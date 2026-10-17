#!/usr/bin/env bash

set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
readme="${repo_root}/Readme.md"
runbook="${repo_root}/docs/runbooks/onboard-organization-repository.md"
evidence="${repo_root}/docs/evidence/issue-35-organization-repository-onboarding.md"

for document in "$runbook" "$evidence"; do
  if [[ ! -f "$document" ]]; then
    echo "Missing organization repository onboarding document" >&2
    exit 1
  fi
done

required_runbook_text=(
  'does not accept a repository name, owner, URL, branch'
  'rivet-repository verify'
  'rivet-repository clone'
  'rivet-repository status'
  'rivet-repository register'
  'approval-required'
  'findings remain private'
  'emits only booleans and counts'
  'UMask=0027'
)

for expected in "${required_runbook_text[@]}"; do
  if ! grep -Fq -- "$expected" "$runbook"; then
    echo "Organization onboarding runbook is missing: ${expected}" >&2
    exit 1
  fi
done

required_evidence_text=(
  'intentionally redacted'
  'no repository-list endpoint'
  'did not create a duplicate'
  'initial discovery attempt'
  'supervisedReadOnlyThread'
  '"activeProjectCount": 1'
  'private findings are reproduced here.'
)

for expected in "${required_evidence_text[@]}"; do
  if ! grep -Fq -- "$expected" "$evidence"; then
    echo "Organization onboarding evidence is missing: ${expected}" >&2
    exit 1
  fi
done

if ! grep -Fq \
  '[organization repository onboarding runbook](docs/runbooks/onboard-organization-repository.md)' \
  "$readme"; then
  echo "README must link the organization repository onboarding runbook" >&2
  exit 1
fi

for document in "$runbook" "$evidence"; do
  if grep -Eiq \
    'gh repo list|SELECT \*|token[=:][[:space:]]*[^<[:space:]]+' \
    "$document"; then
    echo "Organization onboarding documentation contains prohibited detail" >&2
    exit 1
  fi
done

echo "Organization repository onboarding documentation remains redacted."
