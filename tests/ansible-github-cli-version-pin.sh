#!/usr/bin/env bash

set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
defaults_file="${repo_root}/ansible/roles/github_cli/defaults/main.yml"
expected_defaults='---
github_cli_version: "2.102.0"
github_cli_package: "gh_{{ github_cli_version }}_linux_amd64.deb"
github_cli_download_url: >-
  https://github.com/cli/cli/releases/download/v{{ github_cli_version }}/{{ github_cli_package }}
github_cli_sha256: "7e54a307f90afdc59796c325ec0c49fb09e6c18537727207a8ac7513584ea5b0"'

if [[ ! -f "$defaults_file" ]]; then
  echo "Missing GitHub CLI release defaults: ${defaults_file}" >&2
  exit 1
fi

if [[ "$(<"$defaults_file")" != "$expected_defaults" ]]; then
  echo "GitHub CLI must use the reviewed Linux AMD64 release and published checksum" >&2
  exit 1
fi

echo "GitHub CLI is pinned to reviewed release 2.102.0."
