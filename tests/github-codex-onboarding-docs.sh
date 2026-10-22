#!/usr/bin/env bash

set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
readme="${repo_root}/README.md"
runbook="${repo_root}/docs/runbooks/onboard-github-and-codex.md"
adr="${repo_root}/docs/adr/0007-use-standalone-codex-cli.md"
evidence="${repo_root}/docs/evidence/issue-6-cloud-workspace-onboarding.md"

if [[ ! -f "$runbook" ]]; then
  echo "Missing GitHub and Codex onboarding runbook: ${runbook}" >&2
  exit 1
fi

if [[ ! -f "$evidence" ]]; then
  echo "Missing Issue #6 onboarding evidence: ${evidence}" >&2
  exit 1
fi

if [[ ! -f "$adr" ]]; then
  echo "Missing standalone Codex architecture decision: ${adr}" >&2
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
  "Agent provider | T3 existing-CLI instance named \`Standalone Codex\`"
  "Codex CLI | \`0.163.0\`, pinned and checksum-verified by Ansible"
  'beb339e8ecd9ba057a6bb2dc81ad8ca474812edfbf0fc5056ca818797648dde4'
  'cli_auth_credentials_store = "file"'
  'codex login --device-auth'
  'codex login status >/dev/null'
  '**Configure manually**'
  "Set **Binary path** to \`/usr/local/bin/codex\`."
  "Set **CODEX_HOME path** to \`/home/rivet/.codex\`."
  "\`codex_standalone\`"
  'more than 60 minutes have elapsed'
  '## Roll back to the retained managed provider'
  '**Current checkout**, not **New worktree**'
  '**Supervised** permissions'
  'Human review remains mandatory before every generated pull request is'
  'never read, print, copy, or hash'
  "including an ignored \`.env\` file"
)

for expected in "${required_runbook_text[@]}"; do
  if ! grep -Fq -- "$expected" "$runbook"; then
    echo "GitHub and Codex onboarding runbook is missing: ${expected}" >&2
    exit 1
  fi
done

required_adr_text=(
  'Replaces: The managed-Codex-only provider decision recorded by Issue #6'
  "Version | \`0.163.0\`"
  'T3 will use a separate Codex provider instance'
  'does not authorize this repository change to run'
  "\`codex login\`"
  'remains usable beyond the one-hour access-token boundary'
)

for expected in "${required_adr_text[@]}"; do
  if ! grep -Fq -- "$expected" "$adr"; then
    echo "Standalone Codex ADR is missing: ${expected}" >&2
    exit 1
  fi
done

if grep -Fq -- "Managed Codex version | Read from T3's \`active.json\`" "$runbook" ||
  grep -Fq -- 'Do not install a duplicate global Codex CLI' "$runbook"; then
  echo "The onboarding runbook still enforces the superseded managed-only Codex policy" >&2
  exit 1
fi

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

if ! grep -Fq -- \
  '[ADR-0007](docs/adr/0007-use-standalone-codex-cli.md)' \
  "$readme"; then
  echo "README must link to the standalone Codex decision" >&2
  exit 1
fi

if grep -Fq -- \
  'Repository and agent-provider setup remain future implementation issues.' \
  "$readme"; then
  echo "README still describes completed repository and provider onboarding as future work" >&2
  exit 1
fi

echo "GitHub and standalone Codex onboarding boundaries are documented."
