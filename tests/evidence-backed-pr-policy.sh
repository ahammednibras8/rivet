#!/usr/bin/env bash

set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
verify="${repo_root}/tests/verify-evidence-backed-pr.sh"

if [[ ! -x "$verify" ]]; then
  echo "Evidence-backed PR verifier must be executable: ${verify}" >&2
  exit 1
fi

bash -n "$verify"

required_text=(
  'feature/11-evidence-backed-pr'
  'autoMergeRequest == null'
  'Related: #11'
  '## Declared scope'
  '## Risks'
  '## Changed files'
  '## Automated verification'
  '## Manual verification'
  '## Redacted evidence'
  'non-closing issue relationship'
  'gitleaks dir'
  'Pull-request changed files do not match the pushed branch.'
  'Pull-request commit set does not match the pushed branch.'
  'Pull request contains an unrelated or prohibited file.'
)

for expected in "${required_text[@]}"; do
  if ! grep -Fq -- "$expected" "$verify"; then
    echo "Evidence-backed PR verifier is missing: ${expected}" >&2
    exit 1
  fi
done

prohibited_text=(
  'gh pr merge'
  'gh pr close'
  'gh pr edit'
  'gh api --method'
  'git push'
  'git commit'
  'git clean'
)

for prohibited in "${prohibited_text[@]}"; do
  if grep -Fq -- "$prohibited" "$verify"; then
    echo "Evidence-backed PR verifier contains a prohibited mutation: ${prohibited}" >&2
    exit 1
  fi
done

echo "Evidence-backed PR verification is read-only and enforces the human gate."
