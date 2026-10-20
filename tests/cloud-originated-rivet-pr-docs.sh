#!/usr/bin/env bash

set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
evidence="${repo_root}/docs/evidence/issue-49-cloud-originated-rivet-pr.md"

if [[ ! -f "$evidence" ]]; then
  echo "Missing Issue #49 cloud-originated contribution evidence" >&2
  exit 1
fi

required_evidence_text=(
  'Branch `feature/49-cloud-originated-rivet-pr` was published successfully.'
  'Initial commit `b8b58c4` changed only'
  '`docs/evidence/issue-49-cloud-originated-rivet-pr.md`.'
  'Project and organization credentials both passed independent access checks.'
  'Organization repository identity and checkout path remain redacted.'
  '`rivet:0700`'
  '`rivet:0600`'
  '`git`, `gh`, Ansible, and Docker were available.'
  'OpenTofu, ShellCheck, and Gitleaks were missing.'
  'cloud-foundation suite is not claimed as passing.'
  'Human review remains required'
)

for expected in "${required_evidence_text[@]}"; do
  if ! grep -Fq -- "$expected" "$evidence"; then
    echo "Issue #49 evidence is missing: ${expected}" >&2
    exit 1
  fi
done

if grep -Eiq -- \
  '(github_pat_|gh[pousr]_[[:alnum:]_]+|(GH_TOKEN|token)[[:space:]]*[:=][[:space:]]*[^[:space:]]+)' \
  "$evidence"; then
  echo "Issue #49 evidence contains a token value" >&2
  exit 1
fi

if grep -Eiq -- \
  'organization.*`[^`[:space:]]+/[^`[:space:]]+`|organization.*(/home/|github\.com)' \
  "$evidence"; then
  echo "Issue #49 evidence contains an organization identity or path" >&2
  exit 1
fi

if grep -Eo '[[:alnum:]_.-]+/[[:alnum:]_.-]+' "$evidence" |
  grep -Fvx \
    -e 'ahammednibras8/rivet' \
    -e 'docs/evidence' \
    -e 'feature/49-cloud-originated-rivet-pr' \
    -e 'home/rivet' \
    -e 'origin/main' \
    -e 'workspaces/rivet' |
  grep -q .; then
  echo "Issue #49 evidence contains an unapproved repository identity" >&2
  exit 1
fi

if grep -Eiq -- '(https?|ssh|git)://|git@[^[:space:]]+|github\.com[:/]' "$evidence"; then
  echo "Issue #49 evidence contains a remote URL" >&2
  exit 1
fi

echo "Issue #49 cloud contribution evidence is complete and redacted."
