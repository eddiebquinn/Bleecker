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
* `docker_prep` — docker-agent setup for docker hosts
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

**Perform system upgrade**
```bash
ansible-playbook -i inventory/hosts.yml playbooks/lifecycle/30-apt-upgrade.yml
```

## CI Integration Model

The repository is designed to support CI-driven infrastructure convergence.

Typical flow:
1. Change pushed to `master`
2. CI runner clones this repository
3. CI executes targeted playbooks (e.g. `40-komodo.yml`)
4. Hosts converge automatically

This enables:
* Git-triggered container deployments
* Deterministic infra changes
* No manual SSH orchestration

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