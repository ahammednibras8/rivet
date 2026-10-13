#!/usr/bin/env bash

require_temporary_aws_identity() {
  local region="$1"
  local identity
  local account_id
  local caller_arn
  local role_name
  local role_arn

  if ! command -v aws >/dev/null 2>&1; then
    printf 'error: AWS CLI v2 is required\n' >&2
    return 1
  fi

  identity="$(
    aws sts get-caller-identity \
      --region "$region" \
      --query '[Account,Arn]' \
      --output text
  )" || return $?

  IFS=$'\t' read -r account_id caller_arn <<<"$identity"

  if [[ ! "$account_id" =~ ^[0-9]{12}$ ]]; then
    printf 'error: AWS returned an invalid account ID\n' >&2
    return 1
  fi

  if [[ "$caller_arn" =~ ^arn:aws:sts::${account_id}:assumed-role/([^/]+)/[^/]+$ ]]; then
    role_name="${BASH_REMATCH[1]}"
  else
    printf 'error: use temporary credentials from an assumed IAM role\n' >&2
    return 1
  fi

  if [[ "$role_name" != "rivet-operator" ]]; then
    printf 'error: use temporary credentials from rivet-operator\n' >&2
    return 1
  fi

  role_arn="$(
    aws iam get-role \
      --role-name "$role_name" \
      --region "$region" \
      --query Role.Arn \
      --output text
  )" || return $?

  if [[ "$role_arn" != "arn:aws:iam::${account_id}:role/rivet-operator" ]]; then
    printf 'error: AWS returned an invalid operator role ARN\n' >&2
    return 1
  fi

  printf '%s\t%s\n' "$account_id" "$role_arn"
}

require_root_aws_identity() {
  local region="$1"
  local identity
  local account_id
  local caller_arn
  local expected_root_arn

  if ! command -v aws >/dev/null 2>&1; then
    printf 'error: AWS CLI v2 is required\n' >&2
    return 1
  fi

  identity="$(
    aws sts get-caller-identity \
      --region "$region" \
      --query '[Account,Arn]' \
      --output text
  )" || return $?

  IFS=$'\t' read -r account_id caller_arn <<<"$identity"

  if [[ ! "$account_id" =~ ^[0-9]{12}$ ]]; then
    printf 'error: AWS returned an invalid account ID\n' >&2
    return 1
  fi

  expected_root_arn="arn:aws:iam::${account_id}:root"

  if [[ "$caller_arn" != "$expected_root_arn" ]]; then
    printf 'error: use the AWS account root login only for IAM bootstrap\n' >&2
    return 1
  fi

  printf '%s\n' "$account_id"
}
