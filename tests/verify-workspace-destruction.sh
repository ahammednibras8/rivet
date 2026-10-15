#!/usr/bin/env bash

set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
tofu_directory="${repo_root}/infra/tofu"
evidence_directory="${repo_root}/temp/issue-14"
plan_record="${evidence_directory}/plan.json"
canary_record="${evidence_directory}/canary.json"
snapshot_record="${evidence_directory}/snapshot.json"
verification_record="${evidence_directory}/verification.json"
aws_region="ap-south-1"

# shellcheck source=infra/bootstrap/lib/aws-session.sh
source "${repo_root}/infra/bootstrap/lib/aws-session.sh"

for command in awk aws date grep jq mktemp rm sed shasum tofu; do
  if ! command -v "$command" >/dev/null 2>&1; then
    printf 'error: %s is required\n' "$command" >&2
    exit 1
  fi
done

for evidence_file in "$plan_record" "$canary_record" "$snapshot_record"; do
  if [[ ! -r "$evidence_file" ]]; then
    printf 'error: required destruction evidence is unreadable: %s\n' \
      "$evidence_file" >&2
    exit 1
  fi
done

if [[ -e "$verification_record" ]]; then
  printf 'error: destruction verification refuses to overwrite: %s\n' \
    "$verification_record" >&2
  exit 1
fi

aws_identity="$(require_temporary_aws_identity "$aws_region")"
IFS=$'\t' read -r account_id operator_role_arn <<<"$aws_identity"

state_addresses="$(tofu -chdir="$tofu_directory" state list)"
if [[ -n "$state_addresses" ]]; then
  printf 'error: OpenTofu still manages workspace resources\n' >&2
  printf '%s\n' "$state_addresses" >&2
  exit 1
fi

raw_state="$(tofu -chdir="$tofu_directory" state pull)"
reviewed_lineage="$(jq -er '.stateLineage' "$plan_record")"
reviewed_serial="$(jq -er '.stateSerial' "$plan_record")"
current_lineage="$(jq -er '.lineage' <<<"$raw_state")"
current_serial="$(jq -er '.serial' <<<"$raw_state")"

if [[ "$current_lineage" != "$reviewed_lineage" ]] ||
  ((current_serial <= reviewed_serial)); then
  printf 'error: retained state lineage or serial is invalid\n' >&2
  exit 1
fi

if ! jq -e '(.resources // []) | length == 0' <<<"$raw_state" >/dev/null; then
  printf 'error: retained state contains managed resources\n' >&2
  exit 1
fi

instance_count="$(
  # Backticks are JMESPath literals, not shell substitutions.
  # shellcheck disable=SC2016
  aws lightsail get-instances \
    --region "$aws_region" \
    --query 'length(instances[?name == `rivet-workspace`])' \
    --output text
)"
key_pair_count="$(
  # Backticks are JMESPath literals, not shell substitutions.
  # shellcheck disable=SC2016
  aws lightsail get-key-pairs \
    --region "$aws_region" \
    --query 'length(keyPairs[?name == `rivet-operator`])' \
    --output text
)"
static_ip_count="$(
  # Backticks are JMESPath literals, not shell substitutions.
  # shellcheck disable=SC2016
  aws lightsail get-static-ips \
    --region "$aws_region" \
    --query 'length(staticIps[?name == `rivet-workspace-ip`])' \
    --output text
)"

if [[ "$instance_count" != 0 || "$key_pair_count" != 0 ||
  "$static_ip_count" != 0 ]]; then
  printf 'error: selected Lightsail resources remain after destruction\n' >&2
  exit 1
fi

temporary_directory="$(mktemp -d "${TMPDIR:-/tmp}/rivet-destroy-verify.XXXXXX")"
budget_stdout="${temporary_directory}/budget.stdout"
budget_stderr="${temporary_directory}/budget.stderr"
canary_download="${temporary_directory}/canary.json"

cleanup() {
  rm -f -- "$budget_stdout" "$budget_stderr" "$canary_download"
  rmdir "$temporary_directory" 2>/dev/null || true
}
trap cleanup EXIT

if aws budgets describe-budget \
  --account-id "$account_id" \
  --budget-name rivet-monthly-cost \
  --region "$aws_region" >"$budget_stdout" 2>"$budget_stderr"; then
  printf 'error: selected budget remains after destruction\n' >&2
  exit 1
fi

if ! grep -q 'NotFoundException' "$budget_stderr"; then
  printf 'error: selected budget absence could not be verified\n' >&2
  sed -E 's/[[:alnum:]_.%+-]+@[[:alnum:].-]+/<redacted-email>/g' \
    "$budget_stderr" >&2
  exit 1
fi

snapshot_name="$(jq -er '.name' "$snapshot_record")"
snapshot_response="$(
  aws lightsail get-instance-snapshot \
    --instance-snapshot-name "$snapshot_name" \
    --region "$aws_region"
)"

if ! jq -e \
  --arg snapshot_name "$snapshot_name" \
  '
    .instanceSnapshot as $snapshot |
    ($snapshot.tags | map({key: .key, value: .value}) | from_entries) as $tags |
    $snapshot.name == $snapshot_name and
    $snapshot.state == "available" and
    $snapshot.fromInstanceName == "rivet-workspace" and
    $snapshot.sizeInGb == 80 and
    $tags.ManagedBy == "Rivet" and
    $tags.Project == "Rivet" and
    $tags.Purpose == "RetainedBackup" and
    $tags.Workspace == "primary"
  ' <<<"$snapshot_response" >/dev/null; then
  printf 'error: retained snapshot changed during destruction\n' >&2
  exit 1
fi

canary_bucket="$(jq -er '.bucket' "$canary_record")"
canary_key="$(jq -er '.key' "$canary_record")"
canary_version="$(jq -er '.versionId' "$canary_record")"
canary_etag="$(jq -er '.eTag' "$canary_record")"
canary_sha256="$(jq -er '.sha256' "$canary_record")"

canary_head="$(
  aws s3api head-object \
    --bucket "$canary_bucket" \
    --key "$canary_key" \
    --region "$aws_region"
)"

if ! jq -e \
  --arg version_id "$canary_version" \
  --arg e_tag "$canary_etag" \
  '
    .VersionId == $version_id and
    .ETag == $e_tag and
    .ServerSideEncryption == "AES256" and
    .ContentLength > 0
  ' <<<"$canary_head" >/dev/null; then
  printf 'error: destruction canary metadata changed\n' >&2
  exit 1
fi

aws s3api get-object \
  --bucket "$canary_bucket" \
  --key "$canary_key" \
  --version-id "$canary_version" \
  --region "$aws_region" \
  "$canary_download" >/dev/null

downloaded_sha256="$(shasum -a 256 "$canary_download" | awk '{print $1}')"
if [[ "$downloaded_sha256" != "$canary_sha256" ]]; then
  printf 'error: destruction canary content changed\n' >&2
  exit 1
fi

canary_tags="$(
  aws s3api get-object-tagging \
    --bucket "$canary_bucket" \
    --key "$canary_key" \
    --version-id "$canary_version" \
    --region "$aws_region"
)"

if ! jq -e '
  (.TagSet | map({key: .Key, value: .Value}) | from_entries) as $tags |
  $tags.ManagedBy == "Rivet" and
  $tags.Project == "Rivet" and
  $tags.Purpose == "DestructionCanary" and
  ($tags | length) == 3
' <<<"$canary_tags" >/dev/null; then
  printf 'error: destruction canary tags changed\n' >&2
  exit 1
fi

bucket_versioning="$(
  aws s3api get-bucket-versioning \
    --bucket "$canary_bucket" \
    --region "$aws_region" \
    --query Status \
    --output text
)"
bucket_encryption="$(
  aws s3api get-bucket-encryption \
    --bucket "$canary_bucket" \
    --region "$aws_region" \
    --query 'ServerSideEncryptionConfiguration.Rules[0].ApplyServerSideEncryptionByDefault.SSEAlgorithm' \
    --output text
)"

if [[ "$bucket_versioning" != Enabled || "$bucket_encryption" != AES256 ]]; then
  printf 'error: retained state backend protections changed\n' >&2
  exit 1
fi

verified_at_utc="$(date -u '+%Y-%m-%dT%H:%M:%SZ')"
umask 077
jq -n \
  --arg verified_at_utc "$verified_at_utc" \
  --arg operator_role_arn "$operator_role_arn" \
  --arg state_lineage "$current_lineage" \
  --argjson state_serial "$current_serial" \
  --arg snapshot_name "$snapshot_name" \
  --arg canary_version "$canary_version" \
  '{
    verifiedAtUtc: $verified_at_utc,
    operatorRoleArn: $operator_role_arn,
    selectedResourcesAbsent: true,
    state: {
      retained: true,
      empty: true,
      lineage: $state_lineage,
      serial: $state_serial,
      versioning: "Enabled",
      encryption: "AES256"
    },
    retainedSnapshot: {
      name: $snapshot_name,
      state: "available",
      monthlyUpperBoundUsd: 4
    },
    canary: {
      versionId: $canary_version,
      metadataUnchanged: true,
      contentUnchanged: true,
      tagsUnchanged: true
    },
    continuingMonthlyCostUpperBoundUsd: 4
  }' >"$verification_record"
chmod 0600 "$verification_record"

jq '{
  selectedResourcesAbsent,
  state,
  retainedSnapshot,
  canary,
  continuingMonthlyCostUpperBoundUsd
}' "$verification_record"
