#!/usr/bin/env bash

set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
readme="${repo_root}/Readme.md"
runbook="${repo_root}/docs/runbooks/restore-workspace-backup.md"
evidence="${repo_root}/docs/evidence/issue-13-backup-restoration.md"

for required_file in "$runbook" "$evidence"; do
  if [[ ! -f "$required_file" ]]; then
    echo "Missing backup-restoration document: ${required_file}" >&2
    exit 1
  fi
done

required_runbook_text=(
  'latest seven'
  '20:00'
  '/home/rivet/.t3/userdata'
  '/home/rivet/.t3/worktrees'
  '/home/rivet/workspaces'
  '/home/rivet/.config/gh'
  'tests/capture-backup-restore-baseline.sh'
  'tests/verify-backup-restoration.sh'
  '192.0.2.1/32'
  'source and replacement disks'
  'not copied back'
  'Purpose=RestoreDrill'
  'Delete only the tagged manual drill snapshot.'
)

for expected in "${required_runbook_text[@]}"; do
  if ! grep -Fq -- "$expected" "$runbook"; then
    echo "Backup-restoration runbook is missing: ${expected}" >&2
    exit 1
  fi
done

required_evidence_text=(
  'NotFoundException'
  'zero restore-drill instances'
  'changed=0 unreachable=0 failed=0'
  '"sameThread": true'
  '"repositoryPreserved": true'
  '"worktreeCount": 2'
  '"credentialsProtected": true'
  '"sqliteIntegrity": "ok"'
  '"recoverySeconds": 675'
  'below USD 0.10'
  'one successful automatic snapshot'
  'no remaining restore-drill instance or manual drill snapshot'
)

for expected in "${required_evidence_text[@]}"; do
  if ! grep -Fq -- "$expected" "$evidence"; then
    echo "Backup-restoration evidence is missing: ${expected}" >&2
    exit 1
  fi
done

if ! grep -Fq -- \
  '[backup-restoration runbook](docs/runbooks/restore-workspace-backup.md)' \
  "$readme"; then
  echo "README must link to the backup-restoration runbook." >&2
  exit 1
fi

echo "Backup retention, restoration, cost, limitations, and cleanup are documented."
