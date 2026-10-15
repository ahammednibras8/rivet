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

case "$action" in
  plan | apply | verify | revoke)
    ;;
  *)
    printf 'usage: %s [plan|apply|verify|revoke]\n' "$0" >&2
    exit 64
    ;;
esac

export AWS_PAGER=""

if ! command -v jq >/dev/null 2>&1; then
  printf 'error: jq is required\n' >&2
  exit 1
fi

account_id="$(require_root_aws_identity "$aws_region")"
readonly account_id

printf 'AWS root IAM preflight passed.\n'
printf 'Operator role: %s\n' "$operator_role"
printf 'Temporary policy: %s\n' "$policy_name"

if [[ "$action" == "revoke" ]]; then
  printf 'Type REVOKE rivet-workspace DESTROY POLICY to continue: ' >&2
  IFS= read -r confirmation

  if [[ "$confirmation" != "REVOKE rivet-workspace DESTROY POLICY" ]]; then
    printf 'error: destroy-policy revocation confirmation did not match\n' >&2
    exit 1
  fi

  aws iam delete-role-policy \
    --role-name "$operator_role" \
    --policy-name "$policy_name" \
    --region "$aws_region"

  policy_present="$(
    # The backticks are JMESPath literals, not shell substitutions.
    # shellcheck disable=SC2016
    aws iam list-role-policies \
      --role-name "$operator_role" \
      --region "$aws_region" \
      --query 'contains(PolicyNames, `rivet-workspace-destroy`)' \
      --output text
  )"
  readonly policy_present

  if [[ "$policy_present" != "False" ]]; then
    printf 'error: temporary destroy policy remains installed\n' >&2
    exit 1
  fi

  printf 'Temporary destroy policy revoked.\n'
  exit 0
fi

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

verify_installed_policy() {
  local installed_policy
  local expected_canonical
  local installed_canonical

  installed_policy="$(
    aws iam get-role-policy \
      --role-name "$operator_role" \
      --policy-name "$policy_name" \
      --region "$aws_region" \
      --query PolicyDocument \
      --output json
  )" || return $?

  expected_canonical="$(
    jq --sort-keys --compact-output . <<<"$destroy_policy"
  )" || return $?

  installed_canonical="$(
    jq --sort-keys --compact-output . <<<"$installed_policy"
  )" || return $?

  if [[ "$installed_canonical" != "$expected_canonical" ]]; then
    printf 'error: installed destroy policy differs from the reviewed boundary\n' >&2
    return 1
  fi
}

printf 'Static IP: %s\n' "$static_ip_name"
printf 'Retained backup deletion: denied\n'
printf 'State backend deletion: denied\n'

case "$action" in
  plan)
    printf 'Plan: authorize only the selected workspace, address, budget, and canary boundary.\n'
    printf 'No AWS resources were changed.\n'
    ;;
  apply)
    printf 'Type AUTHORIZE rivet-workspace DESTROY POLICY to continue: ' >&2
    IFS= read -r confirmation

    if [[ "$confirmation" != "AUTHORIZE rivet-workspace DESTROY POLICY" ]]; then
      printf 'error: destroy-policy authorization confirmation did not match\n' >&2
      exit 1
    fi

    temporary_directory="$(
      mktemp -d "${TMPDIR:-/tmp}/rivet-destroy-policy.XXXXXX"
    )"
    readonly temporary_directory
    policy_file="${temporary_directory}/policy.json"
    readonly policy_file

    cleanup() {
      rm -f -- "$policy_file"
      rmdir "$temporary_directory" 2>/dev/null || true
    }
    trap cleanup EXIT

    umask 077
    printf '%s\n' "$destroy_policy" >"$policy_file"

    aws iam put-role-policy \
      --role-name "$operator_role" \
      --policy-name "$policy_name" \
      --policy-document "file://${policy_file}" \
      --region "$aws_region"

    verify_installed_policy
    printf 'Temporary destroy policy installed and verified.\n'
    ;;
  verify)
    verify_installed_policy
    printf 'Temporary destroy policy matches the reviewed boundary.\n'
    ;;
esac
