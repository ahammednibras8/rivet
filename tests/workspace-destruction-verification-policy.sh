#!/usr/bin/env bash

set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
verify="${repo_root}/tests/verify-workspace-destruction.sh"

bash -n "$verify"

# Dollar signs below are literal product-code assertions.
# shellcheck disable=SC2016
required_text=(
  'state list'
  '(.resources // []) | length == 0'
  'get-instances'
  'get-key-pairs'
  'get-static-ips'
  'describe-budget'
  'NotFoundException'
  'get-instance-snapshot'
  'Purpose == "RetainedBackup"'
  's3api head-object'
  's3api get-object'
  's3api get-object-tagging'
  'get-bucket-versioning'
  'get-bucket-encryption'
  'continuingMonthlyCostUpperBoundUsd: 4'
  'chmod 0600 "$verification_record"'
)

for expected in "${required_text[@]}"; do
  if ! grep -Fq -- "$expected" "$verify"; then
    echo "Workspace destruction verification is missing: ${expected}" >&2
    exit 1
  fi
done

for prohibited in \
  'delete-instance' \
  'delete-key-pair' \
  'release-static-ip' \
  'delete-budget' \
  'delete-instance-snapshot' \
  's3api delete-object'; do
  if grep -Fq -- "$prohibited" "$verify"; then
    echo "Workspace destruction verification contains mutation: ${prohibited}" >&2
    exit 1
  fi
done

echo "Post-destruction verification is read-only and proves retained boundaries."
