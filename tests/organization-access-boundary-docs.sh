#!/usr/bin/env bash

set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
readme="${repo_root}/README.md"
runbook="${repo_root}/docs/runbooks/verify-organization-access-boundary.md"

if [[ ! -f "$runbook" ]]; then
  echo "Missing organization access-boundary runbook" >&2
  exit 1
fi

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

if ! grep -Fq \
  '[organization access-boundary runbook](docs/runbooks/verify-organization-access-boundary.md)' \
  "$readme"; then
  echo "README must link the organization access-boundary runbook" >&2
  exit 1
fi

if grep -Eiq \
  'gh repo list|/home/rivet/workspaces/organizations/[^<[:space:]]+|github\.com/[^/[:space:]]+/[^/[:space:]]+/(pull/new|git)|token[=:][[:space:]]*[^<[:space:]]+' \
  "$runbook"; then
  echo "Organization access runbook contains prohibited private detail" >&2
  exit 1
fi

echo "Organization access-boundary runbook remains honest and redacted."
