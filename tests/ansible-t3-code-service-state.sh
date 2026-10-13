#!/usr/bin/env bash

set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
config_file="${repo_root}/ansible/ansible.cfg"
service_file="${repo_root}/ansible/roles/t3_code/tasks/service.yml"
playbook="${repo_root}/tests/fixtures/ansible/t3-code.yml"
expected_state='- name: Read T3 Code service enabled state
  ansible.builtin.command:
    argv:
      - systemctl
      - --user
      - is-enabled
      - t3code.service
  become: true
  become_user: rivet
  environment:
    XDG_RUNTIME_DIR: "/run/user/{{ getent_passwd.rivet[1] }}"
    DBUS_SESSION_BUS_ADDRESS: "unix:path=/run/user/{{ getent_passwd.rivet[1] }}/bus"
  register: t3_code_service_enabled
  changed_when: false
  failed_when: false
  when: not ansible_check_mode

- name: Read T3 Code service active state
  ansible.builtin.command:
    argv:
      - systemctl
      - --user
      - is-active
      - t3code.service
  become: true
  become_user: rivet
  environment:
    XDG_RUNTIME_DIR: "/run/user/{{ getent_passwd.rivet[1] }}"
    DBUS_SESSION_BUS_ADDRESS: "unix:path=/run/user/{{ getent_passwd.rivet[1] }}/bus"
  register: t3_code_service_active
  changed_when: false
  failed_when: false
  when: not ansible_check_mode

- name: Verify T3 Code service supervision
  ansible.builtin.assert:
    that:
      - t3_code_service_enabled.rc == 0
      - t3_code_service_enabled.stdout == "enabled"
      - t3_code_service_active.rc == 0
      - t3_code_service_active.stdout == "active"
    fail_msg: T3 Code must be enabled and active under the rivet systemd user manager
  when: not ansible_check_mode'

if [[ ! -f "$service_file" ]] || [[ "$(<"$service_file")" != *"$expected_state"* ]]; then
  echo "T3 Code service state must be verified through the rivet systemd user manager" >&2
  exit 1
fi

ANSIBLE_CONFIG="$config_file" \
  ansible-playbook \
    --inventory 'localhost,' \
    --syntax-check \
    "$playbook"

echo "The T3 Code systemd user service must be enabled and active."
