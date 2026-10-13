#!/usr/bin/env bash

set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
config_file="${repo_root}/ansible/ansible.cfg"
service_file="${repo_root}/ansible/roles/t3_code/tasks/service.yml"
playbook="${repo_root}/tests/fixtures/ansible/t3-code.yml"
expected_install='- name: Read the T3 Code service account
  ansible.builtin.getent:
    database: passwd
    key: rivet

- name: Wait for the T3 Code user manager
  ansible.builtin.wait_for:
    path: "/run/user/{{ getent_passwd.rivet[1] }}/bus"
    state: present
    timeout: 30
  when: not ansible_check_mode

- name: Install the T3 Code user service
  ansible.builtin.command:
    argv:
      - /home/rivet/.local/bin/t3
      - service
      - install
  become: true
  become_user: rivet
  environment:
    HOME: /home/rivet
    PATH: /home/rivet/.local/bin:/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin
    XDG_RUNTIME_DIR: "/run/user/{{ getent_passwd.rivet[1] }}"
    DBUS_SESSION_BUS_ADDRESS: "unix:path=/run/user/{{ getent_passwd.rivet[1] }}/bus"
  register: t3_code_service_install
  changed_when: >-
    "Installed T3 Code service" in t3_code_service_install.stdout or
    "Updated T3 Code service" in t3_code_service_install.stdout
  when: not ansible_check_mode'

if [[ ! -f "$service_file" ]] || [[ "$(<"$service_file")" != *"$expected_install"* ]]; then
  echo "The upstream T3 service installer must run as rivet against its systemd user manager" >&2
  exit 1
fi

ANSIBLE_CONFIG="$config_file" \
  ansible-playbook \
    --inventory 'localhost,' \
    --syntax-check \
    "$playbook"

echo "The upstream T3 Code service installer runs only as the non-root service user."
