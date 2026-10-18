#!/usr/bin/env bash

set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
capture="${repo_root}/tests/capture-organization-access-baseline.sh"

if [[ ! -x "$capture" ]]; then
  echo "Organization access baseline capture must be executable" >&2
  exit 1
fi

bash -n "$capture"

required_text=(
  'StrictHostKeyChecking=yes'
  'rivet-repository status'
  "git -C \"\$checkout\" fetch --prune origin"
  '.permissions.pull == true'
  '.permissions.push == true'
  '.permissions.admin == false'
  'issue-36-before.json'
  'repositoryFingerprint'
  'defaultBranchFingerprint'
  'checkoutFingerprint'
  'defaultHeadMatchesGitHub'
  "chmod 0600 \"\$temporary_baseline\""
)

for expected in "${required_text[@]}"; do
  if ! grep -Fq -- "$expected" "$capture"; then
    echo "Organization access baseline capture is missing: ${expected}" >&2
    exit 1
  fi
done

prohibited_text=(
  'gh repo list'
  'printenv'
  'env |'
  "jq . <<<\"\$metadata\""
  "echo \"\$organization\""
  "echo \"\$repository_name\""
  "echo \"\$origin_url\""
)

for prohibited in "${prohibited_text[@]}"; do
  if grep -Fq -- "$prohibited" "$capture"; then
    echo "Organization access baseline exposes prohibited data: ${prohibited}" >&2
    exit 1
  fi
done

echo "Organization access baseline remains private and redacted."
