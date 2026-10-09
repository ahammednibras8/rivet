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
