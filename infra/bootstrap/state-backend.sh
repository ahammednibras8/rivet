#!/usr/bin/env bash

set -euo pipefail

script_directory="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
readonly script_directory

# shellcheck source=infra/bootstrap/lib/aws-session.sh
source "${script_directory}/lib/aws-session.sh"
# shellcheck source=infra/bootstrap/lib/state-bucket-policy.sh
source "${script_directory}/lib/state-bucket-policy.sh"
# shellcheck source=infra/bootstrap/lib/state-bucket.sh
source "${script_directory}/lib/state-bucket.sh"

readonly aws_region="ap-south-1"
readonly bucket_prefix="rivet-tofu-state"
readonly state_key="phase-1/rivet.tfstate"
readonly action="${1:-plan}"

case "$action" in
  plan | apply)
    ;;
  *)
    printf 'usage: %s [plan|apply]\n' "$0" >&2
    exit 64
    ;;
esac

export AWS_PAGER=""

account_id="$(require_temporary_aws_account_id "$aws_region")"
readonly account_id

readonly state_bucket="${bucket_prefix}-${account_id}-${aws_region}-an"

printf 'AWS temporary-role preflight passed.\n'
printf 'Target region: %s\n' "$aws_region"
printf 'Target state bucket: %s\n' "$state_bucket"
if [[ "$action" == "plan" ]]; then
  printf 'Plan: ensure the account-regional state bucket exists.\n'
  printf 'No AWS resources were changed.\n'
  exit 0
fi

printf 'Type the target bucket name to approve creation: ' >&2
IFS= read -r confirmation

if [[ "$confirmation" != "$state_bucket" ]]; then
  printf 'error: confirmation did not match the target bucket\n' >&2
  exit 1
fi

ensure_state_bucket "$state_bucket" "$account_id" "$aws_region"
configure_state_bucket "$state_bucket" "$account_id" "$aws_region" "$state_key"
