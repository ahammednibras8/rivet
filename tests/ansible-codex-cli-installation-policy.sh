#!/usr/bin/env bash

set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
config_file="${repo_root}/ansible/ansible.cfg"
role_dir="${repo_root}/ansible/roles/codex_cli"
playbook="${repo_root}/tests/fixtures/ansible/codex-cli.yml"

expected_main='---
- name: Prepare the standalone Codex CLI filesystem
  ansible.builtin.import_tasks: layout.yml

- name: Install the reviewed standalone Codex CLI release
  ansible.builtin.import_tasks: install.yml'

expected_layout='---
- name: Maintain standalone Codex CLI directories
  ansible.builtin.file:
    path: "{{ item }}"
    state: directory
    owner: root
    group: root
    mode: "0755"
  loop:
    - /var/cache/rivet/codex-cli
    - /opt/rivet
    - /opt/rivet/codex-cli
    - "/opt/rivet/codex-cli/{{ codex_cli_version }}"

- name: Prepare private Codex configuration directory
  ansible.builtin.file:
    path: /home/rivet/.codex
    state: directory
    owner: rivet
    group: rivet
    mode: "0700"'

if [[ "$(<"${role_dir}/tasks/main.yml")" != "$expected_main" ]]; then
  echo "Codex CLI must import only its reviewed layout and installation policies" >&2
  exit 1
fi

if [[ "$(<"${role_dir}/tasks/layout.yml")" != "$expected_layout" ]]; then
  echo "Codex CLI installations must be root-owned and its empty home private to rivet" >&2
  exit 1
fi

required_install_fragments=(
  'checksum: "sha256:{{ codex_cli_sha256 }}"'
  '    owner: root'
  '    group: root'
  '    mode: "0644"'
  '    remote_src: true'
  '      - "{{ codex_cli_archive_binary }}"'
  '    mode: "0755"'
  '    dest: /usr/local/bin/codex'
  '    state: link'
  '- name: Read installed standalone Codex CLI version as rivet'
  '      - /usr/local/bin/codex'
  '  become_user: rivet'
  '    CODEX_HOME: /home/rivet/.codex'
  '    PATH: /home/rivet/.local/bin:/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin'
  '      - (codex_cli_installed_version.stdout | trim) == ("codex-cli " ~ codex_cli_version)'
)

for fragment in "${required_install_fragments[@]}"; do
  if ! grep -Fq -- "$fragment" "${role_dir}/tasks/install.yml"; then
    echo "Missing Codex CLI installation policy fragment: ${fragment}" >&2
    exit 1
  fi
done

if [[ "$(grep -Fc -- '  ansible.builtin.get_url:' "${role_dir}/tasks/install.yml")" -ne 1 ]] ||
  [[ "$(grep -Fc -- '  ansible.builtin.unarchive:' "${role_dir}/tasks/install.yml")" -ne 1 ]] ||
  [[ "$(grep -Fc -- '  become_user: rivet' "${role_dir}/tasks/install.yml")" -ne 1 ]]; then
  echo "Codex CLI needs one verified download, one extraction, and one rivet-account version check" >&2
  exit 1
fi

if grep -ERiq -- '(auth\.json|codex login|api[_ -]?key|access[_ -]?token|authorization[_ -]?url|config\.toml)' "$role_dir"; then
  echo "The Codex CLI role must not create, inspect, or mock authentication material or login configuration" >&2
  exit 1
fi

ANSIBLE_CONFIG="$config_file" \
  ansible-playbook \
    --inventory 'localhost,' \
    --syntax-check \
    "$playbook"

echo "The standalone Codex CLI checksum, ownership, mode, and credential boundaries are valid."
