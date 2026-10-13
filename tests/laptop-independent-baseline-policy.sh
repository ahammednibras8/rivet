#!/usr/bin/env bash

set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
capture="${repo_root}/tests/capture-laptop-independent-baseline.sh"
verify="${repo_root}/tests/verify-laptop-independent-operation.sh"

if [[ ! -x "$capture" ]]; then
  echo "Laptop-independent baseline capture must be executable: ${capture}" >&2
  exit 1
fi

if [[ ! -x "$verify" ]]; then
  echo "Laptop-independent continuity verifier must be executable: ${verify}" >&2
  exit 1
fi

bash -n "$capture"
bash -n "$verify"

required_text=(
  'StrictHostKeyChecking=yes'
  '.local/state/rivet-verification'
  'issue-7-before.json'
  '.t3/userdata'
  'environment-id'
  'state.sqlite'
  'projection_threads'
  'provider_session_runtime'
  'systemctl --user show t3code.service'
  't3" connect status --json'
  'relayClientStatus: .relayClient.status'
  'ps -eo pid=,ppid=,user=,comm='
  "chmod 0600 \"\$temporary_path\""
  'machineFingerprint'
  'bootFingerprint'
  'thread_fingerprint'
)

for expected in "${required_text[@]}"; do
  if ! grep -Fq -- "$expected" "$capture"; then
    echo "Laptop-independent baseline capture is missing: ${expected}" >&2
    exit 1
  fi
done

required_verifier_text=(
  'issue-7-before.json'
  'issue-7-after.json'
  'baseline_mode'
  'baseline_owner'
  'sameHost'
  'sameBoot'
  'sameServiceProcess'
  'sameEnvironment'
  'sameThread'
  'authenticatedTurnRecorded'
  'supervisedMode'
  'repositoryClean'
  'processCommands'
)

for expected in "${required_verifier_text[@]}"; do
  if ! grep -Fq -- "$expected" "$verify"; then
    echo "Laptop-independent continuity verifier is missing: ${expected}" >&2
    exit 1
  fi
done

prohibited_text=(
  'ps -ef'
  'ps aux'
  'printenv'
  'env |'
  '.clientSecret'
  '.relayUrl'
  '.cloudUserId'
)

for prohibited in "${prohibited_text[@]}"; do
  if grep -Fq -- "$prohibited" "$capture" "$verify"; then
    echo "Laptop-independent baseline capture exposes prohibited data: ${prohibited}" >&2
    exit 1
  fi
done

echo "Laptop-independent baseline capture records protected, redacted identity evidence."
