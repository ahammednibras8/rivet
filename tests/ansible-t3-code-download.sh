#!/usr/bin/env bash

set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
main_file="${repo_root}/ansible/roles/t3_code/tasks/main.yml"
install_file="${repo_root}/ansible/roles/t3_code/tasks/install.yml"
expected_download='---
- name: Download reviewed T3 Code release
  ansible.builtin.get_url:
    url: "{{ t3_code_release_url }}"
    dest: "/var/cache/rivet/t3-code/{{ t3_code_release_archive }}"
    checksum: "sha256:{{ t3_code_release_sha256 }}"
    owner: root
    group: root
    mode: "0644"'

if ! grep -Fqx -- '- name: Download the reviewed T3 Code release' "$main_file" ||
  ! grep -Fqx -- '  ansible.builtin.import_tasks: install.yml' "$main_file"; then
  echo "The T3 Code role must import its reviewed-release installation tasks" >&2
  exit 1
fi

if [[ ! -f "$install_file" ]] || [[ "$(<"$install_file")" != *"$expected_download"* ]]; then
  echo "T3 Code must be downloaded from the pinned URL with its pinned SHA-256 checksum" >&2
  exit 1
fi

echo "The reviewed T3 Code archive download is checksum-protected."
