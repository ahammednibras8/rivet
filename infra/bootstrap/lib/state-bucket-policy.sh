#!/usr/bin/env bash

render_state_bucket_policy() {
  local bucket="$1"
  local state_object_key="$2"
  local allowed_operator_role_arn="$3"

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
        "arn:aws:s3:::${bucket}",
        "arn:aws:s3:::${bucket}/*"
      ],
      "Condition": {
        "Bool": {
          "aws:SecureTransport": "false"
        }
      }
    },
    {
      "Sid": "DenyUnexpectedPrincipals",
      "Effect": "Deny",
      "Principal": "*",
      "Action": "s3:*",
      "Resource": [
        "arn:aws:s3:::${bucket}",
        "arn:aws:s3:::${bucket}/*"
      ],
      "Condition": {
        "ArnNotEquals": {
          "aws:PrincipalArn": "${allowed_operator_role_arn}"
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
      "Resource": "arn:aws:s3:::${bucket}/${state_object_key}"
    }
  ]
}
EOF
}
