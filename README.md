# Bartmoss Ansible Playbooks
This repository manages baseline configuration, provisioning, and lifecycle automation for the Bartmoss homelab infrastructure.

The design goal is reproducibility, idempotency, and clean separation of concerns:
* Static inventory defines *what hosts exist*
* Dynamic grouping defines *what lifecycle state they are in*
* Playbooks converge hosts into desired state
* No manual inventory mutation
* No secrets stored in Git

## Repository Structure

```
.
├── site.yml
├── inventory/
│   ├── hosts.yml
│   └── group_vars/
│       └── all.yml
├── playbooks/
│   ├── 00-detect.yml
│   ├── 10-provision.yml
│   ├── 20-baseline.yml
│   └── 30-apt-upgrade.yml
└── README.md
```


## Inventory

Inventory is static and located in:

```
inventory/hosts.yml
```

It defines:
* Hostnames
* IP addresses
* MAC addresses
* Functional group membership (docker-hosts, k3s-hosts, etc.)

Inventory does **not** track lifecycle state.

## Provisioning Model

Provisioning is dynamic.

A host is considered **provisioned** when the marker file exists:

```
/etc/bartmoss/provisioned
```

Lifecycle flow:

1. `00-detect.yml`

   * Checks for provision marker
   * Dynamically groups hosts without it into `needs_provisioning`

2. `10-provision.yml`

   * Bootstraps `semaphore-agent` using a `bootstrap_user`
   * Hardens SSH
   * Creates the provision marker file

3. `20-baseline.yml`

   * Applies recurring baseline configuration
   * Ensures packages, users, services, and system state converge

This approach avoids editing inventory files during automation.

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

**Perform system upgrade**
```bash
ansible-playbook -i inventory/hosts.yml playbooks/30-apt-upgrade.yml
```

## Secrets Handling
Secrets are not stored in this repository.

Passwords and private keys are injected at runtime via:
* CI variables
* Environment variables
* External secrets manager (Infisical)

Sensitive tasks use `no_log: true` to prevent credential leakage in logs.

## Design Principles
* Idempotent playbooks
* Deterministic execution
* Separation of bootstrap and operational identities
* No snowflake state
* Git as the source of truth
* Automation over manual intervention