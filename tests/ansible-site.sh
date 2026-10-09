#!/usr/bin/env bash

set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
config_file="${repo_root}/ansible/ansible.cfg"
playbook="${repo_root}/ansible/site.yml"
expected_playbook='---
- name: Configure the Rivet workspace
  hosts: rivet_workspace
  become: true
  gather_facts: false
  any_errors_fatal: true

  pre_tasks:
    - name: Wait for cloud-init bootstrap
      ansible.builtin.raw: cloud-init status --wait
      changed_when: false
      check_mode: false

    - name: Gather workspace facts
      ansible.builtin.setup:

  roles:
    - role: system_baseline
    - role: ssh_hardening
    - role: host_firewall'

if [[ "$(<"${playbook}")" != "${expected_playbook}" ]]; then
  echo "Unexpected role composition or execution order in ${playbook}" >&2
  exit 1
fi

RIVET_WORKSPACE_IP="203.0.113.10" \
  RIVET_OPERATOR_IPV4_CIDR="198.51.100.42/32" \
  ANSIBLE_CONFIG="${config_file}" \
  ansible-playbook --syntax-check "${playbook}"

echo "The workspace playbook composes the roles in the safe order."
