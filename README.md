# 🎛️ Bleecker
This repository manages baseline configuration, provisioning, and lifecycle automation for the Bartmoss homelab infrastructure.

> ⚠️ **Read-Only Mirror**
> This repository is a public projection for portfolio purposes.
> The canonical source of truth lives on my self-managed GitLab infrastructure.
> Running systems are built from that source.

## Overview
The design goal is reproducibility, idempotency, and clean separation of concerns:
* Static inventory defines *what hosts exist*
* Roles define *how configuration is applied*
* Playbooks orchestrate lifecycle phases
* New-host bootstrap is explicit
* Recurring lifecycle runs stay boring and reliable
* No manual inventory mutation
* No secrets stored in Git

## Repository Structure

```
.
├── ansible.cfg
├── site.yml
├── inventory/
│   ├── hosts.yml
│   └── group_vars/
│       ├── all.yml
│       ├── docker_hosts.yml
│       └── k3s_hosts.yml
├── playbooks/
│   ├── 00-detect.yml
│   ├── 10-provision.yml
│   ├── 20-baseline.yml
│   ├── 30-apt-upgrade.yml
│   └── 40-komodo.yml (optional deployment playbook)
├── roles/
│   ├── users/
│   ├── ssh_hardening/
│   ├── apt_timers/
│   ├── motd_dynamic/
│   ├── docker_prep/
│   ├── k3s_agent_user/
│   └── ...
├── flake.nix
├── flake.lock
├── .envrc
└── README.md
```

## Development Environment

This repository includes a Nix-based development environment:
* `flake.nix`
* `flake.lock`
* `.envrc`

These files define and pin the local development shell used to work on this repository. They ensure contributors enter a consistent, reproducible environment when making changes.

They are strictly for local development and do not affect runtime behaviour on managed hosts.

## Inventory

Inventory is static and located in:

```
inventory/hosts.yml
```

It defines:
* Hostnames
* IP addresses
* MAC addresses
* Functional group membership (`docker_hosts`, `k3s_hosts`, `singular_hosts`, etc.)

Inventory does **not** track lifecycle state.

All configuration values are defined via:

```
inventory/group_vars/
```

Host groups are used to scope configuration cleanly without conditionals scattered throughout tasks.

## Provisioning Model

Provisioning is explicit.

A host is considered **provisioned** when the marker file exists:

```
/etc/markers/provisioned
```

Recommended flow:

### 1. `10-provision.yml`

Run this explicitly for **new hosts only**.

It:
* Connects using a provided `bootstrap_user`
* Creates the `semaphore-agent` automation user
* Installs the supplied `semaphore_agent_authorized_key`
* Creates the provision marker file

Required bootstrap vars:
* `bootstrap_user`
* `semaphore_agent_authorized_key`

These should be passed at runtime or supplied via a non-committed vars file.

### 2. `20-baseline.yml`

Applies recurring baseline configuration using modular roles:
* `users` — system users and SSH keys
* `ssh_hardening` — hardened SSH configuration
* `apt_timers` — disable/mask unattended timers
* `motd_dynamic` — dynamic system MOTD
* `docker_prep` — docker-agent setup for docker hosts, with Docker package standardisation scaffolding available behind a safe toggle
* `k3s_agent_user` — k3s-agent configuration for k3s hosts

### 3. `site.yml`

`site.yml` is intentionally limited to recurring baseline runs so normal lifecycle convergence does not depend on first-contact bootstrap logic.

### Note on `00-detect.yml`

`00-detect.yml` remains in the repository as an experimental detection helper, but it is not part of the default recurring lifecycle path.

This separation keeps recurring runs reliable and makes new-host onboarding more predictable.

## Role-Based Design
Baseline configuration is implemented as composable Ansible roles under:

```
roles/
```

Each role:
* Has safe defaults (`defaults/main.yml`)
* Is gated via inventory group vars or role-level conditionals
* Remains idempotent
* Avoids embedded secrets
* Can be reused in other playbooks

This structure enables CI-driven deployments and selective automation without monolithic playbooks.

## Running
**Recurring lifecycle run**
```bash
ansible-playbook -i inventory/hosts.yml site.yml
```

**Bootstrap a specific new host**
```bash
ansible-playbook -i inventory/hosts.yml playbooks/lifecycle/10-provision.yml \
  --limit newhost-1 \
  -e bootstrap_user=root \
  -e "semaphore_agent_authorized_key=$(cat ~/.ssh/id_ed25519.pub)"
```

**Apply baseline only**
```bash
ansible-playbook -i inventory/hosts.yml playbooks/lifecycle/20-baseline.yml
```

### Docker standardisation note

For `docker_hosts`, the `docker_prep` role now contains scaffolding for Docker package cleanup and installation using Docker's official apt repository.

Current safety posture:

* `docker_manage_packages` defaults to `false`
* package standardisation is therefore **not** active by default in normal lifecycle runs yet
* this is intentional so discovery, canary rollout, and cleanup logic can be validated before broad rollout

The intended target package set is:

* `docker-ce`
* `docker-ce-cli`
* `containerd.io`
* `docker-buildx-plugin`
* `docker-compose-plugin`

The intended conflicting package cleanup set includes:

* `docker.io`
* `docker-compose`
* `docker-compose-v2`
* `docker-doc`
* `podman-docker`
* `containerd`
* `runc`

**Perform system upgrade**
```bash
ansible-playbook -i inventory/hosts.yml playbooks/lifecycle/30-apt-upgrade.yml
```

## CI Validation and Dry-Run Workflow

This repository uses CI checks to make lifecycle changes safer before merge.

### `ansible-validate`

Runs syntax checks against the main playbooks on:
* merge requests
* commits to the default branch

This catches YAML, playbook, and role wiring errors without contacting any remote hosts.

### `ansible-dry-run-lifecycle`

Runs `site.yml` in Ansible check mode with diff enabled on:
* merge requests
* commits to the default branch

Default scope:

```bash
TARGET_HOSTS=managed
```

This means the dry-run is treated as a real CI gate for the recurring lifecycle path while remaining non-mutating.

### Required CI/CD Variables

The SSH-backed jobs require these project-level CI/CD variables:

* `ANSIBLE_USER`
  * SSH username used by the CI runner to connect to managed hosts
* `SSH_PRIVATE_KEY`
  * Private key matching a public key already trusted on the managed hosts

The pipeline builds `.ansible/known_hosts` dynamically via `ssh-keyscan` for the targeted hosts before running Ansible.

### Manual ad hoc runs

The pipeline can still be run manually from the GitLab UI.

Useful examples:

```bash
TARGET_HOSTS=arrstack-1
TARGET_HOSTS=arrstack-1:mediastack-1
TARGET_HOSTS=docker_hosts
TARGET_HOSTS=k3s_hosts
TARGET_HOSTS=managed
```

### Docker discovery runs

A manual CI job is available for discovery work against Docker hosts without changing them.

Job:

```text
ansible-discover-docker-state
```

Default scope:

```bash
DISCOVERY_TARGETS=docker_hosts
```

The job connects to the target hosts over SSH and collects Docker-related state into a pipeline artifact, including:

* Docker Engine version
* Docker client/server API versions
* Compose plugin version
* installed Docker-related packages
* apt package policy output
* Docker-related apt sources
* Docker service enabled/active state
* whether `docker info` succeeds

This is intended for inventory and migration planning before standardising Docker across the estate.

### Concurrency note

`ansible.cfg` uses:

```ini
forks = 5
```

This lower parallelism was chosen after CI dry-run testing showed it to be more reliable across the full managed estate, especially the k3s hosts.

## Automated Updates

Updates are handled by the `ansible-apply-updates` CI job.

### Behaviour

* runs `playbooks/lifecycle/30-apt-upgrade.yml`
* waits only for `ansible-validate`, so update runs are not blocked by the lifecycle dry-run stage
* targets `managed` by default via:

```bash
UPDATE_TARGETS=managed
```

* uses the same SSH CI variables and host key bootstrap flow as the lifecycle dry-run
* runs apt in non-interactive mode to avoid CI hangs caused by package prompts or `needrestart`
* can reboot hosts when the playbook determines a reboot is required
* performs `autoremove` after upgrades

### Triggering model

* **automatic on scheduled pipelines**
* **manual from the GitLab web UI** for ad hoc runs started with **Run pipeline**

This keeps routine patching automated while still allowing on-demand update execution when needed.

## CI Integration Model

The repository is designed to support CI-driven infrastructure convergence.

Typical flow:
1. Change raised in a merge request
2. CI runs syntax validation automatically
3. CI runs a non-mutating dry-run of `site.yml` automatically
4. Scheduled pipelines can run the update playbook automatically
5. Manual web-triggered runs remain available for targeted operator actions

This enables:
* safer Git-triggered infrastructure changes
* deterministic validation before merge
* automated patching for the managed estate
* less reliance on ad hoc manual SSH orchestration

## Secrets Handling
Secrets are not stored in this repository.

Sensitive values are injected at runtime via:
* CI variables
* Environment variables
* External secrets manager (e.g. Infisical)

Sensitive tasks use `no_log: true` where appropriate to prevent credential leakage in logs.

## Design Principles
* Idempotent playbooks
* Deterministic execution
* Role-driven modularity
* Separation of bootstrap and operational identities
* No snowflake state
* Git as the source of truth
* Automation over manual intervention
