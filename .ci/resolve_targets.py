#!/usr/bin/env python3
"""
Resolve target hostnames to ansible_host IPs from inventory/hosts.yml.

Reads target hostnames from stdin (one per line, as produced by
`ansible --list-hosts`), walks the inventory YAML tree, and outputs the
resolved ansible_host IP for each match.

Usage:
  ansible -i inventory/hosts.yml managed --list-hosts | tail -n +2 | tr -d ' ' | resolve_targets.py
  resolve_targets.py /tmp/ansible_target_names.txt
"""

import sys
import yaml
from pathlib import Path


def resolve(inventory_path: str, target_path: str) -> list[str]:
    data = yaml.safe_load(Path(inventory_path).read_text())
    targets = {
        line.strip()
        for line in Path(target_path).read_text().splitlines()
        if line.strip()
    }
    hosts: list[str] = []
    all_hosts = data.get("all", {})

    def walk_children(node):
        if not isinstance(node, dict):
            return
        host_map = node.get("hosts", {})
        if isinstance(host_map, dict):
            for name, attrs in host_map.items():
                if name in targets and isinstance(attrs, dict):
                    host = attrs.get("ansible_host", name)
                    if host not in hosts:
                        hosts.append(host)
        children = node.get("children", {})
        if isinstance(children, dict):
            for child in children.values():
                walk_children(child)

    walk_children(all_hosts)
    return hosts


if __name__ == "__main__":
    if len(sys.argv) > 1:
        target_file = sys.argv[1]
    else:
        # Read from stdin, write to temp file
        stdin_text = sys.stdin.read()
        if not stdin_text.strip():
            print("Error: no target names provided via stdin or argument", file=sys.stderr)
            sys.exit(2)
        target_file = "/tmp/ansible_target_names.txt"
        Path(target_file).write_text(stdin_text)

    inventory_file = "inventory/hosts.yml"
    resolved = resolve(inventory_file, target_file)
    for host in resolved:
        print(host)
