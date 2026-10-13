#!/usr/bin/env bash

set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
config_file="${repo_root}/ansible/ansible.cfg"
install_file="${repo_root}/ansible/roles/t3_code/tasks/install.yml"
playbook="${repo_root}/tests/fixtures/ansible/t3-code.yml"
expected_link='- name: Link verified T3 Code release
  ansible.builtin.file:
    src: "/home/rivet/.t3/runtime/versions/{{ t3_code_version }}/t3"
    dest: /home/rivet/.local/bin/t3
    state: link
    owner: rivet
    group: rivet
    force: true'

if [[ ! -f "$install_file" ]] || [[ "$(<"$install_file")" != *"$expected_link"* ]]; then
  echo "The user-facing T3 command must link only to the verified versioned release" >&2
  exit 1
fi

ANSIBLE_CONFIG="$config_file" \
  ansible-playbook \
    --inventory 'localhost,' \
    --syntax-check \
    "$playbook"

echo "The T3 Code command links to the verified versioned release."
