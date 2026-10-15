#!/usr/bin/env bash

set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
script="${repo_root}/infra/tofu/destroy-workspace.sh"

bash -n "$script"

# Dollar signs in this list are literal product-code assertions.
# shellcheck disable=SC2016
required_text=(
  'snapshot_record="${evidence_directory}/snapshot.json"'
  '-retained-'
  'aws lightsail get-instance-state'
  'aws lightsail get-instance-snapshots'
  'aws lightsail stop-instance'
  'aws lightsail create-instance-snapshot'
  'aws lightsail start-instance'
  'aws lightsail get-instance-snapshot'
  '$tags.ManagedBy == "Rivet"'
  '$tags.Project == "Rivet"'
  '$tags.Purpose == "RetainedBackup"'
  '$tags.Workspace == "primary"'
  '"$snapshot_state" == "available"'
  'fromInstanceName == "rivet-workspace"'
  'monthlyUpperBoundUsd: 4'
  'chmod 0600 "$snapshot_record"'
  'Retained manual snapshot created and verified:'
)

for expected in "${required_text[@]}"; do
  if ! grep -Fq -- "$expected" "$script"; then
    echo "Workspace preparation is missing retained-snapshot control: ${expected}" >&2
    exit 1
  fi
done

prohibited_text=(
  'delete-instance-snapshot'
  'delete-auto-snapshot'
  '--force'
  'Purpose,RestoreDrill'
)

for prohibited in "${prohibited_text[@]}"; do
  if grep -Fq -- "$prohibited" "$script"; then
    echo "Retained-snapshot preparation contains prohibited behavior: ${prohibited}" >&2
    exit 1
  fi
done

echo "The retained snapshot is tagged, cost-bounded, verified, and never deleted."
