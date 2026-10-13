#!/usr/bin/env bash

set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
config_file="${repo_root}/ansible/ansible.cfg"
fixtures_dir="${repo_root}/tests/fixtures/ansible"

ANSIBLE_CONFIG="${config_file}" \
  ansible-playbook \
    --inventory 'localhost,' \
    --syntax-check \
    "${fixtures_dir}/system-baseline-supported.yml"

ANSIBLE_CONFIG="${config_file}" \
  ansible-playbook \
    --inventory 'localhost,' \
    "${fixtures_dir}/system-baseline-supported.yml"

if unsupported_output="$(
  ANSIBLE_CONFIG="${config_file}" \
    ansible-playbook \
      --inventory 'localhost,' \
      "${fixtures_dir}/system-baseline-unsupported.yml" 2>&1
)"; then
  echo "The system baseline accepted an unsupported platform" >&2
  exit 1
fi

if ! grep -Fq 'Rivet requires Ubuntu 24.04 LTS on x86-64; found Debian 12 on x86_64.' \
  <<<"${unsupported_output}"; then
  echo "The system baseline did not report the unsupported platform clearly" >&2
  exit 1
fi

echo "The system baseline accepts only Ubuntu 24.04 LTS on x86-64."
