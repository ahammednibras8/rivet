#!/usr/bin/env bash

set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
requirements_file="${repo_root}/ansible/requirements.yml"
expected_version="13.4.0"
expected_requirements=$'---\ncollections:\n  - name: community.general\n    version: "13.4.0"'

if [[ "$(<"${requirements_file}")" != "${expected_requirements}" ]]; then
  echo "Unexpected Ansible collection requirements in ${requirements_file}" >&2
  exit 1
fi

active_version="$(
  ansible-galaxy collection list community.general --format json |
    python3 -c 'import json, sys; data = json.load(sys.stdin); print(next(iter(data.values()))["community.general"]["version"])'
)"

if [[ "${active_version}" != "${expected_version}" ]]; then
  echo "Expected active community.general ${expected_version}, found ${active_version}" >&2
  exit 1
fi

ansible-doc --type module community.general.ufw >/dev/null

echo "community.general ${expected_version} provides the UFW module."
