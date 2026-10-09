#!/usr/bin/env bash

set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
config_file="${repo_root}/ansible/ansible.cfg"
packages_file="${repo_root}/ansible/roles/system_baseline/tasks/packages.yml"
playbook="${repo_root}/tests/fixtures/ansible/system-baseline.yml"
expected_packages=$'---\n- name: Install baseline packages\n  ansible.builtin.apt:\n    name:\n      - ca-certificates\n      - curl\n      - git\n      - jq\n      - ufw\n      - unattended-upgrades\n    state: present\n    update_cache: true\n    cache_valid_time: 3600'

if [[ "$(<"${packages_file}")" != "${expected_packages}" ]]; then
  echo "Unexpected package policy in ${packages_file}" >&2
  exit 1
fi

ANSIBLE_CONFIG="${config_file}" \
  ansible-playbook \
    --inventory 'localhost,' \
    --syntax-check \
    "${playbook}"

echo "The system baseline package policy is valid."
