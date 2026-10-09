#!/usr/bin/env bash

set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
config_file="${repo_root}/ansible/ansible.cfg"
tasks_file="${repo_root}/ansible/roles/ssh_hardening/tasks/main.yml"
handlers_file="${repo_root}/ansible/roles/ssh_hardening/handlers/main.yml"
playbook="${repo_root}/tests/fixtures/ansible/ssh-hardening.yml"
expected_tasks='---
- name: Maintain SSH configuration directory
  ansible.builtin.file:
    path: /etc/ssh/sshd_config.d
    state: directory
    owner: root
    group: root
    mode: "0755"

- name: Install SSH hardening policy
  ansible.builtin.copy:
    src: 00-rivet-hardening.conf
    dest: /etc/ssh/sshd_config.d/00-rivet-hardening.conf
    owner: root
    group: root
    mode: "0644"
    validate: /usr/sbin/sshd -t -f %s
  notify: Reload SSH'
expected_handlers='---
- name: Validate complete SSH configuration
  ansible.builtin.command: /usr/sbin/sshd -t
  changed_when: false
  listen: Reload SSH

- name: Reload SSH service
  ansible.builtin.service:
    name: ssh
    state: reloaded
  listen: Reload SSH'

if [[ "$(<"${tasks_file}")" != "${expected_tasks}" ]]; then
  echo "Unexpected SSH role tasks in ${tasks_file}" >&2
  exit 1
fi

if [[ "$(<"${handlers_file}")" != "${expected_handlers}" ]]; then
  echo "Unexpected SSH role handlers in ${handlers_file}" >&2
  exit 1
fi

ANSIBLE_CONFIG="${config_file}" \
  ansible-playbook \
    --inventory 'localhost,' \
    --syntax-check \
    "${playbook}"

echo "The SSH hardening role validates before reloading SSH."
