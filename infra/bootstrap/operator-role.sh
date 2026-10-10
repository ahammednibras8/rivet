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
  plan)
    ;;
  *)
    printf 'usage: %s plan\n' "$0" >&2
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
printf 'Plan: ensure rivet-developer can assume the least-privilege rivet-operator role.\n'
printf 'No AWS resources were changed.\n'
