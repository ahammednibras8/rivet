#!/usr/bin/env bash

set -euo pipefail

script_directory="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
readonly script_directory

# shellcheck source=infra/bootstrap/lib/aws-session.sh
source "${script_directory}/lib/aws-session.sh"
# shellcheck source=infra/bootstrap/lib/operator-role-policy.sh
source "${script_directory}/lib/operator-role-policy.sh"

readonly aws_region="ap-south-1"
readonly login_user="rivet-developer"
readonly operator_role="rivet-operator"
readonly action="${1:-plan}"

case "$action" in
  plan | apply | verify)
    ;;
  *)
    printf 'usage: %s [plan|apply|verify]\n' "$0" >&2
    exit 64
    ;;
esac

export AWS_PAGER=""

aws_account_id="$(require_root_aws_identity "$aws_region")"
readonly aws_account_id

printf 'AWS root bootstrap preflight passed.\n'
printf 'Account: %s\n' "$aws_account_id"
printf 'Login user: %s\n' "$login_user"
printf 'Operator role: %s\n' "$operator_role"

if [[ "$action" == "plan" ]]; then
  printf 'Plan: ensure rivet-developer can assume the least-privilege rivet-operator role.\n'
  printf 'No AWS resources were changed.\n'
  exit 0
fi

if [[ "$action" == "apply" ]]; then
  printf 'Type rivet-operator to approve IAM role convergence: ' >&2
  IFS= read -r confirmation

  if [[ "$confirmation" != "$operator_role" ]]; then
    printf 'error: confirmation did not match rivet-operator\n' >&2
    exit 1
  fi
fi

expected_login_user_arn="arn:aws:iam::${aws_account_id}:user/${login_user}"
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

expected_operator_role_arn="arn:aws:iam::${aws_account_id}:role/${operator_role}"
readonly expected_operator_role_arn

if [[ "$action" == "apply" ]]; then
  temporary_directory="$(
    mktemp -d "${TMPDIR:-/tmp}/rivet-operator-role.XXXXXX"
  )"
  readonly temporary_directory
  trap 'rm -rf -- "$temporary_directory"' EXIT

  trust_policy_file="${temporary_directory}/trust-policy.json"
  readonly trust_policy_file
  render_operator_trust_policy "$aws_account_id" >"$trust_policy_file"

  assume_policy_file="${temporary_directory}/assume-policy.json"
  readonly assume_policy_file
  render_operator_assume_policy "$aws_account_id" >"$assume_policy_file"

  state_policy_file="${temporary_directory}/state-policy.json"
  identity_policy_file="${temporary_directory}/identity-policy.json"
  lightsail_policy_file="${temporary_directory}/lightsail-policy.json"
  budget_policy_file="${temporary_directory}/budget-policy.json"
  readonly state_policy_file identity_policy_file lightsail_policy_file budget_policy_file

  render_operator_state_policy "$aws_account_id" >"$state_policy_file"
  render_operator_identity_policy "$aws_account_id" >"$identity_policy_file"
  render_operator_lightsail_policy >"$lightsail_policy_file"
  render_operator_budget_policy "$aws_account_id" >"$budget_policy_file"

  existing_role_arn="$(
    # The backticks below are JMESPath literal delimiters.
    # shellcheck disable=SC2016
    aws iam list-roles \
      --region "$aws_region" \
      --query 'Roles[?RoleName==`rivet-operator`].Arn | [0]' \
      --output text
  )"
  readonly existing_role_arn

  if [[ "$existing_role_arn" == "None" ]]; then
    created_role_arn="$(
      aws iam create-role \
        --role-name "$operator_role" \
        --assume-role-policy-document "file://${trust_policy_file}" \
        --description "Rivet cloud foundation operator" \
        --max-session-duration 3600 \
        --tags \
          "Key=ManagedBy,Value=AWSCLI" \
          "Key=Project,Value=Rivet" \
          "Key=Workspace,Value=primary" \
        --region "$aws_region" \
        --query Role.Arn \
        --output text
    )"
    readonly created_role_arn

    if [[ "$created_role_arn" != "$expected_operator_role_arn" ]]; then
      printf 'error: AWS returned an unexpected created role ARN\n' >&2
      exit 1
    fi

    printf 'Operator role created: %s\n' "$created_role_arn"
  elif [[ "$existing_role_arn" == "$expected_operator_role_arn" ]]; then
    aws iam update-assume-role-policy \
      --role-name "$operator_role" \
      --policy-document "file://${trust_policy_file}" \
      --region "$aws_region"

    aws iam update-role \
      --role-name "$operator_role" \
      --description "Rivet cloud foundation operator" \
      --max-session-duration 3600 \
      --region "$aws_region"

    aws iam tag-role \
      --role-name "$operator_role" \
      --tags \
        "Key=ManagedBy,Value=AWSCLI" \
        "Key=Project,Value=Rivet" \
        "Key=Workspace,Value=primary" \
      --region "$aws_region"

    printf 'Operator role updated: %s\n' "$existing_role_arn"
  else
    printf 'error: AWS returned an unexpected existing role ARN\n' >&2
    exit 1
  fi

  aws iam put-user-policy \
    --user-name "$login_user" \
    --policy-name "rivet-assume-operator" \
    --policy-document "file://${assume_policy_file}" \
    --region "$aws_region"

  aws iam put-role-policy \
    --role-name "$operator_role" \
    --policy-name "rivet-state-backend" \
    --policy-document "file://${state_policy_file}" \
    --region "$aws_region"

  aws iam put-role-policy \
    --role-name "$operator_role" \
    --policy-name "rivet-identity" \
    --policy-document "file://${identity_policy_file}" \
    --region "$aws_region"

  aws iam put-role-policy \
    --role-name "$operator_role" \
    --policy-name "rivet-lightsail" \
    --policy-document "file://${lightsail_policy_file}" \
    --region "$aws_region"

  aws iam put-role-policy \
    --role-name "$operator_role" \
    --policy-name "rivet-budget" \
    --policy-document "file://${budget_policy_file}" \
    --region "$aws_region"

  printf 'Operator role trust boundary converged.\n'
  printf 'Login user assume-role policy converged.\n'
  printf 'Operator role permission policies converged.\n'
  exit 0
fi

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
