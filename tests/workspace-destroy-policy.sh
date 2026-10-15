#!/usr/bin/env bash

set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
policy_library="${repo_root}/infra/bootstrap/lib/workspace-destroy-policy.sh"

if [[ ! -f "$policy_library" ]]; then
  echo "Missing temporary workspace-destroy policy library: ${policy_library}" >&2
  exit 1
fi

# shellcheck source=infra/bootstrap/lib/workspace-destroy-policy.sh
source "$policy_library"

account_id="123456789012"
static_ip_arn="arn:aws:lightsail:ap-south-1:${account_id}:StaticIp/11111111-2222-3333-4444-555555555555"
state_bucket="rivet-tofu-state-${account_id}-ap-south-1-an"
expected_budget="arn:aws:budgets::${account_id}:budget/rivet-monthly-cost"
expected_canary="arn:aws:s3:::${state_bucket}/canary/issue-14.json"

destroy_policy="$(render_workspace_destroy_policy "$account_id" "$static_ip_arn")"

if ! jq -e \
  --arg static_ip "$static_ip_arn" \
  --arg budget "$expected_budget" \
  --arg canary "$expected_canary" \
  '. == {
    "Version": "2012-10-17",
    "Statement": [
      {
        "Sid": "InventoryDestroyBoundary",
        "Effect": "Allow",
        "Action": [
          "lightsail:GetAlarms",
          "lightsail:GetBuckets",
          "lightsail:GetContainerServices",
          "lightsail:GetDisks",
          "lightsail:GetDistributions",
          "lightsail:GetInstanceSnapshots",
          "lightsail:GetInstances",
          "lightsail:GetKeyPairs",
          "lightsail:GetLoadBalancers",
          "lightsail:GetRelationalDatabases",
          "lightsail:GetStaticIps"
        ],
        "Resource": "*",
        "Condition": {
          "StringEquals": {
            "aws:RequestedRegion": "ap-south-1"
          }
        }
      },
      {
        "Sid": "DeleteSelectedWorkspaceIdentity",
        "Effect": "Allow",
        "Action": [
          "lightsail:DeleteInstance",
          "lightsail:DeleteKeyPair"
        ],
        "Resource": "*",
        "Condition": {
          "StringEquals": {
            "aws:RequestedRegion": "ap-south-1",
            "aws:ResourceTag/Project": "Rivet",
            "aws:ResourceTag/Workspace": "primary"
          }
        }
      },
      {
        "Sid": "DeleteSelectedWorkspaceAddress",
        "Effect": "Allow",
        "Action": [
          "lightsail:DetachStaticIp",
          "lightsail:ReleaseStaticIp"
        ],
        "Resource": $static_ip,
        "Condition": {
          "StringEquals": {
            "aws:RequestedRegion": "ap-south-1"
          }
        }
      },
      {
        "Sid": "DeleteSelectedWorkspaceBudget",
        "Effect": "Allow",
        "Action": "budgets:DeleteBudget",
        "Resource": $budget
      },
      {
        "Sid": "MaintainDestructionCanary",
        "Effect": "Allow",
        "Action": [
          "s3:GetObject",
          "s3:GetObjectTagging",
          "s3:PutObject",
          "s3:PutObjectTagging"
        ],
        "Resource": $canary
      }
    ]
  }' <<<"$destroy_policy" >/dev/null; then
  echo "The temporary destroy policy exceeds or misses the exact Issue #14 boundary" >&2
  exit 1
fi

for prohibited_action in \
  'lightsail:DeleteAutoSnapshot' \
  'lightsail:DeleteInstanceSnapshot' \
  's3:DeleteObject' \
  's3:DeleteBucket' \
  'iam:DeleteRole'; do
  if jq -e --arg action "$prohibited_action" \
    '[.Statement[].Action] | flatten | index($action) != null' \
    <<<"$destroy_policy" >/dev/null; then
    echo "The temporary destroy policy contains prohibited action: ${prohibited_action}" >&2
    exit 1
  fi
done

echo "The temporary workspace-destroy policy has exact resource and action boundaries."
