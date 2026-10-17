#!/usr/bin/env bash

set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
config_file="${repo_root}/ansible/ansible.cfg"
tasks_file="${repo_root}/ansible/roles/repository_access/tasks/main.yml"
command_file="${repo_root}/ansible/roles/repository_access/files/rivet-repository-allowlist"
playbook="${repo_root}/tests/fixtures/ansible/repository-access.yml"
site_file="${repo_root}/ansible/site.yml"

expected_tasks='---
- name: Maintain private Rivet configuration directory
  ansible.builtin.file:
    path: /home/rivet/.config/rivet
    state: directory
    owner: root
    group: rivet
    mode: "0750"

- name: Install repository approval command
  ansible.builtin.copy:
    src: rivet-repository-allowlist
    dest: /home/rivet/.local/bin/rivet-repository-allowlist
    owner: root
    group: rivet
    mode: "0750"'

if [[ ! -f "$tasks_file" ]] || [[ "$(<"$tasks_file")" != "$expected_tasks" ]]; then
  echo "Repository access must keep its command and approval directory read-only to the service account" >&2
  exit 1
fi

if [[ ! -x "$command_file" ]]; then
  echo "The repository approval command must remain executable" >&2
  exit 1
fi

if ! grep -Fq '    - role: repository_access' "$site_file"; then
  echo "The repository access role must be enabled in the workspace playbook" >&2
  exit 1
fi

if find "${repo_root}/ansible" -type f \( \
    -name 'repositories.json' -o \
    -name '*allowlist*.json' \
  \) -print -quit | grep -q .; then
  echo "A real repository approval manifest must never be committed to Ansible" >&2
  exit 1
fi

ANSIBLE_CONFIG="$config_file" \
  ansible-playbook \
    --inventory 'localhost,' \
    --syntax-check \
    "$playbook"

echo "The repository approval command has a private, immutable installation boundary."
