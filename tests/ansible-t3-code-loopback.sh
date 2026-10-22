#!/usr/bin/env bash

set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
config_file="${repo_root}/ansible/ansible.cfg"
service_file="${repo_root}/ansible/roles/t3_code/tasks/service.yml"
playbook="${repo_root}/tests/fixtures/ansible/t3-code.yml"
expected_loopback='- name: Maintain T3 Code service override directory
  ansible.builtin.file:
    path: /home/rivet/.config/systemd/user/t3code.service.d
    state: directory
    owner: rivet
    group: rivet
    mode: "0700"

- name: Harden the T3 Code service runtime
  ansible.builtin.copy:
    content: |
      [Service]
      Environment=T3CODE_HOST=127.0.0.1
      Environment=PATH=/home/rivet/.local/bin:/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin
      UMask=0027
    dest: /home/rivet/.config/systemd/user/t3code.service.d/10-loopback.conf
    owner: rivet
    group: rivet
    mode: "0600"
  register: t3_code_loopback_override

- name: Apply T3 Code loopback service override
  ansible.builtin.systemd_service:
    name: t3code.service
    scope: user
    daemon_reload: true
    state: restarted
  become: true
  become_user: rivet
  environment:
    XDG_RUNTIME_DIR: "/run/user/{{ getent_passwd.rivet[1] }}"
    DBUS_SESSION_BUS_ADDRESS: "unix:path=/run/user/{{ getent_passwd.rivet[1] }}/bus"
  when:
    - not ansible_check_mode
    - t3_code_loopback_override.changed'

if [[ ! -f "$service_file" ]] || [[ "$(<"$service_file")" != *"$expected_loopback"* ]]; then
  echo "The T3 Code service must have a private, managed loopback and PATH override" >&2
  exit 1
fi

loopback_line="$(grep -n -- '^- name: Maintain T3 Code service override directory$' "$service_file" | cut -d: -f1)"
state_line="$(grep -n -- '^- name: Read T3 Code service enabled state$' "$service_file" | cut -d: -f1)"
if [[ -z "$loopback_line" ]] || [[ -z "$state_line" ]] || ((loopback_line >= state_line)); then
  echo "The loopback override must be applied before verifying service state" >&2
  exit 1
fi

ANSIBLE_CONFIG="$config_file" \
  ansible-playbook \
    --inventory 'localhost,' \
    --syntax-check \
    "$playbook"

echo "The T3 Code service is explicitly pinned to the loopback interface."
