#!/usr/bin/env bash

render_workspace_destroy_policy() {
  local account_id="$1"
  local static_ip_arn="$2"
  local state_bucket
  local budget_arn
  local canary_arn

  if [[ ! "$account_id" =~ ^[0-9]{12}$ ]]; then
    printf 'error: invalid AWS account ID\n' >&2
    return 1
  fi

  if [[ ! "$static_ip_arn" =~ ^arn:aws:lightsail:ap-south-1:${account_id}:StaticIp/[0-9a-f-]{36}$ ]]; then
    printf 'error: invalid Rivet static IP ARN\n' >&2
    return 1
  fi

  state_bucket="rivet-tofu-state-${account_id}-ap-south-1-an"
  budget_arn="arn:aws:budgets::${account_id}:budget/rivet-monthly-cost"
  canary_arn="arn:aws:s3:::${state_bucket}/canary/issue-14.json"

  cat <<EOF
{
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
      "Resource": "${static_ip_arn}",
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
      "Resource": "${budget_arn}"
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
      "Resource": "${canary_arn}"
    }
  ]
}
EOF
}
