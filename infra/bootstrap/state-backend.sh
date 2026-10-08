#!/usr/bin/env bash

set -euo pipefail

script_directory="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
readonly script_directory

# shellcheck source=infra/bootstrap/lib/aws-session.sh
source "${script_directory}/lib/aws-session.sh"

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

aws s3api put-bucket-ownership-controls \
  --bucket "$state_bucket" \
  --expected-bucket-owner "$account_id" \
  --ownership-controls \
    'Rules=[{ObjectOwnership=BucketOwnerEnforced}]' \
  --region "$aws_region"

aws s3api put-public-access-block \
  --bucket "$state_bucket" \
  --expected-bucket-owner "$account_id" \
  --public-access-block-configuration \
    'BlockPublicAcls=true,IgnorePublicAcls=true,BlockPublicPolicy=true,RestrictPublicBuckets=true' \
  --region "$aws_region"

aws s3api put-bucket-encryption \
  --bucket "$state_bucket" \
  --expected-bucket-owner "$account_id" \
  --server-side-encryption-configuration \
    'Rules=[{ApplyServerSideEncryptionByDefault={SSEAlgorithm=AES256}}]' \
  --region "$aws_region"

aws s3api put-bucket-versioning \
  --bucket "$state_bucket" \
  --expected-bucket-owner "$account_id" \
  --versioning-configuration 'Status=Enabled' \
  --region "$aws_region"

aws s3api put-bucket-tagging \
  --bucket "$state_bucket" \
  --expected-bucket-owner "$account_id" \
  --tagging \
    'TagSet=[{Key=ManagedBy,Value=AWSCLI},{Key=Phase,Value=phase-1},{Key=Project,Value=Rivet}]' \
  --region "$aws_region"

aws s3api put-bucket-lifecycle-configuration \
  --bucket "$state_bucket" \
  --expected-bucket-owner "$account_id" \
  --lifecycle-configuration \
    'Rules=[{ID=LimitNoncurrentStateAndLockVersions,Status=Enabled,Filter={Prefix=phase-1/},NoncurrentVersionExpiration={NoncurrentDays=90,NewerNoncurrentVersions=10},Expiration={ExpiredObjectDeleteMarker=true}}]' \
  --region "$aws_region"

bucket_policy="$(
  cat <<EOF
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Sid": "DenyInsecureTransport",
      "Effect": "Deny",
      "Principal": "*",
      "Action": "s3:*",
      "Resource": [
        "arn:aws:s3:::${state_bucket}",
        "arn:aws:s3:::${state_bucket}/*"
      ],
      "Condition": {
        "Bool": {
          "aws:SecureTransport": "false"
        }
      }
    },
    {
      "Sid": "DenyStateDeletion",
      "Effect": "Deny",
      "Principal": "*",
      "Action": [
        "s3:DeleteObject",
        "s3:DeleteObjectVersion"
      ],
      "Resource": "arn:aws:s3:::${state_bucket}/${state_key}"
    }
  ]
}
EOF
)"

aws s3api put-bucket-policy \
  --bucket "$state_bucket" \
  --expected-bucket-owner "$account_id" \
  --policy "$bucket_policy" \
  --region "$aws_region"

printf 'State bucket protection settings converged.\n'
