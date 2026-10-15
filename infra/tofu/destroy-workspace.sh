#!/usr/bin/env bash

set -euo pipefail

script_directory="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
readonly script_directory
repository_root="$(cd "${script_directory}/../.." && pwd)"
readonly repository_root
readonly tofu_directory="$script_directory"
readonly evidence_directory="${repository_root}/temp/issue-14"

# shellcheck source=infra/bootstrap/lib/aws-session.sh
source "${repository_root}/infra/bootstrap/lib/aws-session.sh"

readonly required_tofu_version="1.13.1"
readonly aws_region="ap-south-1"
readonly instance_name="rivet-workspace"
readonly static_ip_name="rivet-workspace-ip"
readonly key_pair_name="rivet-operator"
readonly budget_name="rivet-monthly-cost"
readonly action="${1:-preflight}"

case "$action" in
  preflight | prepare)
    ;;
  *)
    printf 'usage: %s [preflight|prepare]\n' "$0" >&2
    exit 64
    ;;
esac

for required_command in git install jq tofu; do
  if ! command -v "$required_command" >/dev/null 2>&1; then
    printf 'error: %s is required\n' "$required_command" >&2
    exit 1
  fi
done

installed_tofu_version="$(tofu version -json | jq -r '.terraform_version')"
readonly installed_tofu_version

if [[ "$installed_tofu_version" != "$required_tofu_version" ]]; then
  printf 'error: OpenTofu %s is required; found %s\n' \
    "$required_tofu_version" \
    "$installed_tofu_version" >&2
  exit 1
fi

if [[ -e "${tofu_directory}/terraform.tfstate" ||
  -e "${tofu_directory}/terraform.tfstate.backup" ]]; then
  printf 'error: local OpenTofu state exists; destruction requires the protected S3 backend\n' >&2
  exit 1
fi

tracked_status="$(
  git -C "$repository_root" status --porcelain --untracked-files=no
)"
readonly tracked_status

if [[ -n "$tracked_status" ]]; then
  printf 'error: Tracked worktree must be clean before destruction planning\n' >&2
  exit 1
fi

require_temporary_aws_identity "$aws_region" >/dev/null

expected_resources="$(
  printf '%s\n' \
    'aws_budgets_budget.workspace' \
    'aws_lightsail_instance.workspace' \
    'aws_lightsail_instance_public_ports.workspace' \
    'aws_lightsail_key_pair.operator' \
    'aws_lightsail_static_ip.workspace' \
    'aws_lightsail_static_ip_attachment.workspace' |
    LC_ALL=C sort
)"
readonly expected_resources

actual_resources="$(
  tofu -chdir="$tofu_directory" state list |
    LC_ALL=C sort
)"
readonly actual_resources

if [[ "$actual_resources" != "$expected_resources" ]]; then
  printf 'error: OpenTofu state does not match the exact destruction boundary\n' >&2
  diff -u \
    <(printf '%s\n' "$expected_resources") \
    <(printf '%s\n' "$actual_resources") >&2 || true
  exit 1
fi

printf 'AWS temporary-role preflight passed.\n'
printf 'Selected instance: %s\n' "$instance_name"
printf 'Selected static IP: %s\n' "$static_ip_name"
printf 'Selected key pair: %s\n' "$key_pair_name"
printf 'Selected budget: %s\n' "$budget_name"
printf 'Selected OpenTofu resources: 6\n'
printf 'Retained manual snapshot: outside OpenTofu state\n'
printf 'State backend: outside OpenTofu state\n'

if [[ "$action" == "prepare" ]]; then
  if [[ -e "$evidence_directory" ]]; then
    printf 'error: Preparation evidence already exists; review or remove it explicitly: %s\n' \
      "$evidence_directory" >&2
    exit 1
  fi

  umask 077
  install -d -m 0700 "$evidence_directory"

  printf 'Protected preparation directory: %s\n' "$evidence_directory"
  printf 'Local preparation completed; no AWS resources were changed.\n'
else
  printf 'Preflight is read-only; no infrastructure was changed.\n'
fi
