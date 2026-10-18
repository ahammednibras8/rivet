#!/usr/bin/env bash

set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
verification="${repo_root}/tests/verify-organization-safe-denials.sh"

if [[ ! -x "$verification" ]]; then
  echo "Organization safe-denial verification must be executable" >&2
  exit 1
fi

bash -n "$verification"

required_text=(
  'StrictHostKeyChecking=yes'
  'rivet-repository status'
  'baselinePresent'
  'guardedCheckoutValid'
  'rivet-repository verify example/repository'
  'actions/workflows?per_page=1'
  'actions/permissions/access'
  'actions/secrets?per_page=1'
  'hooks?per_page=1'
  'deployments?per_page=1'
  'callerSuppliedRepositoryRejected'
  'workflowReadDenied'
  'actionsAdministrationReadDenied'
  'secretsMetadataReadDenied'
  'webhookAdministrationReadDenied'
  'deploymentReadDenied'
  'defaultBranchUnchanged'
  'unsafeStateChangingTestsSkipped'
  'residualDefaultMergeApprovalRisk'
  "chmod 0600 \"\$temporary_result\""
)

for expected in "${required_text[@]}"; do
  if ! grep -Fq -- "$expected" "$verification"; then
    echo "Organization safe-denial verification is missing: ${expected}" >&2
    exit 1
  fi
done

prohibited_text=(
  '--method POST'
  '--method PUT'
  '--method PATCH'
  '--method DELETE'
  'gh pr merge'
  'gh pr review'
  'git push'
  'gh repo list'
  'printenv'
  'env |'
  "echo \"\$organization\""
  "echo \"\$repository_name\""
)

for prohibited in "${prohibited_text[@]}"; do
  if grep -Fq -- "$prohibited" "$verification"; then
    echo "Organization safe-denial verification contains a prohibited operation: ${prohibited}" >&2
    exit 1
  fi
done

echo "Organization permission probes remain read-only and redacted."
