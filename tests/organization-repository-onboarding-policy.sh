#!/usr/bin/env bash

set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
verifier="${repo_root}/tests/verify-organization-repository-onboarding.sh"

if [[ ! -x "$verifier" ]]; then
  echo "Organization repository onboarding verifier must be executable" >&2
  exit 1
fi

bash -n "$verifier"

required_text=(
  'StrictHostKeyChecking=yes'
  'RIVET_ORGANIZATION_DISCOVERY_MARKER'
  "\${HOME}/.config/rivet/repositories.json"
  'rivet-repository status'
  'rivet-repository register'
  'projection_projects'
  'projection_threads'
  'projection_thread_messages'
  'provider_session_runtime'
  'projects.deleted_at IS NULL'
  '.runtimeMode == "approval-required"'
  '.providerName == "codex"'
  '.worktreePath == null'
  'activeProjectCount'
  'repositoryClean'
  'securePermissions'
  'serviceUmask'
)

for expected in "${required_text[@]}"; do
  if ! grep -Fq -- "$expected" "$verifier"; then
    echo "Organization repository onboarding verification is missing: ${expected}" >&2
    exit 1
  fi
done

prohibited_text=(
  'SELECT *'
  'gh repo list'
  'printenv'
  'env |'
  'messages.text AS'
  'remote get-url origin >&'
)

for prohibited in "${prohibited_text[@]}"; do
  if grep -Fq -- "$prohibited" "$verifier"; then
    echo "Organization repository onboarding verifier exposes prohibited data: ${prohibited}" >&2
    exit 1
  fi
done

echo "Organization repository onboarding verification remains redacted."
