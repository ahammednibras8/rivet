#!/usr/bin/env bash

set -euo pipefail

script_directory="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
readonly script_directory

# shellcheck source=infra/bootstrap/lib/aws-session.sh
source "${script_directory}/lib/aws-session.sh"

readonly aws_region="ap-south-1"
readonly login_user="rivet-developer"
readonly operator_role="rivet-operator"
readonly action="${1:-plan}"

case "$action" in
  plan | verify)
    ;;
  *)
    printf 'usage: %s [plan|verify]\n' "$0" >&2
    exit 64
    ;;
esac

export AWS_PAGER=""

account_id="$(require_root_aws_identity "$aws_region")"
readonly account_id

printf 'AWS root bootstrap preflight passed.\n'
printf 'Account: %s\n' "$account_id"
printf 'Login user: %s\n' "$login_user"
printf 'Operator role: %s\n' "$operator_role"

if [[ "$action" == "plan" ]]; then
  printf 'Plan: ensure rivet-developer can assume the least-privilege rivet-operator role.\n'
  printf 'No AWS resources were changed.\n'
  exit 0
fi

expected_login_user_arn="arn:aws:iam::${account_id}:user/${login_user}"
readonly expected_login_user_arn

login_user_arn="$(
  aws iam get-user \
    --user-name "$login_user" \
    --region "$aws_region" \
    --query User.Arn \
    --output text
)"
readonly login_user_arn

if [[ "$login_user_arn" != "$expected_login_user_arn" ]]; then
  printf 'error: AWS returned an unexpected login user ARN\n' >&2
  exit 1
fi

expected_operator_role_arn="arn:aws:iam::${account_id}:role/${operator_role}"
readonly expected_operator_role_arn

operator_role_arn="$(
  aws iam get-role \
    --role-name "$operator_role" \
    --region "$aws_region" \
    --query Role.Arn \
    --output text
)"
readonly operator_role_arn

if [[ "$operator_role_arn" != "$expected_operator_role_arn" ]]; then
  printf 'error: AWS returned an unexpected operator role ARN\n' >&2
  exit 1
fi

printf 'Login user verified: %s\n' "$login_user_arn"
printf 'Operator role verified: %s\n' "$operator_role_arn"
printf 'Identity bootstrap targets verified.\n'
printf 'No AWS resources were changed.\n'
