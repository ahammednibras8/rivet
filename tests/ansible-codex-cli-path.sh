#!/usr/bin/env bash

set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
install_file="${repo_root}/ansible/roles/codex_cli/tasks/install.yml"
service_file="${repo_root}/ansible/roles/t3_code/tasks/service.yml"
expected_path='Environment=PATH=/home/rivet/.local/bin:/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin'

if ! grep -Fq -- '    dest: /usr/local/bin/codex' "$install_file" ||
  ! grep -Fq -- '      - /usr/local/bin/codex' "$install_file"; then
  echo "Codex CLI must be linked into the system path and executed there as rivet" >&2
  exit 1
fi

if ! grep -Fqx -- "      ${expected_path}" "$service_file"; then
  echo "The non-interactive T3 service PATH must include /usr/local/bin" >&2
  exit 1
fi

echo "The standalone Codex CLI is available to rivet and T3's non-interactive PATH."
