#!/usr/bin/env bash

set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
config_file="${repo_root}/ansible/ansible.cfg"
main_file="${repo_root}/ansible/roles/t3_code/tasks/main.yml"
packages_file="${repo_root}/ansible/roles/t3_code/tasks/packages.yml"
playbook="${repo_root}/tests/fixtures/ansible/t3-code.yml"
expected_packages='---
- name: Install T3 Code runtime packages
  ansible.builtin.apt:
    name:
      - libasound2t64
      - libatomic1
      - libatk-bridge2.0-0t64
      - libatk1.0-0t64
      - libatspi2.0-0t64
      - libgbm1
      - libxcomposite1
      - libxdamage1
      - libxfixes3
      - libxrandr2
    state: present
    update_cache: true
    cache_valid_time: 3600'

if ! grep -Fqx -- '- name: Install T3 Code runtime dependencies' "$main_file" ||
  ! grep -Fqx -- '  ansible.builtin.import_tasks: packages.yml' "$main_file"; then
  echo "The T3 Code role must import its runtime dependencies" >&2
  exit 1
fi

if [[ ! -f "$packages_file" ]] || [[ "$(<"$packages_file")" != "$expected_packages" ]]; then
  echo "T3 Code must own only its reviewed Ubuntu runtime packages" >&2
  exit 1
fi

packages_line="$(grep -n -- '^- name: Install T3 Code runtime dependencies$' "$main_file" | cut -d: -f1)"
install_line="$(grep -n -- '^- name: Download the reviewed T3 Code release$' "$main_file" | cut -d: -f1)"
if [[ -z "$packages_line" ]] || [[ -z "$install_line" ]] || ((packages_line >= install_line)); then
  echo "T3 Code runtime dependencies must be installed before its release is executed" >&2
  exit 1
fi

ANSIBLE_CONFIG="$config_file" \
  ansible-playbook \
    --inventory 'localhost,' \
    --syntax-check \
    "$playbook"

echo "T3 Code runtime and browser packages are isolated from the host baseline."
