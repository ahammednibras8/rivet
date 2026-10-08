#!/usr/bin/env bash

set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
config_file="${repo_root}/ansible/ansible.cfg"
test_ip="203.0.113.10"

resolved_inventory="$(
  RIVET_WORKSPACE_IP="${test_ip}" \
    ANSIBLE_CONFIG="${config_file}" \
    ansible rivet-workspace \
      --module-name ansible.builtin.debug \
      --args 'msg={{ ansible_host }}|{{ ansible_user }}'
)"

if ! grep -Fq "${test_ip}|rivet-admin" <<<"${resolved_inventory}"; then
  echo "Inventory did not resolve the runtime IP and SSH user" >&2
  exit 1
fi

if missing_ip_output="$(
  env -u RIVET_WORKSPACE_IP \
    ANSIBLE_CONFIG="${config_file}" \
    ansible rivet-workspace \
      --module-name ansible.builtin.debug \
      --args 'var=ansible_host' 2>&1
)"; then
  echo "Inventory accepted a missing RIVET_WORKSPACE_IP" >&2
  exit 1
fi

if ! grep -Fq "The environment variable 'RIVET_WORKSPACE_IP' is not set" <<<"${missing_ip_output}"; then
  echo "Inventory did not explain the missing RIVET_WORKSPACE_IP" >&2
  exit 1
fi

echo "Ansible inventory requires and resolves the runtime workspace IP."
