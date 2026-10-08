#!/usr/bin/env bash

set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
requirements_file="${repo_root}/ansible/requirements.txt"
expected_version="2.21.3"
expected_requirement="ansible-core==${expected_version}"

if [[ "$(<"${requirements_file}")" != "${expected_requirement}" ]]; then
  echo "Expected ${requirements_file} to contain only ${expected_requirement}" >&2
  exit 1
fi

installed_version="$(ansible --version | sed -n '1s/^ansible \[core \([^]]*\)\]$/\1/p')"

if [[ "${installed_version}" != "${expected_version}" ]]; then
  echo "Expected Ansible Core ${expected_version}, found ${installed_version:-unknown}" >&2
  exit 1
fi

echo "Ansible Core is pinned to ${expected_version}."
