#!/usr/bin/env bash

set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
verification="${repo_root}/tests/verify-organization-branch-lifecycle.sh"

if [[ ! -x "$verification" ]]; then
  echo "Organization branch lifecycle verification must be executable" >&2
  exit 1
fi

bash -n "$verification"

required_text=(
  'StrictHostKeyChecking=yes'
  'rivet-repository status'
  'issue-36-before.json'
  'rivet-verification/issue-36-'
  "git -C \"\$checkout\" commit-tree"
  "\"\${commit_sha}:refs/heads/\${branch}\""
  "\":refs/heads/\${branch}\""
  'defaultBranchUnchanged'
  'disposableBranchCreated'
  'disposableBranchDeleted'
  'checkoutClean'
  "chmod 0600 \"\$temporary_result\""
  'trap cleanup EXIT'
)

for expected in "${required_text[@]}"; do
  if ! grep -Fq -- "$expected" "$verification"; then
    echo "Organization branch lifecycle verification is missing: ${expected}" >&2
    exit 1
  fi
done

prohibited_text=(
  'git checkout'
  'git switch'
  'gh repo list'
  'printenv'
  'env |'
  "echo \"\$organization\""
  "echo \"\$repository_name\""
  "echo \"\$branch\""
  "echo \"\$commit_sha\""
)

for prohibited in "${prohibited_text[@]}"; do
  if grep -Fq -- "$prohibited" "$verification"; then
    echo "Organization branch lifecycle exposes or mutates prohibited state: ${prohibited}" >&2
    exit 1
  fi
done

echo "Organization branch lifecycle remains isolated and redacted."
