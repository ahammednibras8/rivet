#!/usr/bin/env bash

set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
defaults_file="${repo_root}/ansible/roles/codex_cli/defaults/main.yml"
expected_defaults='---
codex_cli_version: "0.163.0"
codex_cli_archive: "codex-x86_64-unknown-linux-musl.tar.gz"
codex_cli_archive_binary: "codex-x86_64-unknown-linux-musl"
codex_cli_download_url: >-
  https://github.com/openai/codex/releases/download/rust-v{{ codex_cli_version }}/{{ codex_cli_archive }}
codex_cli_sha256: "beb339e8ecd9ba057a6bb2dc81ad8ca474812edfbf0fc5056ca818797648dde4"'

if [[ ! -f "$defaults_file" ]] || [[ "$(<"$defaults_file")" != "$expected_defaults" ]]; then
  echo "Codex CLI must use the reviewed stable Linux AMD64 artifact and SHA-256" >&2
  exit 1
fi

echo "Codex CLI is pinned to reviewed stable release 0.163.0."
