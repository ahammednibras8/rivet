#!/usr/bin/env bash

set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
script="${repo_root}/infra/tofu/destroy-workspace.sh"

bash -n "$script"

# Dollar signs in this list are literal product-code assertions.
# shellcheck disable=SC2016
required_text=(
  'state_bucket="rivet-tofu-state-${account_id}-${aws_region}-an"'
  'canary_key="canary/issue-14.json"'
  'canary_body="${evidence_directory}/canary-body.json"'
  'canary_record="${evidence_directory}/canary.json"'
  'aws s3api put-object'
  '--server-side-encryption AES256'
  '--content-type application/json'
  '--tagging "ManagedBy=Rivet&Project=Rivet&Purpose=DestructionCanary"'
  'aws s3api head-object'
  'aws s3api get-object-tagging'
  'Purpose == "DestructionCanary"'
  '.ServerSideEncryption == "AES256"'
  'sha256'
  'versionId'
  'eTag'
  'chmod 0600 "$canary_body" "$canary_record"'
  'Encrypted destruction canary created and verified:'
)

for expected in "${required_text[@]}"; do
  if ! grep -Fq -- "$expected" "$script"; then
    echo "Workspace preparation is missing canary control: ${expected}" >&2
    exit 1
  fi
done

prohibited_text=(
  's3api delete-object'
  's3 rm'
  'delete-bucket'
)

for prohibited in "${prohibited_text[@]}"; do
  if grep -Fq -- "$prohibited" "$script"; then
    echo "Canary preparation contains prohibited deletion: ${prohibited}" >&2
    exit 1
  fi
done

echo "The destruction canary is encrypted, tagged, integrity-recorded, and retained."
