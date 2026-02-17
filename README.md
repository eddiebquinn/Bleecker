# 🕸️ Bartmoss Ansible Playbooks
This repository manages baseline configuration, provisioning, and lifecycle automation for the Bartmoss homelab infrastructure.

> ⚠️ **Read-Only Mirror**
> This repository is a public projection for portfolio purposes.
> The canonical source of truth lives on my self-managed GitLab infrastructure.
> Running systems are built from that source.

## Overview
The design goal is reproducibility, idempotency, and clean separation of concerns:
* Static inventory defines *what hosts exist*
* Dynamic grouping defines *what lifecycle state they are in*
* Roles define *how configuration is applied*
* Playbooks orchestrate lifecycle phases
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

Provisioning is dynamic.

A host is considered **provisioned** when the marker file exists:

```
/etc/markers/provisioned
```

Lifecycle flow:

### 1. `00-detect.yml`

* Checks for provision marker
* Dynamically groups hosts without it into `needs_provisioning`

### 2. `10-provision.yml`

* Bootstraps `semaphore-agent` using a `bootstrap_user`
* Establishes initial SSH access
* Creates the provision marker file

### 3. `20-baseline.yml`

Applies recurring baseline configuration using modular roles:
* `users` — system users and SSH keys
* `ssh_hardening` — hardened SSH configuration
* `apt_timers` — disable/mask unattended timers
* `motd_dynamic` — dynamic system MOTD
* `docker_prep` — docker-agent setup for docker hosts
* `k3s_agent_user` — k3s-agent configuration for k3s hosts

This separation keeps lifecycle orchestration thin and pushes logic into reusable, testable roles.

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
**Full lifecycle run**
```bash
ansible-playbook -i inventory/hosts.yml site.yml
```

**Provision a specific new host**
```bash
ansible-playbook -i inventory/hosts.yml site.yml --limit newhost-1
```

**Apply baseline only**
```bash
ansible-playbook -i inventory/hosts.yml playbooks/20-baseline.yml
```

**Perform System Upgrade**
```bash
ansible-playbook -i inventory/hosts.yml playbooks/30-apt-upgrade.yml
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