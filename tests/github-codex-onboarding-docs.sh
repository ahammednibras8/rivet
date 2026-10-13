#!/usr/bin/env bash

set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
readme="${repo_root}/README.md"
runbook="${repo_root}/docs/runbooks/onboard-github-and-codex.md"
evidence="${repo_root}/docs/evidence/issue-6-cloud-workspace-onboarding.md"

if [[ ! -f "$runbook" ]]; then
  echo "Missing GitHub and Codex onboarding runbook: ${runbook}" >&2
  exit 1
fi

if [[ ! -f "$evidence" ]]; then
  echo "Missing Issue #6 onboarding evidence: ${evidence}" >&2
  exit 1
fi

required_runbook_text=(
  "Approved repository | \`ahammednibras8/rivet\` only"
  'GitHub permission | Repository contents, read-only'
  "GitHub CLI \`2.102.0\`"
  "**Only select repositories** with only \`rivet\` selected"
  '**Contents: Read-only**'
  '/home/rivet/workspaces/rivet'
  "HTTP \`403\` with \`Resource not accessible by personal access token\`"
  "T3-managed Codex connected to \`ChatGPT Personal\`"
  "Managed Codex version | \`0.156.1\`"
  '**Current checkout**, not **New worktree**'
  '**Supervised** permissions'
  'Human review remains mandatory before every generated pull request is'
  'Never list, read, hash, copy, or publish secret contents.'
  "including an ignored \`.env\` file"
)

for expected in "${required_runbook_text[@]}"; do
  if ! grep -Fq -- "$expected" "$runbook"; then
    echo "GitHub and Codex onboarding runbook is missing: ${expected}" >&2
    exit 1
  fi
done

required_evidence_text=(
  'ok=50 changed=0 unreachable=0 failed=0 skipped=2'
  "HTTP \`403\` with \`Resource not accessible by personal access token\`"
  'permissionMode=approval-required'
  'lastTurnState=completed'
  'No token was committed or retained in the local repository.'
)

for expected in "${required_evidence_text[@]}"; do
  if ! grep -Fq -- "$expected" "$evidence"; then
    echo "Issue #6 onboarding evidence is missing: ${expected}" >&2
    exit 1
  fi
done

if ! grep -Fq -- \
  '[GitHub and Codex onboarding runbook](docs/runbooks/onboard-github-and-codex.md)' \
  "$readme"; then
  echo "README must link to the GitHub and Codex onboarding runbook" >&2
  exit 1
fi

if grep -Fq -- \
  'Repository and agent-provider setup remain future implementation issues.' \
  "$readme"; then
  echo "README still describes completed repository and provider onboarding as future work" >&2
  exit 1
fi

echo "GitHub and managed Codex onboarding boundaries are documented."
