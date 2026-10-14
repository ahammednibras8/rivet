#!/usr/bin/env bash

set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
verify="${repo_root}/tests/verify-isolated-worktree-state.sh"

if [[ ! -x "$verify" ]]; then
  echo "Isolated-worktree verifier must be executable: ${verify}" >&2
  exit 1
fi

bash -n "$verify"

required_text=(
  'RIVET_ISSUE9_MARKER'
  'StrictHostKeyChecking=yes'
  'issue-9-isolated-worktree.json'
  'projection_thread_messages'
  'worktreePath'
  'deterministicChangeMatches'
  'defaultBranchUntouched'
  'unrelatedWorktreeCount'
  "chmod 0600 \"\$temporary_path\""
)

for expected in "${required_text[@]}"; do
  if ! grep -Fq -- "$expected" "$verify"; then
    echo "Isolated-worktree verifier is missing: ${expected}" >&2
    exit 1
  fi
done

prohibited_text=(
  'git commit'
  'git push'
  'git clean'
  'rm -rf'
  'SELECT *'
  'printenv'
  'env |'
)

for prohibited in "${prohibited_text[@]}"; do
  if grep -Fq -- "$prohibited" "$verify"; then
    echo "Isolated-worktree verifier contains a prohibited operation: ${prohibited}" >&2
    exit 1
  fi
done

echo "Isolated-worktree verification is read-only outside its protected evidence file."
