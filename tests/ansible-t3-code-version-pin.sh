#!/usr/bin/env bash

set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
defaults_file="${repo_root}/ansible/roles/t3_code/defaults/main.yml"
expected_defaults='---
t3_code_version: "0.1.0"
t3_code_release_archive: "t3-0.1.0-linux-x64.tar.gz"
t3_code_release_url: "https://github.com/pingdotgg/t3code/releases/download/v0.1.0/t3-0.1.0-linux-x64.tar.gz"
t3_code_release_sha256: "f7703ff1bb8f6243580058b3ccf2c02abb62eba4b991e26bbb1da22f4b56d9b1"'

if [[ ! -f "$defaults_file" ]]; then
  echo "Missing T3 Code release defaults: ${defaults_file}" >&2
  exit 1
fi

if [[ "$(<"$defaults_file")" != "$expected_defaults" ]]; then
  echo "T3 Code must use the reviewed stable Linux x64 release and published checksum" >&2
  exit 1
fi

echo "T3 Code is pinned to reviewed stable release 0.1.0."
