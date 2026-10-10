#!/usr/bin/env bash

render_operator_trust_policy() {
  local account_id="$1"

  cat <<EOF
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Sid": "AllowRivetDeveloper",
      "Effect": "Allow",
      "Principal": {
        "AWS": "arn:aws:iam::${account_id}:user/rivet-developer"
      },
      "Action": "sts:AssumeRole"
    }
  ]
}
EOF
}

render_operator_assume_policy() {
  local account_id="$1"

  cat <<EOF
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Sid": "AssumeRivetOperator",
      "Effect": "Allow",
      "Action": "sts:AssumeRole",
      "Resource": "arn:aws:iam::${account_id}:role/rivet-operator"
    }
  ]
}
EOF
}

render_operator_state_policy() {
  local account_id="$1"
  local bucket="rivet-tofu-state-${account_id}-ap-south-1-an"
  local state="arn:aws:s3:::${bucket}/rivet/infrastructure.tfstate"
  local lock="${state}.tflock"

  cat <<EOF
{
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
      "Resource": "arn:aws:s3:::${bucket}"
    },
    {
      "Sid": "ReadAndWriteRivetState",
      "Effect": "Allow",
      "Action": [
        "s3:GetObject",
        "s3:PutObject"
      ],
      "Resource": [
        "${state}",
        "${lock}"
      ]
    },
    {
      "Sid": "ReleaseRivetStateLock",
      "Effect": "Allow",
      "Action": "s3:DeleteObject",
      "Resource": "${lock}"
    }
  ]
}
EOF
}

render_operator_identity_policy() {
  local account_id="$1"

  cat <<EOF
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Sid": "InspectRivetOperatorRole",
      "Effect": "Allow",
      "Action": "iam:GetRole",
      "Resource": "arn:aws:iam::${account_id}:role/rivet-operator"
    }
  ]
}
EOF
}

render_operator_lightsail_policy() {
  cat <<'EOF'
{
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
}
EOF
}

render_operator_budget_policy() {
  local account_id="$1"

  cat <<EOF
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Sid": "ManageRivetBudget",
      "Effect": "Allow",
      "Action": [
        "budgets:ListTagsForResource",
        "budgets:ModifyBudget",
        "budgets:TagResource",
        "budgets:UntagResource",
        "budgets:ViewBudget"
      ],
      "Resource": "arn:aws:budgets::${account_id}:budget/rivet-monthly-cost"
    },
    {
      "Sid": "AuthorizeRivetBudgetBilling",
      "Effect": "Allow",
      "Action": [
        "aws-portal:ModifyBilling",
        "aws-portal:ViewBilling"
      ],
      "Resource": "*"
    }
  ]
}
EOF
}
