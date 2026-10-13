#!/usr/bin/env bash

set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
readme="${repo_root}/README.md"
runbook="${repo_root}/docs/runbooks/verify-laptop-independent-operation.md"
evidence="${repo_root}/docs/evidence/issue-7-laptop-independent-operation.md"

for required_file in "$runbook" "$evidence"; do
  if [[ ! -f "$required_file" ]]; then
    echo "Missing laptop-independent operation document: ${required_file}" >&2
    exit 1
  fi
done

required_runbook_text=(
  'tests/capture-laptop-independent-baseline.sh'
  'tests/verify-laptop-independent-operation.sh'
  'Fully shut down the laptop.'
  'disable Wi-Fi'
  '**Supervised** mode'
  'same continuously running T3 service process'
  'same project and thread with a different latest-turn fingerprint'
  'approved cloud-host T3 Connect relay client'
  'missing evidence rather than claiming it was zero'
  'issue-7-before.json'
  'issue-7-after.json'
)

for expected in "${required_runbook_text[@]}"; do
  if ! grep -Fq -- "$expected" "$runbook"; then
    echo "Laptop-independent operation runbook is missing: ${expected}" >&2
    exit 1
  fi
done

required_evidence_text=(
  'The laptop was fully powered off for the complete action interval.'
  'Android Wi-Fi was disabled and the official T3 client used mobile data.'
  'The mobile response did not report the requested established-SSH-session'
  '421.62 seconds'
  'ok=36 changed=0 unreachable=0 failed=0 skipped=17'
  '"sameServiceProcess": true'
  '"authenticatedTurnRecorded": true'
  '"cloudflared", "codex", "node-MainThread"'
  'No laptop process, laptop tunnel,'
)

for expected in "${required_evidence_text[@]}"; do
  if ! grep -Fq -- "$expected" "$evidence"; then
    echo "Issue #7 evidence is missing: ${expected}" >&2
    exit 1
  fi
done

if ! grep -Fq -- \
  '[laptop-independent operation runbook](docs/runbooks/verify-laptop-independent-operation.md)' \
  "$readme"; then
  echo "README must link to the laptop-independent operation runbook" >&2
  exit 1
fi

echo "Laptop-independent operation and its evidence are documented honestly."
