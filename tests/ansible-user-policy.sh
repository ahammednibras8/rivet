#!/usr/bin/env bash

set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
config_file="${repo_root}/ansible/ansible.cfg"
users_file="${repo_root}/ansible/roles/system_baseline/tasks/users.yml"
playbook="${repo_root}/tests/fixtures/ansible/system-baseline.yml"
expected_users=$'---\n- name: Create Rivet service group\n  ansible.builtin.group:\n    name: rivet\n    system: true\n    state: present\n\n- name: Create Rivet service account\n  ansible.builtin.user:\n    name: rivet\n    comment: Rivet service account\n    group: rivet\n    groups: ""\n    home: /home/rivet\n    shell: /bin/bash\n    create_home: true\n    system: true\n    password_lock: true\n    state: present'

if [[ "$(<"${users_file}")" != "${expected_users}" ]]; then
  echo "Unexpected service-account policy in ${users_file}" >&2
  exit 1
fi

ANSIBLE_CONFIG="${config_file}" \
  ansible-playbook \
    --inventory 'localhost,' \
    --syntax-check \
    "${playbook}"

echo "The non-root service-account policy is valid."
