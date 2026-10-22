#!/usr/bin/env bash

set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
defaults_file="${repo_root}/ansible/roles/codex_cli/defaults/main.yml"
expected_defaults='---
codex_cli_version: "0.163.0"
codex_cli_archive: "codex-package-x86_64-unknown-linux-musl.tar.gz"
codex_cli_binary: "bin/codex"
codex_cli_code_mode_host_binary: "bin/codex-code-mode-host"
codex_cli_search_binary: "codex-path/rg"
codex_cli_sandbox_binary: "codex-resources/bwrap"
codex_cli_download_url: >-
  https://github.com/openai/codex/releases/download/rust-v{{ codex_cli_version }}/{{ codex_cli_archive }}
codex_cli_sha256: "582646c6bf0561eb0de540f7fc85b9121b0091a826bc6e96830b7f1722122182"'

if [[ ! -f "$defaults_file" ]] || [[ "$(<"$defaults_file")" != "$expected_defaults" ]]; then
  echo "Codex CLI must use the reviewed complete Linux AMD64 package and SHA-256" >&2
  exit 1
fi

echo "Codex CLI is pinned to reviewed stable release 0.163.0."
