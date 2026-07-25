#!/bin/bash
# ci_prepare_ssh.sh — source-d by CI before_script blocks.
#
# Usage:
#   source .ci/ci_prepare_ssh.sh <TARGET_VAR_NAME>
#
# Where TARGET_VAR_NAME is the environment variable holding the
# Ansible target group (e.g. DETECT_TARGETS, TARGET_HOSTS).
#
# The script:
#   1. Assert the target var is set and non-empty
#   2. Write SSH_PRIVATE_KEY to ~/.ssh/ci_ansible_key
#   3. Resolve target hostnames via ansible --list-hosts
#   4. Resolve ansible_host IPs via .ci/resolve_targets.py
#   5. Run ssh-keyscan against the resolved IPs
#   6. Write ./.ansible/known_hosts
#
# Leaves ~/.ssh/ci_ansible_key, .ansible/known_hosts, and
# /tmp/ansible_target_names.txt, /tmp/ansible_hosts.txt for the
# caller (script: section) to use.

set -eu

_ci_target_var="${1:?Usage: source .ci/ci_prepare_ssh.sh <TARGET_VAR_NAME>}"

# Evaluate the variable name to get the actual target value
eval "_ci_target_val=\${${_ci_target_var}}"
if [ -z "${_ci_target_val:-}" ]; then
  echo "ERROR: ${_ci_target_var} is required" >&2
  exit 1
fi

# Assert required CI variables
: "${SSH_PRIVATE_KEY:?SSH_PRIVATE_KEY is required}"
: "${ANSIBLE_USER:?ANSIBLE_USER is required}"

# ── SSH key setup ──
mkdir -p ~/.ssh .ansible
chmod 700 ~/.ssh
printf '%s\n' "$SSH_PRIVATE_KEY" > ~/.ssh/ci_ansible_key
chmod 600 ~/.ssh/ci_ansible_key

# ── Resolve target hostnames ──
ansible_extra_args="${_CI_ANSIBLE_EXTRA_ARGS:-}"
ansible $ansible_extra_args -i inventory/hosts.yml "${_ci_target_val}" --list-hosts \
  | tail -n +2 \
  | tr -d ' ' \
  > /tmp/ansible_target_names.txt

if [ ! -s /tmp/ansible_target_names.txt ]; then
  echo "ERROR: No hosts matched ${_ci_target_var}=${_ci_target_val}" >&2
  exit 1
fi

# ── Resolve IPs ──
python3 .ci/resolve_targets.py /tmp/ansible_target_names.txt > /tmp/ansible_hosts.txt

if [ ! -s /tmp/ansible_hosts.txt ]; then
  echo "ERROR: No ansible_host entries found for ${_ci_target_var}=${_ci_target_val}" >&2
  exit 1
fi

# ── ssh-keyscan ──
xargs -r -n 1 ssh-keyscan -T 5 -H -t ed25519,rsa < /tmp/ansible_hosts.txt > .ansible/known_hosts || true
chmod 644 .ansible/known_hosts

echo "SSH prepared for ${_ci_target_var}=${_ci_target_val}: $(wc -l < /tmp/ansible_hosts.txt) host(s)"
