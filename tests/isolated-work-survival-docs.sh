#!/usr/bin/env bash

set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
readme="${repo_root}/README.md"
runbook="${repo_root}/docs/runbooks/verify-isolated-work-survival.md"
evidence="${repo_root}/docs/evidence/issue-9-isolated-work-survival.md"

for required_file in "$runbook" "$evidence"; do
  if [[ ! -f "$required_file" ]]; then
    echo "Missing isolated-work survival document: ${required_file}" >&2
    exit 1
  fi
done

required_runbook_text=(
  'tests/verify-isolated-worktree-state.sh'
  'tests/verify-cloud-foundation.sh'
  "issue-specific non-\`main\` branch"
  'force-close the Android client'
  'thread, working diff, command completion state, stdout, and'
  'sleep 15; tests/fixtures/issue-9/command-state.sh failure'
  'Record a different observed failure honestly'
  'issue-9-isolated-worktree.json'
)

for expected in "${required_runbook_text[@]}"; do
  if ! grep -Fq -- "$expected" "$runbook"; then
    echo "Isolated-work survival runbook is missing: ${expected}" >&2
    exit 1
  fi
done

required_evidence_text=(
  '"isolationMode": "branch"'
  '"deterministicChangeMatches": true'
  '"defaultBranchUntouched": true'
  '"unrelatedWorktreeCount": 0'
  "exit status \`127\`"
  "planned failure status was \`23\`"
  'preserves that discrepancy rather than'
)

for expected in "${required_evidence_text[@]}"; do
  if ! grep -Fq -- "$expected" "$evidence"; then
    echo "Issue #9 evidence is missing: ${expected}" >&2
    exit 1
  fi
done

if ! grep -Fq -- \
  '[isolated-work survival runbook](docs/runbooks/verify-isolated-work-survival.md)' \
  "$readme"; then
  echo "README must link to the isolated-work survival runbook" >&2
  exit 1
fi

echo "Isolated-work survival and its unexpected failure are documented honestly."
