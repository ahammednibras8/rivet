#!/usr/bin/env bash

set -euo pipefail

required_variables=(
  RIVET_WORKSPACE_IP
  RIVET_RESTORE_PUBLIC_IP
  RIVET_OPERATOR_SSH_PRIVATE_KEY
  RIVET_BACKUP_MARKER
  RIVET_BACKUP_CONTEXT
  RIVET_RESTORE_INSTANCE_NAME
  RIVET_RESTORE_REQUESTED_EPOCH
)

for variable in "${required_variables[@]}"; do
  if [[ -z "${!variable:-}" ]]; then
    echo "Required environment variable is unset: ${variable}" >&2
    exit 1
  fi
done

if [[ ! "$RIVET_RESTORE_INSTANCE_NAME" =~ ^rivet-workspace-restore-drill-[0-9]{8}$ ]]; then
  echo "RIVET_RESTORE_INSTANCE_NAME has an unexpected value." >&2
  exit 1
fi

if [[ ! "$RIVET_RESTORE_REQUESTED_EPOCH" =~ ^[0-9]+$ ]]; then
  echo "RIVET_RESTORE_REQUESTED_EPOCH must be a Unix timestamp." >&2
  exit 1
fi

aws_profile="${AWS_PROFILE:-rivet-operator}"
aws_region="ap-south-1"

source_state="$(
  aws --profile "$aws_profile" lightsail get-instance-state \
    --region "$aws_region" \
    --instance-name rivet-workspace \
    --query state.name \
    --output text
)"

restore_instance="$(
  aws --profile "$aws_profile" lightsail get-instance \
    --region "$aws_region" \
    --instance-name "$RIVET_RESTORE_INSTANCE_NAME" \
    --output json
)"

if [[ "$source_state" != stopped ]]; then
  echo "The source instance must remain stopped during restore verification." >&2
  exit 1
fi

if ! jq -e \
  --arg instance "$RIVET_RESTORE_INSTANCE_NAME" '
    .instance.name == $instance and
    .instance.state.name == "running" and
    .instance.blueprintId == "ubuntu_24_04" and
    .instance.bundleId == "medium_3_1" and
    any(.instance.tags[]; .key == "Project" and .value == "Rivet") and
    any(.instance.tags[]; .key == "Purpose" and .value == "RestoreDrill")
  ' <<<"$restore_instance" >/dev/null; then
  echo "The replacement instance does not match the approved restore boundary." >&2
  exit 1
fi

port_states="$(
  aws --profile "$aws_profile" lightsail get-instance-port-states \
    --region "$aws_region" \
    --instance-name "$RIVET_RESTORE_INSTANCE_NAME" \
    --query portStates \
    --output json
)"

if ! jq -e '
  length == 1 and
  .[0].fromPort == 22 and
  .[0].toPort == 22 and
  .[0].protocol == "tcp" and
  .[0].state == "open" and
  .[0].cidrs == ["192.0.2.1/32"] and
  (.[0].ipv6Cidrs | length) == 0 and
  (.[0].cidrListAliases | length) == 0
' <<<"$port_states" >/dev/null; then
  echo "The replacement Lightsail firewall is not fail-closed." >&2
  jq . <<<"$port_states" >&2
  exit 1
fi

marker_base64="$(printf '%s' "$RIVET_BACKUP_MARKER" | base64 | tr -d '\n')"
context_base64="$(printf '%s' "$RIVET_BACKUP_CONTEXT" | base64 | tr -d '\n')"
remote_command="rivet_uid=\$(id -u rivet); sudo -u rivet env HOME=/home/rivet T3CODE_HOME=/home/rivet/.t3 PATH=/home/rivet/.local/bin:/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin XDG_RUNTIME_DIR=/run/user/\${rivet_uid} DBUS_SESSION_BUS_ADDRESS=unix:path=/run/user/\${rivet_uid}/bus bash -s -- '${marker_base64}' '${context_base64}' '${RIVET_RESTORE_REQUESTED_EPOCH}'"

ssh \
  -o "HostKeyAlias=${RIVET_RESTORE_PUBLIC_IP}" \
  -o StrictHostKeyChecking=yes \
  -i "${RIVET_OPERATOR_SSH_PRIVATE_KEY}" \
  "rivet-admin@${RIVET_WORKSPACE_IP}" \
  "$remote_command" <<'REMOTE'
set -euo pipefail

marker="$(printf '%s' "$1" | base64 --decode)"
context_word="$(printf '%s' "$2" | base64 --decode)"
restore_requested_epoch="$3"
cd "$HOME"

state_dir="${HOME}/.local/state/rivet-verification"
baseline_path="${state_dir}/issue-13-before.json"
result_path="${state_dir}/issue-13-after.json"
database="${HOME}/.t3/userdata/state.sqlite"
environment_id="${HOME}/.t3/userdata/environment-id"
repository="${HOME}/workspaces/rivet"
codex_active="${HOME}/.t3/tools/codex/active.json"
secret_dir="${HOME}/.t3/userdata/secrets"
github_config="${HOME}/.config/gh/hosts.yml"

for command in git gh jq sha256sum sqlite3 ss stat systemctl; do
  if ! command -v "$command" >/dev/null 2>&1; then
    echo "Required restored command is unavailable: ${command}" >&2
    exit 1
  fi
done

for path in \
  "$baseline_path" \
  "$database" \
  "$environment_id" \
  "$repository/.git" \
  "$codex_active" \
  "$secret_dir" \
  "$github_config"; do
  if [[ ! -r "$path" ]]; then
    echo "Required restored state is unreadable: ${path}" >&2
    exit 1
  fi
done

if ! jq -e '.schemaVersion == 1' "$baseline_path" >/dev/null; then
  echo "The restored Issue #13 baseline is invalid." >&2
  exit 1
fi

hash_stream() {
  sha256sum | awk '{print $1}'
}

hash_value() {
  printf '%s' "$1" | hash_stream
}

sqlite_integrity="$(sqlite3 "$database" 'PRAGMA integrity_check;')"
if [[ "$sqlite_integrity" != ok ]]; then
  echo "The restored T3 SQLite database failed its integrity check." >&2
  exit 1
fi

service_active="$(systemctl --user show t3code.service --property=ActiveState --value)"
service_enabled="$(systemctl --user show t3code.service --property=UnitFileState --value)"
service_main_pid="$(systemctl --user show t3code.service --property=MainPID --value)"
service_user="$(ps -o user= -p "$service_main_pid" | xargs)"

if [[ "$service_active" != active || "$service_enabled" != enabled || "$service_user" != rivet ]]; then
  echo "The restored T3 service is not active, enabled, and owned by rivet." >&2
  exit 1
fi

connect_status="$(
  "${HOME}/.local/bin/t3" connect status --json |
    jq '{
      desired,
      authenticated,
      linked,
      relayClientStatus: .relayClient.status
    }'
)"

if ! jq -e '
  .desired == true and
  .authenticated == true and
  .linked == true and
  .relayClientStatus == "available"
' <<<"$connect_status" >/dev/null; then
  echo "The restored T3 Connect environment is not ready." >&2
  jq . <<<"$connect_status" >&2
  exit 1
fi

thread_state="$(
  sqlite3 -json "$database" <<SQL
WITH marked_thread AS (
  SELECT DISTINCT thread_id
  FROM projection_thread_messages
  WHERE instr(text, '${marker}') > 0
)
SELECT
  threads.thread_id AS threadId,
  threads.project_id AS projectId,
  projects.workspace_root AS workspaceRoot,
  COALESCE(threads.branch, '') AS branch,
  threads.worktree_path AS worktreePath,
  COALESCE(runtime.runtime_mode, '') AS runtimeMode,
  COALESCE(runtime.status, '') AS runtimeStatus,
  COALESCE(runtime.provider_name, '') AS providerName,
  COUNT(messages.message_id) AS messageCount,
  MAX(CASE WHEN instr(messages.text, '${marker}') > 0 THEN 1 ELSE 0 END) AS markerPresent,
  MAX(CASE WHEN instr(messages.text, '${context_word}') > 0 THEN 1 ELSE 0 END) AS contextPresent
FROM projection_threads AS threads
INNER JOIN marked_thread
  ON marked_thread.thread_id = threads.thread_id
INNER JOIN projection_projects AS projects
  ON projects.project_id = threads.project_id
LEFT JOIN provider_session_runtime AS runtime
  ON runtime.thread_id = threads.thread_id
LEFT JOIN projection_thread_messages AS messages
  ON messages.thread_id = threads.thread_id
WHERE threads.deleted_at IS NULL
GROUP BY threads.thread_id;
SQL
)"

if ! jq -e 'length == 1' <<<"$thread_state" >/dev/null; then
  echo "The restored marker does not identify exactly one thread." >&2
  exit 1
fi

thread="$(jq '.[0]' <<<"$thread_state")"
baseline_thread="$(jq '.thread' "$baseline_path")"
baseline_message_count="$(jq -r '.thread.messageCount' "$baseline_path")"

same_thread=false
if jq -e \
  --argjson before "$baseline_thread" \
  --argjson after "$thread" '
    $after.threadId == $before.threadId and
    $after.projectId == $before.projectId and
    $after.workspaceRoot == $before.workspaceRoot and
    $after.branch == $before.branch and
    $after.worktreePath == $before.worktreePath and
    $after.providerName == $before.providerName and
    $after.runtimeMode == $before.runtimeMode and
    $after.markerPresent == 1 and
    $after.contextPresent == 1
  ' <<<"{}" >/dev/null; then
  same_thread=true
fi

context_response_recorded=false
if [[ "$(jq -r '.messageCount' <<<"$thread")" -gt "$baseline_message_count" ]]; then
  context_response_recorded=true
fi

worktrees="$(
  while IFS= read -r worktree_path; do
    worktree_clean=false
    if [[ -z "$(git -C "$worktree_path" status --porcelain)" ]]; then
      worktree_clean=true
    fi

    jq -n \
      --arg path "$worktree_path" \
      --arg head "$(git -C "$worktree_path" rev-parse HEAD)" \
      --arg branch "$(git -C "$worktree_path" symbolic-ref --quiet --short HEAD || true)" \
      --argjson clean "$worktree_clean" \
      '{path: $path, head: $head, branch: $branch, clean: $clean}'
  done < <(
    git -C "$repository" worktree list --porcelain |
      awk '/^worktree / {sub(/^worktree /, ""); print}'
  )
)"
worktrees="$(jq -s 'sort_by(.path)' <<<"$worktrees")"
baseline_worktrees="$(jq '.repository.worktrees' "$baseline_path")"

branches_digest="$(
  git -C "$repository" for-each-ref \
    --sort=refname \
    --format='%(refname)|%(objectname)' \
    refs/heads |
    hash_stream
)"

repository_preserved=false
if [[ "$(git -C "$repository" rev-parse HEAD)" == "$(jq -r '.repository.head' "$baseline_path")" &&
  "$(git -C "$repository" symbolic-ref --quiet --short HEAD)" == "$(jq -r '.repository.branch' "$baseline_path")" &&
  "$branches_digest" == "$(jq -r '.repository.branchesDigest' "$baseline_path")" ]] &&
  jq -e --argjson before "$baseline_worktrees" --argjson after "$worktrees" \
    '$after == $before and all($after[]; .clean == true)' <<<"{}" >/dev/null; then
  repository_preserved=true
fi

durable_inventory="$(
  jq -r '.durableInventory[].path' "$baseline_path" |
    while IFS= read -r path; do
      if [[ ! -d "$path" ]]; then
        echo "Restored durable root is missing: ${path}" >&2
        exit 1
      fi
      jq -n \
        --arg path "$path" \
        --arg owner "$(stat -c '%U' "$path")" \
        --arg group "$(stat -c '%G' "$path")" \
        --arg mode "$(stat -c '%a' "$path")" \
        '{path: $path, owner: $owner, group: $group, mode: $mode}'
    done
)"
durable_inventory="$(jq -s 'sort_by(.path)' <<<"$durable_inventory")"

durable_permissions_preserved=false
if jq -e \
  --argjson before "$(jq '[.durableInventory[] | {path, owner, group, mode}]' "$baseline_path")" \
  --argjson after "$durable_inventory" \
  '$after == $before and all($after[]; .owner == "rivet" and .group == "rivet")' \
  <<<"{}" >/dev/null; then
  durable_permissions_preserved=true
fi

secret_file_count="$(find "$secret_dir" -type f | wc -l | tr -d ' ')"
insecure_secret_count="$(find "$secret_dir" -type f ! -perm 0600 | wc -l | tr -d ' ')"
credentials_protected=false
if ((secret_file_count > 0 && insecure_secret_count == 0)); then
  credentials_protected=true
fi
credential_rotation_observed=false
if ((secret_file_count != $(jq -r '.integrity.secretFileCount' "$baseline_path"))); then
  credential_rotation_observed=true
fi

github_configuration_preserved=false
if [[ "$(sha256sum "$github_config" | awk '{print $1}')" == "$(jq -r '.integrity.githubConfigDigest' "$baseline_path")" ]] &&
  gh auth status --hostname github.com >/dev/null 2>&1; then
  github_configuration_preserved=true
fi

provider_configuration_preserved=false
codex_version="$(jq -er '.version' "$codex_active")"
codex_binary="${HOME}/.t3/tools/codex/${codex_version}/bin/codex"
if [[ "$(sha256sum "$codex_active" | awk '{print $1}')" == "$(jq -r '.integrity.codexActiveDigest' "$baseline_path")" &&
  -x "$codex_binary" ]] && "$codex_binary" --version >/dev/null 2>&1; then
  provider_configuration_preserved=true
fi

environment_preserved=false
if [[ "$(hash_value "$(<"$environment_id")")" == "$(jq -r '.environmentFingerprint' "$baseline_path")" ]]; then
  environment_preserved=true
fi

loopback_only=false
if ss -ltn | awk '$4 ~ /:3773$/ {print $4}' | grep -Fxq '127.0.0.1:3773' &&
  ! ss -ltn | awk '$4 ~ /:3773$/ {print $4}' | grep -Evq '^127\.0\.0\.1:3773$'; then
  loopback_only=true
fi

if [[ "$same_thread" != true ||
  "$context_response_recorded" != true ||
  "$repository_preserved" != true ||
  "$durable_permissions_preserved" != true ||
  "$credentials_protected" != true ||
  "$github_configuration_preserved" != true ||
  "$provider_configuration_preserved" != true ||
  "$environment_preserved" != true ||
  "$loopback_only" != true ]]; then
  echo "The restored workspace does not satisfy every Issue #13 invariant." >&2
  jq -n \
    --argjson sameThread "$same_thread" \
    --argjson contextResponseRecorded "$context_response_recorded" \
    --argjson repositoryPreserved "$repository_preserved" \
    --argjson durablePermissionsPreserved "$durable_permissions_preserved" \
    --argjson credentialsProtected "$credentials_protected" \
    --argjson credentialRotationObserved "$credential_rotation_observed" \
    --argjson githubConfigurationPreserved "$github_configuration_preserved" \
    --argjson providerConfigurationPreserved "$provider_configuration_preserved" \
    --argjson environmentPreserved "$environment_preserved" \
    --argjson loopbackOnly "$loopback_only" \
    '{
      sameThread: $sameThread,
      contextResponseRecorded: $contextResponseRecorded,
      repositoryPreserved: $repositoryPreserved,
      durablePermissionsPreserved: $durablePermissionsPreserved,
      credentialsProtected: $credentialsProtected,
      credentialRotationObserved: $credentialRotationObserved,
      githubConfigurationPreserved: $githubConfigurationPreserved,
      providerConfigurationPreserved: $providerConfigurationPreserved,
      environmentPreserved: $environmentPreserved,
      loopbackOnly: $loopbackOnly
    }' >&2
  exit 1
fi

install -d -m 0700 "$state_dir"
temporary_path="$(mktemp "${state_dir}/.issue-13-after.XXXXXX")"
trap 'rm -f "$temporary_path"' EXIT
chmod 0600 "$temporary_path"

jq -n \
  --arg baseline_captured_at "$(jq -r '.capturedAtUtc' "$baseline_path")" \
  --arg verified_at "$(date -u +'%Y-%m-%dT%H:%M:%SZ')" \
  --arg source_state "stopped" \
  --argjson service_recovered true \
  --argjson environment_preserved "$environment_preserved" \
  --argjson same_thread "$same_thread" \
  --argjson context_response_recorded "$context_response_recorded" \
  --argjson repository_preserved "$repository_preserved" \
  --argjson durable_permissions_preserved "$durable_permissions_preserved" \
  --argjson credentials_protected "$credentials_protected" \
  --argjson credential_rotation_observed "$credential_rotation_observed" \
  --argjson github_configuration_preserved "$github_configuration_preserved" \
  --argjson provider_configuration_preserved "$provider_configuration_preserved" \
  --argjson loopback_only "$loopback_only" \
  --arg sqlite_integrity "$sqlite_integrity" \
  --arg worktree_count "$(jq 'length' <<<"$worktrees")" \
  --arg recovery_seconds "$(( $(date +%s) - restore_requested_epoch ))" \
  '{
    schemaVersion: 1,
    baselineCapturedAtUtc: $baseline_captured_at,
    verifiedAtUtc: $verified_at,
    sourceState: $source_state,
    replacementRunning: true,
    serviceRecovered: $service_recovered,
    environmentPreserved: $environment_preserved,
    sameThread: $same_thread,
    contextResponseRecorded: $context_response_recorded,
    repositoryPreserved: $repository_preserved,
    worktreeCount: ($worktree_count | tonumber),
    durablePermissionsPreserved: $durable_permissions_preserved,
    credentialsProtected: $credentials_protected,
    credentialRotationObserved: $credential_rotation_observed,
    githubConfigurationPreserved: $github_configuration_preserved,
    providerConfigurationPreserved: $provider_configuration_preserved,
    loopbackOnly: $loopback_only,
    sqliteIntegrity: $sqlite_integrity,
    recoverySeconds: ($recovery_seconds | tonumber)
  }' >"$temporary_path"

mv "$temporary_path" "$result_path"
trap - EXIT

jq 'del(.schemaVersion)' "$result_path"
REMOTE
