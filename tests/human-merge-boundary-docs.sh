#!/usr/bin/env bash

set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
readme="${repo_root}/Readme.md"
runbook="${repo_root}/docs/runbooks/verify-human-merge-boundary.md"
verifier="${repo_root}/tests/verify-human-merge-boundary.sh"

for required_file in "$runbook" "$verifier"; do
  if [[ ! -f "$required_file" ]]; then
    echo "Missing human merge-boundary artifact: ${required_file}" >&2
    exit 1
  fi
done

required_runbook_text=(
  'Pull requests, administration, workflows, and actions'
  'tests/human-merge-boundary-policy.sh'
  'tests/verify-human-merge-boundary.sh capture <pull-request-number>'
  'tests/verify-human-merge-boundary.sh verify <pull-request-number>'
  'GH006'
  'service_process_recreated=true'
  'Leave the PR open'
)

for expected in "${required_runbook_text[@]}"; do
  if ! grep -Fq -- "$expected" "$runbook"; then
    echo "Human merge-boundary runbook is missing: ${expected}" >&2
    exit 1
  fi
done

if ! grep -Fq -- \
  '[human merge-boundary runbook](docs/runbooks/verify-human-merge-boundary.md)' \
  "$readme"; then
  echo 'README must link to the human merge-boundary runbook.' >&2
  exit 1
fi

bash -n "$verifier"

echo 'Human merge-boundary verification is documented.'
