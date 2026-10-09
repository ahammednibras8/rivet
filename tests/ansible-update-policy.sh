#!/usr/bin/env bash

set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
config_file="${repo_root}/ansible/ansible.cfg"
updates_file="${repo_root}/ansible/roles/system_baseline/tasks/updates.yml"
playbook="${repo_root}/tests/fixtures/ansible/system-baseline.yml"
expected_updates=$'---\n- name: Enable daily unattended upgrades\n  ansible.builtin.copy:\n    content: |\n      APT::Periodic::Update-Package-Lists "1";\n      APT::Periodic::Unattended-Upgrade "1";\n      Unattended-Upgrade::Automatic-Reboot "false";\n    dest: /etc/apt/apt.conf.d/20auto-upgrades\n    owner: root\n    group: root\n    mode: "0644"\n\n- name: Enable APT maintenance timers\n  ansible.builtin.systemd_service:\n    name: "{{ item }}"\n    enabled: true\n    state: started\n  loop:\n    - apt-daily.timer\n    - apt-daily-upgrade.timer'

if [[ "$(<"${updates_file}")" != "${expected_updates}" ]]; then
  echo "Unexpected automatic-update policy in ${updates_file}" >&2
  exit 1
fi

ANSIBLE_CONFIG="${config_file}" \
  ansible-playbook \
    --inventory 'localhost,' \
    --syntax-check \
    "${playbook}"

echo "The automatic security-update policy is valid."
