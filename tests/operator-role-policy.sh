#!/usr/bin/env bash

set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
policy_library="${repo_root}/infra/bootstrap/lib/operator-role-policy.sh"

if [[ ! -f "$policy_library" ]]; then
  echo "Missing operator role policy library: ${policy_library}" >&2
  exit 1
fi

# shellcheck source=infra/bootstrap/lib/operator-role-policy.sh
source "$policy_library"

account_id="123456789012"
expected_principal="arn:aws:iam::${account_id}:user/rivet-developer"
trust_policy="$(render_operator_trust_policy "$account_id")"

if ! jq -e \
  --arg principal "$expected_principal" \
  '(
    .Version == "2012-10-17" and
    (.Statement | length) == 1 and
    .Statement[0].Sid == "AllowRivetDeveloper" and
    .Statement[0].Effect == "Allow" and
    .Statement[0].Principal == {"AWS": $principal} and
    .Statement[0].Action == "sts:AssumeRole" and
    (.Statement[0] | has("Condition") | not)
  )' <<<"$trust_policy" >/dev/null; then
  echo "The operator trust policy must allow only rivet-developer to assume the role" >&2
  exit 1
fi

if grep -Fq '"Principal": "*"' <<<"$trust_policy"; then
  echo "The operator trust policy must not contain a wildcard principal" >&2
  exit 1
fi

expected_role="arn:aws:iam::${account_id}:role/rivet-operator"
assume_policy="$(render_operator_assume_policy "$account_id")"

if ! jq -e \
  --arg role "$expected_role" \
  '(
    .Version == "2012-10-17" and
    (.Statement | length) == 1 and
    .Statement[0].Sid == "AssumeRivetOperator" and
    .Statement[0].Effect == "Allow" and
    .Statement[0].Action == "sts:AssumeRole" and
    .Statement[0].Resource == $role
  )' <<<"$assume_policy" >/dev/null; then
  echo "The login identity must be allowed to assume only rivet-operator" >&2
  exit 1
fi

if grep -Fq '"Resource": "*"' <<<"$assume_policy"; then
  echo "The assume-role policy must not contain a wildcard resource" >&2
  exit 1
fi

state_bucket="rivet-tofu-state-${account_id}-ap-south-1-an"
state_key="arn:aws:s3:::${state_bucket}/rivet/infrastructure.tfstate"
lock_key="${state_key}.tflock"
state_policy="$(render_operator_state_policy "$account_id")"

if ! jq -e \
  --arg bucket "arn:aws:s3:::${state_bucket}" \
  --arg state "$state_key" \
  --arg lock "$lock_key" \
  '. == {
    "Version": "2012-10-17",
    "Statement": [
      {
        "Sid": "ManageRivetStateBucket",
        "Effect": "Allow",
        "Action": [
          "s3:CreateBucket",
          "s3:GetBucketLocation",
          "s3:GetBucketOwnershipControls",
          "s3:PutBucketOwnershipControls",
          "s3:GetBucketPublicAccessBlock",
          "s3:PutBucketPublicAccessBlock",
          "s3:GetEncryptionConfiguration",
          "s3:PutEncryptionConfiguration",
          "s3:GetBucketVersioning",
          "s3:PutBucketVersioning",
          "s3:GetBucketTagging",
          "s3:PutBucketTagging",
          "s3:GetLifecycleConfiguration",
          "s3:PutLifecycleConfiguration",
          "s3:GetBucketPolicy",
          "s3:PutBucketPolicy",
          "s3:ListBucket"
        ],
        "Resource": $bucket
      },
      {
        "Sid": "ReadAndWriteRivetState",
        "Effect": "Allow",
        "Action": ["s3:GetObject", "s3:PutObject"],
        "Resource": [$state, $lock]
      },
      {
        "Sid": "ReleaseRivetStateLock",
        "Effect": "Allow",
        "Action": "s3:DeleteObject",
        "Resource": $lock
      }
    ]
  }' <<<"$state_policy" >/dev/null; then
  echo "The operator state policy exceeds or misses its exact backend permissions" >&2
  exit 1
fi

identity_policy="$(render_operator_identity_policy "$account_id")"

if ! jq -e \
  --arg role "$expected_role" \
  '. == {
    "Version": "2012-10-17",
    "Statement": [
      {
        "Sid": "InspectRivetOperatorRole",
        "Effect": "Allow",
        "Action": "iam:GetRole",
        "Resource": $role
      }
    ]
  }' <<<"$identity_policy" >/dev/null; then
  echo "The operator identity policy must permit inspection of only its own role" >&2
  exit 1
fi

lightsail_policy="$(render_operator_lightsail_policy)"

if ! jq -e '
  . == {
    "Version": "2012-10-17",
    "Statement": [
      {
        "Sid": "ManageRivetLightsailWorkspace",
        "Effect": "Allow",
        "Action": [
          "lightsail:AllocateStaticIp",
          "lightsail:AttachStaticIp",
          "lightsail:CloseInstancePublicPorts",
          "lightsail:CreateInstances",
          "lightsail:GetInstance",
          "lightsail:GetInstanceAccessDetails",
          "lightsail:GetInstancePortStates",
          "lightsail:GetInstanceState",
          "lightsail:GetKeyPair",
          "lightsail:GetOperation",
          "lightsail:GetStaticIp",
          "lightsail:ImportKeyPair",
          "lightsail:PutInstancePublicPorts",
          "lightsail:TagResource",
          "lightsail:UntagResource"
        ],
        "Resource": "*",
        "Condition": {
          "StringEquals": {
            "aws:RequestedRegion": "ap-south-1"
          }
        }
      }
    ]
  }' <<<"$lightsail_policy" >/dev/null; then
  echo "The operator Lightsail policy must contain only the non-destructive Mumbai workspace actions" >&2
  exit 1
fi

echo "The Rivet login, operator role, identity, state, and Lightsail policies have exact boundaries."
