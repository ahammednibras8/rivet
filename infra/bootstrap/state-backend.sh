#!/usr/bin/env bash

set -euo pipefail

readonly aws_region="ap-south-1"
readonly bucket_prefix="rivet-tofu-state"
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

if ! command -v aws >/dev/null 2>&1; then
  printf 'error: AWS CLI v2 is required\n' >&2
  exit 1
fi

identity="$(
  aws sts get-caller-identity \
    --region "$aws_region" \
    --query '[Account,Arn]' \
    --output text
)"

IFS=$'\t' read -r account_id caller_arn <<<"$identity"

if [[ ! "$account_id" =~ ^[0-9]{12}$ ]]; then
  printf 'error: AWS returned an invalid account ID\n' >&2
  exit 1
fi

case "$caller_arn" in
  arn:aws:sts::*:assumed-role/*)
    ;;
  *)
    printf 'error: use temporary credentials from an assumed IAM role\n' >&2
    exit 1
    ;;
esac

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

if aws s3api head-bucket \
  --bucket "$state_bucket" \
  --expected-bucket-owner "$account_id" \
  --region "$aws_region" 2>/dev/null; then
  printf 'State bucket already exists.\n'
else
  aws s3api create-bucket \
    --bucket "$state_bucket" \
    --bucket-namespace account-regional \
    --object-ownership BucketOwnerEnforced \
    --create-bucket-configuration "LocationConstraint=${aws_region}" \
    --region "$aws_region" \
    >/dev/null

  printf 'State bucket created.\n'
fi

actual_region="$(
  aws s3api get-bucket-location \
    --bucket "$state_bucket" \
    --expected-bucket-owner "$account_id" \
    --region "$aws_region" \
    --query LocationConstraint \
    --output text
)"

if [[ "$actual_region" != "$aws_region" ]]; then
  printf 'error: state bucket exists in unexpected region %s\n' \
    "$actual_region" >&2
  exit 1
fi

printf 'State bucket ownership and region verified.\n'
