#!/usr/bin/env bash

set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
config_file="${repo_root}/ansible/ansible.cfg"
tasks_file="${repo_root}/ansible/roles/host_firewall/tasks/main.yml"
rules_file="${repo_root}/ansible/roles/host_firewall/tasks/rules.yml"
validation_file="${repo_root}/ansible/roles/host_firewall/tasks/validate.yml"
fixtures_dir="${repo_root}/tests/fixtures/ansible"
expected_tasks='---
- name: Configure the host firewall
  ansible.builtin.import_tasks: rules.yml'
expected_rules='---
- name: Allow SSH over the private Tailscale interface
  community.general.ufw:
    rule: allow
    direction: in
    interface: tailscale0
    proto: tcp
    to_port: "22"
    comment: Rivet Tailscale administrative SSH

- name: Remove unrestricted SSH access
  community.general.ufw:
    rule: allow
    direction: in
    proto: tcp
    to_port: "22"
    delete: true

- name: Deny other incoming traffic by default
  community.general.ufw:
    default: deny
    direction: incoming

- name: Allow outgoing traffic by default
  community.general.ufw:
    default: allow
    direction: outgoing

- name: Enable low-volume firewall logging
  community.general.ufw:
    logging: low

- name: Enable the host firewall
  community.general.ufw:
    state: enabled'

if [[ "$(<"${rules_file}")" != "${expected_rules}" ]]; then
  echo "Unexpected host firewall policy or task order in ${rules_file}" >&2
  exit 1
fi

if [[ "$(<"${tasks_file}")" != "${expected_tasks}" ]]; then
  echo "Unexpected host firewall task composition in ${tasks_file}" >&2
  exit 1
fi

if [[ -e "${validation_file}" ]]; then
  echo "Retired public-address validation remains in ${validation_file}" >&2
  exit 1
fi

ANSIBLE_CONFIG="${config_file}" \
  ansible-playbook \
    --inventory 'localhost,' \
    --syntax-check \
    "${fixtures_dir}/host-firewall.yml"

echo "The host firewall permits SSH only through Tailscale before enabling UFW."
