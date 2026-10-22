#!/usr/bin/env bash

set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
defaults_file="${repo_root}/ansible/roles/codex_cli/defaults/main.yml"
install_file="${repo_root}/ansible/roles/codex_cli/tasks/install.yml"

required_defaults=(
  'codex_cli_archive: "codex-package-x86_64-unknown-linux-musl.tar.gz"'
  'codex_cli_binary: "bin/codex"'
  'codex_cli_code_mode_host_binary: "bin/codex-code-mode-host"'
  'codex_cli_search_binary: "codex-path/rg"'
  'codex_cli_sandbox_binary: "codex-resources/bwrap"'
)

for fragment in "${required_defaults[@]}"; do
  if ! grep -Fqx -- "$fragment" "$defaults_file"; then
    echo "The complete Codex package pin is missing: ${fragment}" >&2
    exit 1
  fi
done

required_install_fragments=(
  '    creates: "/opt/rivet/codex-cli/{{ codex_cli_version }}/codex-package.json"'
  '    - "{{ codex_cli_binary }}"'
  '    - "{{ codex_cli_code_mode_host_binary }}"'
  '    - "{{ codex_cli_search_binary }}"'
  '    - "{{ codex_cli_sandbox_binary }}"'
  '- name: Verify complete standalone Codex package executables'
  '      - item.stat.mode == "0755"'
  '    src: "/opt/rivet/codex-cli/{{ codex_cli_version }}/{{ codex_cli_binary }}"'
)

for fragment in "${required_install_fragments[@]}"; do
  if ! grep -Fq -- "$fragment" "$install_file"; then
    echo "Codex code-mode-host installation policy is missing: ${fragment}" >&2
    exit 1
  fi
done

if grep -Fq -- 'codex_cli_archive_binary' "$install_file"; then
  echo "Codex must not retain the incomplete CLI-only archive layout" >&2
  exit 1
fi

echo "The complete Codex package includes and verifies the code-mode host."
