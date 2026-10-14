#!/usr/bin/env bash

set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
capture="${repo_root}/tests/capture-reboot-recovery-baseline.sh"
verify="${repo_root}/tests/verify-reboot-recovery.sh"

for script in "$capture" "$verify"; do
  if [[ ! -x "$script" ]]; then
    echo "Reboot-recovery script must be executable: ${script}" >&2
    exit 1
  fi
  bash -n "$script"
done

required_capture_text=(
  'RIVET_REBOOT_MARKER'
  'RIVET_REBOOT_CONTEXT'
  'StrictHostKeyChecking=yes'
  'issue-10-before.json'
  'bootFingerprint'
  'systemctl --user show t3code.service'
  'relayClientStatus: .relayClient.status'
  'branchesDigest'
  'worktrees'
  'codexActiveDigest'
  'secretStoreDigest'
  'settingsDigest'
  "chmod 0600 \"\$temporary_path\""
)

for expected in "${required_capture_text[@]}"; do
  if ! grep -Fq -- "$expected" "$capture"; then
    echo "Reboot baseline capture is missing: ${expected}" >&2
    exit 1
  fi
done

required_verify_text=(
  'issue-10-after.json'
  'issue-10-reboot-requested-epoch'
  'rebootOccurred'
  'serviceRecovered'
  'restartLoopFree'
  'sameEnvironment'
  'threadBranchReconciled'
  'historyPreserved'
  'repositoryPreserved'
  'settingsPreserved'
  'providerConfigurationPreserved'
  'credentialsAvailable'
  'credentialRotationObserved'
  'inFlightProcessInterrupted'
  'mobileThreadSeconds'
)

for expected in "${required_verify_text[@]}"; do
  if ! grep -Fq -- "$expected" "$verify"; then
    echo "Reboot recovery verifier is missing: ${expected}" >&2
    exit 1
  fi
done

prohibited_text=(
  'systemctl reboot'
  'git commit'
  'git push'
  'git clean'
  'rm -rf'
  'printenv'
  'env |'
)

for prohibited in "${prohibited_text[@]}"; do
  if grep -Fq -- "$prohibited" "$capture" "$verify"; then
    echo "Reboot verification script contains a prohibited operation: ${prohibited}" >&2
    exit 1
  fi
done

echo "Reboot recovery verification is protected, redacted, and non-destructive."
