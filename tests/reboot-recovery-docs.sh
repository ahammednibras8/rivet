#!/usr/bin/env bash

set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
readme="${repo_root}/Readme.md"
runbook="${repo_root}/docs/runbooks/verify-reboot-recovery.md"
evidence="${repo_root}/docs/evidence/issue-10-reboot-recovery.md"

for required_file in "$runbook" "$evidence"; do
  if [[ ! -f "$required_file" ]]; then
    echo "Missing reboot recovery document: ${required_file}" >&2
    exit 1
  fi
done

required_runbook_text=(
  'tests/capture-reboot-recovery-baseline.sh'
  'tests/verify-reboot-recovery.sh'
  'issue-10-before.json'
  'issue-10-after.json'
  'without SSH repair'
  're-pairing'
  'different boot identity'
  'credential rotation'
  'interrupted process'
)

for expected in "${required_runbook_text[@]}"; do
  if ! grep -Fq -- "$expected" "$runbook"; then
    echo "Reboot recovery runbook is missing: ${expected}" >&2
    exit 1
  fi
done

required_evidence_text=(
  '"rebootOccurred": true'
  '"sameThread": true'
  '"repositoryPreserved": true'
  '"credentialsAvailable": true'
  '"credentialRotationObserved": true'
  '"inFlightProcessInterrupted": true'
  '"hostSeconds": 11'
  '"serviceSeconds": 19'
  '"mobileThreadSeconds": 529'
  'stale cached thread branch label'
)

for expected in "${required_evidence_text[@]}"; do
  if ! grep -Fq -- "$expected" "$evidence"; then
    echo "Issue #10 evidence is missing: ${expected}" >&2
    exit 1
  fi
done

if ! grep -Fq -- \
  '[reboot-recovery runbook](docs/runbooks/verify-reboot-recovery.md)' \
  "$readme"; then
  echo "README must link to the reboot-recovery runbook" >&2
  exit 1
fi

echo "Reboot recovery behavior and limitations are documented honestly."
