#!/usr/bin/env bash

set -euo pipefail

script_directory="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
readonly script_directory

repository_root="$(cd "${script_directory}/../.." && pwd)"
readonly repository_root
readonly tofu_directory="${repository_root}/infra/tofu"

# shellcheck source=infra/bootstrap/lib/aws-session.sh
source "${script_directory}/lib/aws-session.sh"

readonly aws_region="ap-south-1"
readonly bucket_prefix="rivet-tofu-state"
readonly required_tofu_version="1.13.1"

if ! command -v jq >/dev/null 2>&1; then
  printf 'error: jq is required\n' >&2
  exit 1
fi

if ! command -v tofu >/dev/null 2>&1; then
  printf 'error: OpenTofu %s is required\n' "$required_tofu_version" >&2
  exit 1
fi

installed_tofu_version="$(tofu version -json | jq -r '.terraform_version')"
readonly installed_tofu_version

if [[ "$installed_tofu_version" != "$required_tofu_version" ]]; then
  printf 'error: OpenTofu %s is required; found %s\n' \
    "$required_tofu_version" \
    "$installed_tofu_version" >&2
  exit 1
fi

if [[ -e "${tofu_directory}/terraform.tfstate" ||
  -e "${tofu_directory}/terraform.tfstate.backup" ]]; then
  printf 'error: local state exists; review migration before initializing S3\n' >&2
  exit 1
fi

aws_identity="$(require_temporary_aws_identity "$aws_region")"
readonly aws_identity

IFS=$'\t' read -r account_id operator_role_arn <<<"$aws_identity"
readonly account_id
readonly operator_role_arn
readonly state_bucket="${bucket_prefix}-${account_id}-${aws_region}-an"

printf 'Operator role: %s\n' "$operator_role_arn"
printf 'Initializing backend bucket: %s\n' "$state_bucket"

tofu -chdir="$tofu_directory" init \
  -input=false \
  -reconfigure \
  -backend-config="bucket=${state_bucket}"
