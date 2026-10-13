#!/usr/bin/env bash

set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
config_file="${repo_root}/ansible/ansible.cfg"
main_file="${repo_root}/ansible/roles/t3_code/tasks/main.yml"
layout_file="${repo_root}/ansible/roles/t3_code/tasks/layout.yml"
playbook="${repo_root}/tests/fixtures/ansible/t3-code.yml"
expected_layout='---
- name: Maintain T3 Code service directories
  ansible.builtin.file:
    path: "{{ item.path }}"
    state: directory
    owner: rivet
    group: rivet
    mode: "{{ item.mode }}"
  loop:
    - path: /home/rivet/.local
      mode: "0750"
    - path: /home/rivet/.local/bin
      mode: "0750"
    - path: /home/rivet/.t3
      mode: "0700"
    - path: /home/rivet/.t3/runtime
      mode: "0750"
    - path: /home/rivet/.t3/runtime/versions
      mode: "0750"
    - path: "/home/rivet/.t3/runtime/versions/{{ t3_code_version }}"
      mode: "0750"

- name: Maintain T3 Code archive cache
  ansible.builtin.file:
    path: /var/cache/rivet/t3-code
    state: directory
    owner: root
    group: root
    mode: "0755"'

if [[ ! -f "$main_file" ]] ||
  ! grep -Fqx -- '- name: Prepare the T3 Code filesystem' "$main_file" ||
  ! grep -Fqx -- '  ansible.builtin.import_tasks: layout.yml' "$main_file"; then
  echo "The T3 Code role must import its filesystem layout" >&2
  exit 1
fi

if [[ ! -f "$layout_file" ]] || [[ "$(<"$layout_file")" != "$expected_layout" ]]; then
  echo "T3 Code state must be private to rivet and its archive cache root-owned" >&2
  exit 1
fi

ANSIBLE_CONFIG="$config_file" \
  ansible-playbook \
    --inventory 'localhost,' \
    --syntax-check \
    "$playbook"

echo "The T3 Code non-root filesystem boundary is valid."
