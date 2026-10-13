#!/usr/bin/env bash

set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
defaults_file="${repo_root}/ansible/roles/t3_code/defaults/main.yml"
expected_defaults='---
t3_code_version: "0.0.45"
t3_code_release_archive: "t3-0.0.45-linux-x64.tar.gz"
t3_code_release_url: "https://github.com/pingdotgg/t3code/releases/download/v0.0.45/t3-0.0.45-linux-x64.tar.gz"
t3_code_release_sha256: "10505ae74bc6a43cfab0fde0bf06a0e0d6862f74030591be994a640d48a0d6bd"'

if [[ ! -f "$defaults_file" ]]; then
  echo "Missing T3 Code release defaults: ${defaults_file}" >&2
  exit 1
fi

if [[ "$(<"$defaults_file")" != "$expected_defaults" ]]; then
  echo "T3 Code must use the reviewed stable Linux x64 release and published checksum" >&2
  exit 1
fi

echo "T3 Code is pinned to reviewed stable release 0.0.45."
