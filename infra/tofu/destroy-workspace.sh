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

for required_command in awk git install jq shasum sleep tofu; do
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

aws_identity="$(require_temporary_aws_identity "$aws_region")"
readonly aws_identity

IFS=$'\t' read -r account_id operator_role_arn <<<"$aws_identity"
readonly account_id operator_role_arn

state_bucket="rivet-tofu-state-${account_id}-${aws_region}-an"
readonly state_bucket

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

printf 'AWS temporary-role preflight passed: %s\n' "$operator_role_arn"

wait_for_instance_state() {
  local expected_state="$1"
  local instance_state

  for ((attempt = 1; attempt <= 60; attempt++)); do
    instance_state="$(
      aws lightsail get-instance-state \
        --instance-name "$instance_name" \
        --region "$aws_region" \
        --query state.name \
        --output text
    )"

    if [[ "$instance_state" == "$expected_state" ]]; then
      return 0
    fi

    sleep 5
  done

  printf 'error: instance did not reach state %s\n' "$expected_state" >&2
  return 1
}

wait_for_snapshot_available() {
  local snapshot_name="$1"
  local snapshot_response
  local snapshot_state

  for ((attempt = 1; attempt <= 360; attempt++)); do
    snapshot_response="$(
      aws lightsail get-instance-snapshot \
        --instance-snapshot-name "$snapshot_name" \
        --region "$aws_region"
    )"
    snapshot_state="$(jq -r '.instanceSnapshot.state' <<<"$snapshot_response")"

    if [[ "$snapshot_state" == "available" ]]; then
      printf '%s\n' "$snapshot_response"
      return 0
    fi

    if [[ "$snapshot_state" != "pending" ]]; then
      printf 'error: retained snapshot entered state %s\n' \
        "$snapshot_state" >&2
      return 1
    fi

    sleep 10
  done

  printf 'error: retained snapshot did not become available\n' >&2
  return 1
}

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

  canary_key="canary/issue-14.json"
  canary_body="${evidence_directory}/canary-body.json"
  canary_record="${evidence_directory}/canary.json"
  readonly canary_key canary_body canary_record

  created_at_utc="$(date -u '+%Y-%m-%dT%H:%M:%SZ')"
  repository_commit="$(git -C "$repository_root" rev-parse HEAD)"
  readonly created_at_utc repository_commit

  jq -n \
    --arg created_at_utc "$created_at_utc" \
    --arg repository_commit "$repository_commit" \
    '{
      schemaVersion: 1,
      purpose: "Issue #14 unrelated destruction canary",
      createdAtUtc: $created_at_utc,
      repositoryCommit: $repository_commit
    }' >"$canary_body"

  put_response="$(
    aws s3api put-object \
      --bucket "$state_bucket" \
      --key "$canary_key" \
      --body "$canary_body" \
      --server-side-encryption AES256 \
      --content-type application/json \
      --tagging "ManagedBy=Rivet&Project=Rivet&Purpose=DestructionCanary" \
      --region "$aws_region"
  )"
  readonly put_response

  version_id="$(
    jq -er '.VersionId | select(type == "string" and length > 0)' \
      <<<"$put_response"
  )"
  e_tag="$(jq -er '.ETag' <<<"$put_response")"
  readonly version_id e_tag

  canary_head="$(
    aws s3api head-object \
      --bucket "$state_bucket" \
      --key "$canary_key" \
      --version-id "$version_id" \
      --region "$aws_region"
  )"
  readonly canary_head

  if ! jq -e \
    --arg version_id "$version_id" \
    --arg e_tag "$e_tag" \
    '
      .ServerSideEncryption == "AES256" and
      .VersionId == $version_id and
      .ETag == $e_tag and
      .ContentLength > 0
    ' <<<"$canary_head" >/dev/null; then
    printf 'error: destruction canary metadata verification failed\n' >&2
    exit 1
  fi

  canary_tags="$(
    aws s3api get-object-tagging \
      --bucket "$state_bucket" \
      --key "$canary_key" \
      --version-id "$version_id" \
      --region "$aws_region"
  )"
  readonly canary_tags

  if ! jq -e '
    (.TagSet | map({key: .Key, value: .Value}) | from_entries) as $tags |
    $tags.ManagedBy == "Rivet" and
    $tags.Project == "Rivet" and
    $tags.Purpose == "DestructionCanary" and
    ($tags | length) == 3
  ' <<<"$canary_tags" >/dev/null; then
    printf 'error: destruction canary tags verification failed\n' >&2
    exit 1
  fi

  body_sha256="$(
    shasum -a 256 "$canary_body" |
      awk '{print $1}'
  )"
  readonly body_sha256

  jq -n \
    --arg bucket "$state_bucket" \
    --arg key "$canary_key" \
    --arg version_id "$version_id" \
    --arg e_tag "$e_tag" \
    --arg sha256 "$body_sha256" \
    --arg created_at_utc "$created_at_utc" \
    '{
      bucket: $bucket,
      key: $key,
      versionId: $version_id,
      eTag: $e_tag,
      sha256: $sha256,
      serverSideEncryption: "AES256",
      createdAtUtc: $created_at_utc
    }' >"$canary_record"

  chmod 0600 "$canary_body" "$canary_record"

  printf 'Encrypted destruction canary created and verified: s3://%s/%s\n' \
    "$state_bucket" \
    "$canary_key"

  snapshot_record="${evidence_directory}/snapshot.json"
  snapshot_name="${instance_name}-retained-$(date -u '+%Y%m%dT%H%M%SZ')"
  readonly snapshot_record snapshot_name

  manual_snapshots="$(
    aws lightsail get-instance-snapshots \
      --region "$aws_region"
  )"
  readonly manual_snapshots

  if ! jq -e '
    [
      .instanceSnapshots[]? |
      (.tags | map({key: .key, value: .value}) | from_entries) as $tags |
      select(
        $tags.Project == "Rivet" and
        $tags.Purpose == "RetainedBackup"
      )
    ] |
    length == 0
  ' <<<"$manual_snapshots" >/dev/null; then
    printf 'error: a retained Rivet snapshot already exists\n' >&2
    exit 1
  fi

  initial_instance_state="$(
    aws lightsail get-instance-state \
      --instance-name "$instance_name" \
      --region "$aws_region" \
      --query state.name \
      --output text
  )"
  readonly initial_instance_state

  if [[ "$initial_instance_state" != "running" ]]; then
    printf 'error: workspace must be running before snapshot preparation\n' >&2
    exit 1
  fi

  restart_required=false

  restart_instance_after_failure() {
    local exit_status=$?

    if [[ "$restart_required" == true ]]; then
      aws lightsail start-instance \
        --instance-name "$instance_name" \
        --region "$aws_region" >/dev/null 2>&1 || true
    fi

    return "$exit_status"
  }

  trap restart_instance_after_failure EXIT

  aws lightsail stop-instance \
    --instance-name "$instance_name" \
    --region "$aws_region" >/dev/null
  restart_required=true

  wait_for_instance_state stopped

  aws lightsail create-instance-snapshot \
    --instance-name "$instance_name" \
    --instance-snapshot-name "$snapshot_name" \
    --tags \
      key=ManagedBy,value=Rivet \
      key=Project,value=Rivet \
      key=Purpose,value=RetainedBackup \
      key=Workspace,value=primary \
    --region "$aws_region" >/dev/null

  aws lightsail start-instance \
    --instance-name "$instance_name" \
    --region "$aws_region" >/dev/null

  wait_for_instance_state running
  restart_required=false

  snapshot_response="$(wait_for_snapshot_available "$snapshot_name")"
  readonly snapshot_response

  if ! jq -e \
    --arg snapshot_name "$snapshot_name" \
    '
      .instanceSnapshot as $snapshot |
      ($snapshot.tags |
        map({key: .key, value: .value}) |
        from_entries
      ) as $tags |
      $snapshot.name == $snapshot_name and
      $snapshot.state == "available" and
      $snapshot.fromInstanceName == "rivet-workspace" and
      $snapshot.sizeInGb == 80 and
      $tags.ManagedBy == "Rivet" and
      $tags.Project == "Rivet" and
      $tags.Purpose == "RetainedBackup" and
      $tags.Workspace == "primary"
    ' <<<"$snapshot_response" >/dev/null; then
    printf 'error: retained snapshot verification failed\n' >&2
    exit 1
  fi

  jq '
    .instanceSnapshot |
    {
      name,
      arn,
      state,
      fromInstanceName,
      createdAt,
      sizeInGb,
      tags,
      monthlyUpperBoundUsd: 4
    }
  ' <<<"$snapshot_response" >"$snapshot_record"

  chmod 0600 "$snapshot_record"

  printf 'Retained manual snapshot created and verified: %s\n' \
    "$snapshot_name"

  printf 'Protected preparation directory: %s\n' "$evidence_directory"
  printf 'Preparation completed; the canary and retained snapshot were created.\n'
else
  printf 'Preflight is read-only; no infrastructure was changed.\n'
fi
