#!/usr/bin/env bash

set -euo pipefail

script_directory="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# shellcheck source=infra/bootstrap/lib/aws-session.sh
source "${script_directory}/lib/aws-session.sh"
# shellcheck source=infra/bootstrap/lib/workspace-destroy-policy.sh
source "${script_directory}/lib/workspace-destroy-policy.sh"

readonly aws_region="ap-south-1"
readonly operator_role="rivet-operator"
readonly policy_name="rivet-workspace-destroy"
readonly static_ip_name="rivet-workspace-ip"
readonly action="${1:-plan}"

if [[ "$action" != "plan" ]]; then
  printf 'usage: %s [plan]\n' "$0" >&2
  exit 64
fi

export AWS_PAGER=""

if ! command -v jq >/dev/null 2>&1; then
  printf 'error: jq is required\n' >&2
  exit 1
fi

account_id="$(require_root_aws_identity "$aws_region")"
readonly account_id

static_ip_arn="$(
  aws lightsail get-static-ip \
    --static-ip-name "$static_ip_name" \
    --region "$aws_region" \
    --query staticIp.arn \
    --output text
)"
readonly static_ip_arn

destroy_policy="$(
  render_workspace_destroy_policy \
    "$account_id" \
    "$static_ip_arn"
)"
readonly destroy_policy

if ! jq -e '.Version == "2012-10-17"' \
  <<<"$destroy_policy" >/dev/null; then
  printf 'error: generated destroy policy is invalid\n' >&2
  exit 1
fi

printf 'AWS root IAM preflight passed.\n'
printf 'Operator role: %s\n' "$operator_role"
printf 'Temporary policy: %s\n' "$policy_name"
printf 'Static IP: %s\n' "$static_ip_name"
printf 'Retained backup deletion: denied\n'
printf 'State backend deletion: denied\n'
printf 'Plan: authorize only the selected workspace, address, budget, and canary boundary.\n'
printf 'No AWS resources were changed.\n'
