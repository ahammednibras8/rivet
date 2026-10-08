#!/usr/bin/env bash

require_temporary_aws_account_id() {
  local region="$1"
  local identity
  local account_id
  local caller_arn

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

  case "$caller_arn" in
    arn:aws:sts::*:assumed-role/*)
      ;;
    *)
      printf 'error: use temporary credentials from an assumed IAM role\n' >&2
      return 1
      ;;
  esac

  printf '%s\n' "$account_id"
}
