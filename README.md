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
│   ├── lifecycle/
│   │   ├── 00-detect.yml
│   │   ├── 10-provision.yml
│   │   ├── 20-baseline.yml
│   │   └── 30-apt-upgrade.yml
│   ├── deploy/
│   │   ├── cloudflare-utils.yml
│   │   ├── komodo.yml
│   │   ├── monitoring-stack.yml
│   │   └── renovate.yml
│   └── discovery/
│       └── docker-state.yml
├── roles/
│   ├── users/
│   ├── ssh_hardening/
│   ├── apt_timers/
│   ├── motd_dynamic/
│   ├── docker_prep/
│   ├── k3s_agent_user/
│   ├── komodo_deploy/
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

In CI, the intended path is now to use the same `ANSIBLE_USER` and `SSH_PRIVATE_KEY` values used for normal lifecycle access, with `bootstrap_user` set to that same automation user, rather than maintaining a separate bootstrap SSH key path.

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

`00-detect.yml` now acts as the lifecycle state detection step used by CI before dry-run, provisioning, and lifecycle apply jobs.

It checks for the provision marker and writes host lists for:
- provisioned hosts
- unprovisioned hosts
- unreachable hosts

Hosts that are unreachable during detection are still recorded separately, but are treated as unprovisioned for bootstrap workflows so first-contact provisioning can continue without the detect step hard-failing.

This lets the pipeline distinguish between hosts that are ready for recurring lifecycle convergence and hosts that still need first-contact bootstrap.

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

Conflicting packages are removed without `apt purge` so distro package post-removal scripts do not try to wipe live Docker state under `/var/lib/docker` during canary migration.

**Perform system upgrade**
```bash
ansible-playbook -i inventory/hosts.yml playbooks/lifecycle/30-apt-upgrade.yml
```

## CI Validation and Dry-Run Workflow

This repository uses CI checks to make lifecycle changes safer before merge.

The CI flow is lifecycle-aware:
- validate playbook syntax first
- detect which targeted hosts are already provisioned
- dry-run lifecycle only against provisioned hosts
- allow provisioning only against unprovisioned hosts

This avoids the deadlock where a brand-new host breaks the lifecycle dry-run before the provisioning job can run.

### `ansible-validate`

Runs syntax checks against the main playbooks on:
* merge requests
* commits to the default branch

This catches YAML, playbook, and role wiring errors without contacting any remote hosts.

### `ansible-detect-provision-state`

Runs `playbooks/lifecycle/00-detect.yml` and writes CI artifacts describing which targeted hosts are:
- already provisioned
- still unprovisioned
- unreachable

Default scope:

```bash
DETECT_TARGETS=managed
```

Artifacts written:
- `.ci/detect/provisioned_hosts.txt`
- `.ci/detect/unprovisioned_hosts.txt`
- `.ci/detect/unreachable_hosts.txt`

### `ansible-dry-run-lifecycle`

Runs `site.yml` in Ansible check mode with diff enabled on:
* merge requests
* commits to the default branch

Default scope:

```bash
TARGET_HOSTS=managed
```

The dry-run now intersects the requested target scope with the detected provisioned host list. Unprovisioned hosts are excluded automatically so the recurring lifecycle gate only applies to hosts that have already completed bootstrap.

### `ansible-provision-hosts`

Runs `playbooks/lifecycle/10-provision.yml` as a manual job for first-contact bootstrap.

Default behaviour:
- requires explicit `PROVISION_TARGETS`
- intersects those targets with `.ci/detect/unprovisioned_hosts.txt`
- fails fast if none of the requested targets are still unprovisioned

This keeps provisioning separate from recurring lifecycle convergence while still making the CI flow aware of actual host state.

### `ansible-apply-lifecycle`

Runs the full lifecycle playbook without check mode as a manual job.

Triggering model:
* manual on merge request pipelines after `ansible-validate` and `ansible-dry-run-lifecycle`
* manual on web-triggered pipelines

Default scope:

```bash
LIFECYCLE_TARGETS=managed
```

This job currently runs exactly against the requested `LIFECYCLE_TARGETS` scope rather than intersecting with the detect artifact output. That keeps manual apply flexible while dry-run remains lifecycle-aware.

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

### Concurrency note

`ansible.cfg` uses:

```ini
forks = 5
```

This lower parallelism was chosen after CI dry-run testing showed it to be more reliable across the full managed estate, especially the k3s hosts.

## Compose Deploy Playbooks

Compose-based application deploys live under:

```bash
playbooks/deploy/
```

Current playbooks:
- `playbooks/deploy/komodo.yml`
- `playbooks/deploy/monitoring-stack.yml`
- `playbooks/deploy/cloudflare-utils.yml`
- `playbooks/deploy/renovate.yml`

These playbooks now follow a more generic contract:
- shared path conventions come from inventory (`deploy_root`, `ssh_root`, `compose_repo_root`)
- standard repo URLs are derived from `compose_git_base_url + compose_app_name`
- standard repo branch override env vars are derived from app name
- standard deploy script defaults to `./deploy.sh`
- standard Infisical application path defaults to `/<app-name>/application`
- app-specific targets, credentials, and secret-manager values are still injected at runtime

### Shared defaults and derivation

These values are now shared and do not usually need per-app variables:

- `compose_git_base_url`
  - defaulted in inventory
  - used to derive `ssh://.../<app>.git`
- `compose_repo_branch`
  - defaults to `master`
  - can be overridden with `DEPLOYMENT_<APP>_REPO_BRANCH`
- `compose_deploy_script`
  - defaults to `./deploy.sh`
- `compose_repo_infisical_domain`
  - defaults from `infisical_domain`
- `compose_repo_infisical_application_path`
  - defaults to `/<app-name>/application`
- `compose_repo_env_exports`
  - defaults to exporting `.env` when Infisical sync is enabled

### Required runtime inputs by deploy playbook

These should normally come from CI/CD variables or manual `-e` inputs rather than committed inventory.

#### Komodo

Required:
- `komodo_core_deploy_targets`
- `komodo_periphery_deploy_targets`
- `komodo_repo_deploy_key_private`
- `komodo_git_known_hosts`

Optional:
- `DEPLOYMENT_KOMODO_REPO_BRANCH`
  - overrides repo branch

#### Monitoring stack

Required:
- `monitoring_core_deploy_targets`
- `monitoring_exporter_deploy_targets`
- `monitoring_repo_deploy_key_private`
- `monitoring_git_known_hosts`

Optional:
- `DEPLOYMENT_MONITORING_STACK_REPO_BRANCH`
  - overrides repo branch

#### Cloudflare Utils

Required:
- `cloudflare_utils_deploy_targets`
- `cloudflare_utils_repo_deploy_key_private`
- `cloudflare_utils_git_known_hosts`
- `cloudflare_utils_infisical_project_id`
- `cloudflare_utils_infisical_token`

Optional:
- `DEPLOYMENT_CLOUDFLARE_UTILS_REPO_BRANCH`
  - overrides repo branch
- `DEPLOYMENT_CLOUDFLARE_UTILS_INFISICAL_SYNC_ENABLED`
  - defaults to `true`
  - accepts `1`, `true`, `yes`, `on`

#### Renovate

Required:
- `renovate_deploy_targets`
- `renovate_repo_deploy_key_private`
- `renovate_git_known_hosts`
- `renovate_infisical_project_id`
- `renovate_infisical_token`

Optional:
- `DEPLOYMENT_RENOVATE_REPO_BRANCH`
  - overrides repo branch
- `DEPLOYMENT_RENOVATE_INFISICAL_SYNC_ENABLED`
  - defaults to `true`
  - accepts `1`, `true`, `yes`, `on`

### What the runtime inputs do

- `*_deploy_targets`
  - choose which inventory hosts receive the sync/deploy
- `*_repo_deploy_key_private`
  - SSH private key used to clone the compose repo
- `*_git_known_hosts`
  - pinned Git SSH host keys used for strict host verification
- `*_infisical_project_id`
  - Infisical project to export application secrets from
- `*_infisical_token`
  - token used by the Infisical CLI during export
- `DEPLOYMENT_*_REPO_BRANCH`
  - optional branch override for testing or staged rollouts
- `DEPLOYMENT_*_INFISICAL_SYNC_ENABLED`
  - optional runtime toggle for `.env` export behavior on apps that use Infisical

### Manual examples

**Komodo**
```bash
ansible-playbook -i inventory/hosts.yml playbooks/deploy/komodo.yml \
  -e komodo_core_deploy_targets=devstack-1 \
  -e komodo_periphery_deploy_targets=devstack-1 \
  -e @vars/komodo-secrets.yml
```

**Renovate**
```bash
ansible-playbook -i inventory/hosts.yml playbooks/deploy/renovate.yml \
  -e renovate_deploy_targets=devstack-1 \
  -e @vars/renovate-secrets.yml
```

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
* **manual on merge request pipelines**
* **manual from the GitLab web UI** for ad hoc runs started with **Run pipeline**

This keeps routine patching automated while still allowing on-demand update execution when needed, including MR-side operator testing before merge.

## CI Integration Model

The repository is designed to support CI-driven infrastructure convergence.

Typical flow:
1. Change raised in a merge request
2. CI runs syntax validation automatically
3. CI detects provisioned versus unprovisioned hosts automatically
4. CI runs a non-mutating dry-run of `site.yml` only against provisioned hosts
5. Manual provisioning remains available for new hosts
6. Scheduled pipelines can run the update playbook automatically
7. Manual web-triggered runs remain available for targeted operator actions

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
