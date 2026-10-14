#!/usr/bin/env bash

set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
readme="${repo_root}/Readme.md"
runbook="${repo_root}/docs/runbooks/deliver-evidence-backed-pr.md"
evidence="${repo_root}/docs/evidence/issue-11-evidence-backed-pr.md"

for required_file in "$runbook" "$evidence"; do
  if [[ ! -f "$required_file" ]]; then
    echo "Missing evidence-backed PR document: ${required_file}" >&2
    exit 1
  fi
done

required_runbook_text=(
  'Contents: Read and write'
  'Pull requests and every other'
  'Related: #11'
  'tests/verify-evidence-backed-pr.sh <pull-request-number>'
  'tests/repository-secrets.sh'
  'Leave the pull request open'
  'Auto-merge is configured'
)

for expected in "${required_runbook_text[@]}"; do
  if ! grep -Fq -- "$expected" "$runbook"; then
    echo "Evidence-backed PR runbook is missing: ${expected}" >&2
    exit 1
  fi
done

required_evidence_text=(
  'Pull request: [#24]'
  'failed as designed'
  'HTTP 403'
  "\`rivet-cloud-aws\`"
  '"enforceAdmins": true'
  '"forcePushesAllowed": false'
  '"state": "OPEN"'
  '"autoMergeConfigured": false'
  '"changedFileCount": 7'
  '"commitCount": 3'
  'PR #24 intentionally remains open'
)

for expected in "${required_evidence_text[@]}"; do
  if ! grep -Fq -- "$expected" "$evidence"; then
    echo "Issue #11 evidence is missing: ${expected}" >&2
    exit 1
  fi
done

if ! grep -Fq -- \
  '[evidence-backed pull-request runbook](docs/runbooks/deliver-evidence-backed-pr.md)' \
  "$readme"; then
  echo "README must link to the evidence-backed pull-request runbook" >&2
  exit 1
fi

echo "Evidence-backed PR failure, correction, and human gate are documented honestly."
