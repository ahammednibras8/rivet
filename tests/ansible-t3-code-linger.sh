#!/usr/bin/env bash

set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
config_file="${repo_root}/ansible/ansible.cfg"
main_file="${repo_root}/ansible/roles/t3_code/tasks/main.yml"
service_file="${repo_root}/ansible/roles/t3_code/tasks/service.yml"
playbook="${repo_root}/tests/fixtures/ansible/t3-code.yml"
expected_linger='---
- name: Keep the T3 Code service user active after logout
  ansible.builtin.command:
    argv:
      - loginctl
      - enable-linger
      - rivet
    creates: /var/lib/systemd/linger/rivet'

if ! grep -Fqx -- '- name: Prepare the supervised T3 Code service' "$main_file" ||
  ! grep -Fqx -- '  ansible.builtin.import_tasks: service.yml' "$main_file"; then
  echo "The T3 Code role must import its supervised user-service tasks" >&2
  exit 1
fi

if [[ ! -f "$service_file" ]] || [[ "$(<"$service_file")" != *"$expected_linger"* ]]; then
  echo "Only loginctl may use administrator authority to keep the rivet user manager running" >&2
  exit 1
fi

ANSIBLE_CONFIG="$config_file" \
  ansible-playbook \
    --inventory 'localhost,' \
    --syntax-check \
    "$playbook"

echo "Systemd lingering is enabled idempotently for the non-root T3 Code service user."
