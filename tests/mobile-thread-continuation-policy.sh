#!/usr/bin/env bash

set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
capture="${repo_root}/tests/capture-mobile-thread-continuation-baseline.sh"
verify="${repo_root}/tests/verify-mobile-thread-continuation.sh"

for script in "$capture" "$verify"; do
  if [[ ! -x "$script" ]]; then
    echo "Mobile thread-continuation verification script must be executable: ${script}" >&2
    exit 1
  fi

  bash -n "$script"
done

required_text=(
  'StrictHostKeyChecking=yes'
  'RIVET_CONTINUITY_MARKER'
  'RIVET_CONTINUITY_CONTEXT'
  'base64 --decode'
  'issue-8-before.json'
  'projection_thread_messages'
  'projection_threads'
  'projection_projects'
  'provider_session_runtime'
  'length == 1'
  'worktreePath == null'
  'runtimeMode == "approval-required"'
  'providerName == "codex"'
  'history_digest'
  "chmod 0600 \"\$temporary_path\""
  'markerFingerprint'
  'contextFingerprint'
)

for expected in "${required_text[@]}"; do
  if ! grep -Fq -- "$expected" "$capture"; then
    echo "Mobile thread-continuation capture is missing: ${expected}" >&2
    exit 1
  fi
done

verification_text=(
  'issue-8-before.json'
  'issue-8-after.json'
  'stat -c'
  'rivet:rivet 600'
  'length == 1'
  "LIMIT \${baseline_message_count}"
  'historyPreserved'
  'inputsMatchBaseline'
  'latestTurnAdvanced'
  'contextDependentResponseRecorded'
  'sameRepository'
  "chmod 0600 \"\$temporary_path\""
)

for expected in "${verification_text[@]}"; do
  if ! grep -Fq -- "$expected" "$verify"; then
    echo "Mobile thread-continuation verification is missing: ${expected}" >&2
    exit 1
  fi
done

prohibited_text=(
  'ps -ef'
  'ps aux'
  'printenv'
  'env |'
  'SELECT *'
  "cat \"\$database\""
)

for script in "$capture" "$verify"; do
  for prohibited in "${prohibited_text[@]}"; do
    if grep -Fq -- "$prohibited" "$script"; then
      echo "Mobile thread-continuation script exposes prohibited data: ${prohibited}" >&2
      exit 1
    fi
  done
done

echo "Mobile thread-continuation checks protect identities and message content."
