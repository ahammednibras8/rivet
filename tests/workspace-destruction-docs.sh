#!/usr/bin/env bash

set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
readme="${repo_root}/Readme.md"
runbook="${repo_root}/docs/runbooks/destroy-workspace-safely.md"
evidence="${repo_root}/docs/evidence/issue-14-safe-workspace-destruction.md"

for required_file in "$runbook" "$evidence"; do
  if [[ ! -f "$required_file" ]]; then
    echo "Missing safe-destruction document: ${required_file}" >&2
    exit 1
  fi
done

required_runbook_text=(
  'exactly six delete-only actions'
  'canary/issue-14.json'
  'Purpose=RetainedBackup'
  'AUTHORIZE rivet-workspace DESTROY POLICY'
  'REVOKE rivet-workspace DESTROY POLICY'
  'tests/verify-workspace-destruction.sh'
  'never invokes'
  'USD 4 monthly ceiling'
  'backup-restoration runbook'
)

for expected in "${required_runbook_text[@]}"; do
  if ! grep -Fq -- "$expected" "$runbook"; then
    echo "Safe-destruction runbook is missing: ${expected}" >&2
    exit 1
  fi
done

# Backticks and dollar signs below are literal documentation assertions.
# shellcheck disable=SC2016
required_evidence_text=(
  'exactly six actions'
  'incorrect typed confirmation was rejected'
  '"selectedResourcesAbsent": true'
  '"empty": true'
  '"serial": 14'
  '"metadataUnchanged": true'
  '"contentUnchanged": true'
  '"tagsUnchanged": true'
  'temporary `rivet-workspace-destroy` inline policy was revoked'
  'USD 4 monthly ceiling'
)

for expected in "${required_evidence_text[@]}"; do
  if ! grep -Fq -- "$expected" "$evidence"; then
    echo "Safe-destruction evidence is missing: ${expected}" >&2
    exit 1
  fi
done

if ! grep -Fq -- \
  '[safe workspace-destruction runbook](docs/runbooks/destroy-workspace-safely.md)' \
  "$readme"; then
  echo 'README must link to the safe workspace-destruction runbook.' >&2
  exit 1
fi

echo 'Safe destruction, retained resources, cost, recovery, and cleanup are documented.'
