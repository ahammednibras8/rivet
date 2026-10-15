#!/usr/bin/env bash

set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
capture="${repo_root}/tests/capture-backup-restore-baseline.sh"
verify="${repo_root}/tests/verify-backup-restoration.sh"
policy_library="${repo_root}/infra/bootstrap/lib/operator-role-policy.sh"

for script in "$capture" "$verify"; do
  if [[ ! -x "$script" ]]; then
    echo "Backup-restoration script must be executable: ${script}" >&2
    exit 1
  fi
  bash -n "$script"
done

required_capture_text=(
  'issue-13-before.json'
  'PRAGMA wal_checkpoint(TRUNCATE); PRAGMA integrity_check;'
  'T3 Code must be stopped but enabled'
  '/home/rivet/workspaces/rivet-issue-13-worktree'
  'verification/13-restore-fixture'
  '.t3/userdata'
  '.t3/worktrees'
  '/workspaces'
  '.config/gh'
  '! -perm 0600'
  'chmod 0600'
)

for expected in "${required_capture_text[@]}"; do
  if ! grep -Fq -- "$expected" "$capture"; then
    echo "Backup baseline capture is missing: ${expected}" >&2
    exit 1
  fi
done

required_verify_text=(
  'issue-13-after.json'
  'The source instance must remain stopped'
  'Purpose'
  'RestoreDrill'
  '192.0.2.1/32'
  'sameThread'
  'contextResponseRecorded'
  'repositoryPreserved'
  'durablePermissionsPreserved'
  'credentialsProtected'
  'credentialRotationObserved'
  'githubConfigurationPreserved'
  'providerConfigurationPreserved'
  'loopbackOnly'
  'sqliteIntegrity'
  'recoverySeconds'
)

for expected in "${required_verify_text[@]}"; do
  if ! grep -Fq -- "$expected" "$verify"; then
    echo "Backup restoration verifier is missing: ${expected}" >&2
    exit 1
  fi
done

prohibited_text=(
  'lightsail create-instances-from-snapshot'
  'lightsail delete-instance'
  'lightsail delete-instance-snapshot'
  'lightsail start-instance'
  'lightsail stop-instance'
  'git clean'
  'git reset --hard'
  'rm -rf'
)

for prohibited in "${prohibited_text[@]}"; do
  if grep -Fq -- "$prohibited" "$capture" "$verify"; then
    echo "Backup verification script contains a prohibited mutation: ${prohibited}" >&2
    exit 1
  fi
done

# shellcheck source=infra/bootstrap/lib/operator-role-policy.sh
source "$policy_library"
lightsail_policy="$(render_operator_lightsail_policy)"

if ! jq -e '
  any(.Statement[];
    .Sid == "DeleteRivetRestoreDrillResources" and
    .Action == ["lightsail:DeleteInstance", "lightsail:DeleteInstanceSnapshot"] and
    .Condition.StringEquals["aws:RequestedRegion"] == "ap-south-1" and
    .Condition.StringEquals["aws:ResourceTag/Project"] == "Rivet" and
    .Condition.StringEquals["aws:ResourceTag/Purpose"] == "RestoreDrill"
  ) and
  any(.Statement[];
    .Sid == "OperateRivetLightsailInstances" and
    .Action == ["lightsail:StartInstance", "lightsail:StopInstance"] and
    .Condition.StringEquals["aws:ResourceTag/Project"] == "Rivet"
  ) and
  ([.Statement[].Action] | flatten | index("lightsail:DeleteAutoSnapshot") | not) and
  ([.Statement[].Action] | flatten | index("lightsail:ExportSnapshot") | not)
' <<<"$lightsail_policy" >/dev/null; then
  echo "Backup restoration IAM actions exceed or miss the reviewed tag boundary." >&2
  exit 1
fi

echo "Backup restoration is captured, verified, and bounded by tagged cleanup permissions."
