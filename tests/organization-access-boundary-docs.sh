#!/usr/bin/env bash

set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
readme="${repo_root}/Readme.md"
runbook="${repo_root}/docs/runbooks/verify-organization-access-boundary.md"
evidence="${repo_root}/docs/evidence/issue-36-organization-access-boundary.md"

for document in "$runbook" "$evidence"; do
  if [[ ! -f "$document" ]]; then
    echo "Missing organization access-boundary document" >&2
    exit 1
  fi
done

required_runbook_text=(
  'has neither a ruleset nor legacy default-branch'
  'cannot prove that a default-branch push, merge, or review'
  'tests/capture-organization-access-baseline.sh'
  'tests/verify-organization-branch-lifecycle.sh'
  'tests/verify-organization-safe-denials.sh'
  'push stdout and stderr are suppressed'
  'fingerprints the current branch, HEAD, and complete porcelain status'
  "only authenticated \`GET\` requests"
  'Never claim that editing the visible text'
)

for expected in "${required_runbook_text[@]}"; do
  if ! grep -Fq -- "$expected" "$runbook"; then
    echo "Organization access runbook is missing: ${expected}" >&2
    exit 1
  fi
done

required_evidence_text=(
  'intentionally redacted'
  'residual risk'
  'accountRoleSufficient'
  'disposableBranchDeleted'
  'checkoutStateUnchanged'
  'unsafeStateChangingTestsSkipped'
  'residualDefaultMergeApprovalRisk'
  'treated as disclosed rather than claimed erased'
  'rather than a technically enforced default-branch'
)

for expected in "${required_evidence_text[@]}"; do
  if ! grep -Fq -- "$expected" "$evidence"; then
    echo "Organization access evidence is missing: ${expected}" >&2
    exit 1
  fi
done

if ! grep -Fq \
  '[organization access-boundary runbook](docs/runbooks/verify-organization-access-boundary.md)' \
  "$readme"; then
  echo "README must link the organization access-boundary runbook" >&2
  exit 1
fi

for document in "$runbook" "$evidence"; do
  if grep -Eiq \
    'gh repo list|/home/rivet/workspaces/organizations/[^<[:space:]]+|github\.com/[^/[:space:]]+/[^/[:space:]]+/(pull/new|git)|token[=:][[:space:]]*[^<[:space:]]+' \
    "$document"; then
    echo "Organization access documentation contains prohibited private detail" >&2
    exit 1
  fi
done

echo "Organization access-boundary documentation remains honest and redacted."
