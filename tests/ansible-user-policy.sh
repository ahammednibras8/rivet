#!/usr/bin/env bash

set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
config_file="${repo_root}/ansible/ansible.cfg"
users_file="${repo_root}/ansible/roles/system_baseline/tasks/users.yml"
playbook="${repo_root}/tests/fixtures/ansible/system-baseline.yml"
expected_users='---
- name: Create Rivet service group
  ansible.builtin.group:
    name: rivet
    system: true
    state: present

- name: Create Rivet service account
  ansible.builtin.user:
    name: rivet
    comment: Rivet service account
    group: rivet
    groups: ""
    home: /home/rivet
    shell: /bin/bash
    create_home: true
    system: true
    password_lock: true
    state: present

- name: Maintain Rivet administrative account
  ansible.builtin.user:
    name: rivet-admin
    comment: Rivet administrator
    groups:
      - adm
      - sudo
    append: false
    home: /home/rivet-admin
    shell: /bin/bash
    create_home: true
    password_lock: true
    state: present

- name: Maintain passwordless administrative access
  ansible.builtin.copy:
    content: |
      rivet-admin ALL=(ALL) NOPASSWD:ALL
    dest: /etc/sudoers.d/rivet-admin
    owner: root
    group: root
    mode: "0440"
    validate: /usr/sbin/visudo -cf %s

- name: Maintain administrative SSH access
  ansible.builtin.import_tasks: ssh_access.yml'

if [[ "$(<"${users_file}")" != "${expected_users}" ]]; then
  echo "Unexpected service-account policy in ${users_file}" >&2
  exit 1
fi

ANSIBLE_CONFIG="${config_file}" \
  ansible-playbook \
    --inventory 'localhost,' \
    --syntax-check \
    "${playbook}"

echo "The administrative and non-root service-account policies are valid."
