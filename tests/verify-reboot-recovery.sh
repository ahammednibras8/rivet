#!/usr/bin/env bash

set -euo pipefail

required_variables=(
  RIVET_WORKSPACE_IP
  RIVET_WORKSPACE_PUBLIC_IP
  RIVET_OPERATOR_SSH_PRIVATE_KEY
  RIVET_REBOOT_MARKER
  RIVET_REBOOT_CONTEXT
)

for variable in "${required_variables[@]}"; do
  if [[ -z "${!variable:-}" ]]; then
    echo "Required environment variable is unset: ${variable}" >&2
    exit 1
  fi
done

for variable in RIVET_REBOOT_MARKER RIVET_REBOOT_CONTEXT; do
  if [[ ! "${!variable}" =~ ^[[:alnum:]_.:-]{5,128}$ ]]; then
    echo "${variable} must contain 5-128 non-secret identifier characters." >&2
    exit 1
  fi
done

marker_base64="$(printf '%s' "$RIVET_REBOOT_MARKER" | base64 | tr -d '\n')"
context_base64="$(printf '%s' "$RIVET_REBOOT_CONTEXT" | base64 | tr -d '\n')"
remote_command="rivet_uid=\$(id -u rivet); sudo -u rivet env HOME=/home/rivet T3CODE_HOME=/home/rivet/.t3 PATH=/home/rivet/.local/bin:/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin XDG_RUNTIME_DIR=/run/user/\${rivet_uid} DBUS_SESSION_BUS_ADDRESS=unix:path=/run/user/\${rivet_uid}/bus bash -s -- '${marker_base64}' '${context_base64}'"

ssh \
  -o "HostKeyAlias=${RIVET_WORKSPACE_PUBLIC_IP}" \
  -o StrictHostKeyChecking=yes \
  -i "${RIVET_OPERATOR_SSH_PRIVATE_KEY}" \
  "rivet-admin@${RIVET_WORKSPACE_IP}" \
  "$remote_command" <<'REMOTE'
set -euo pipefail

marker="$(printf '%s' "$1" | base64 --decode)"
context_word="$(printf '%s' "$2" | base64 --decode)"
cd "$HOME"

state_dir="${HOME}/.local/state/rivet-verification"
baseline_path="${state_dir}/issue-10-before.json"
after_path="${state_dir}/issue-10-after.json"
reboot_requested_path="${state_dir}/issue-10-reboot-requested-epoch"
inflight_completed_path="${state_dir}/issue-10-inflight-completed"
database="${HOME}/.t3/userdata/state.sqlite"
environment_id="${HOME}/.t3/userdata/environment-id"
repository="${HOME}/workspaces/rivet"
codex_active="${HOME}/.t3/tools/codex/active.json"
secret_dir="${HOME}/.t3/userdata/secrets"
github_config="${HOME}/.config/gh/hosts.yml"

for command in date gh git jq journalctl sha256sum sqlite3 systemctl; do
  if ! command -v "$command" >/dev/null 2>&1; then
    echo "Required cloud command is unavailable: ${command}" >&2
    exit 1
  fi
done

for path in \
  "$baseline_path" \
  "$reboot_requested_path" \
  /etc/machine-id \
  /proc/sys/kernel/random/boot_id \
  "$database" \
  "$environment_id" \
  "$repository/.git" \
  "$codex_active" \
  "$secret_dir" \
  "$github_config"; do
  if [[ ! -r "$path" ]]; then
    echo "Required recovery state is unreadable: ${path}" >&2
    exit 1
  fi
done

if [[ "$(stat -c '%a:%U:%G' "$baseline_path")" != "600:rivet:rivet" ]]; then
  echo "The protected Issue #10 baseline has invalid permissions." >&2
  exit 1
fi

hash_stream() {
  sha256sum | awk '{print $1}'
}

hash_value() {
  printf '%s' "$1" | hash_stream
}

baseline_message_count="$(jq -er '.thread.messageCount' "$baseline_path")"
baseline_thread_id="$(jq -er '.thread.threadId' "$baseline_path")"

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
  COALESCE(threads.latest_turn_id, '') AS latestTurnId,
  threads.updated_at AS updatedAt,
  COALESCE(runtime.runtime_mode, '') AS runtimeMode,
  COALESCE(runtime.status, '') AS runtimeStatus,
  COALESCE(runtime.provider_name, '') AS providerName,
  COUNT(messages.message_id) AS messageCount,
  MAX(CASE WHEN instr(messages.text, '${marker}') > 0 THEN 1 ELSE 0 END) AS markerPresent,
  MAX(CASE WHEN instr(messages.text, '${context_word}') > 0 THEN 1 ELSE 0 END) AS contextPresent,
  MAX(CASE WHEN messages.role = 'assistant' AND trim(messages.text) = '${context_word}' THEN 1 ELSE 0 END) AS contextResponsePresent,
  MAX(CASE WHEN messages.role = 'assistant' AND trim(messages.text) = '${context_word}' THEN CAST(strftime('%s', messages.created_at) AS INTEGER) ELSE 0 END) AS contextResponseEpoch
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
  echo "The reboot marker does not identify exactly one recovered thread." >&2
  exit 1
fi

thread="$(jq '.[0]' <<<"$thread_state")"
if [[ "$(jq -er '.threadId' <<<"$thread")" != "$baseline_thread_id" ]]; then
  echo "The phone reopened a different thread after reboot." >&2
  exit 1
fi

history_prefix_digest="$({
  sqlite3 "$database" <<SQL
SELECT
  hex(CAST(message_id AS BLOB)) || '|' ||
  hex(CAST(role AS BLOB)) || '|' ||
  hex(CAST(text AS BLOB)) || '|' ||
  hex(CAST(created_at AS BLOB))
FROM projection_thread_messages
WHERE thread_id = '${baseline_thread_id}'
ORDER BY created_at, message_id
LIMIT ${baseline_message_count};
SQL
} | hash_stream)"

service_active="$(systemctl --user show t3code.service --property=ActiveState --value)"
service_enabled="$(systemctl --user show t3code.service --property=UnitFileState --value)"
service_main_pid="$(systemctl --user show t3code.service --property=MainPID --value)"
service_started_monotonic="$(
  systemctl --user show t3code.service --property=ExecMainStartTimestampMonotonic --value
)"
service_active_timestamp="$(
  systemctl --user show t3code.service --property=ActiveEnterTimestamp --value
)"
service_active_epoch="$(date -d "$service_active_timestamp" +%s)"
service_restart_count="$(systemctl --user show t3code.service --property=NRestarts --value)"
service_user="$(ps -o user= -p "$service_main_pid" | xargs)"

connect_status="$(
  "${HOME}/.local/bin/t3" connect status --json |
    jq '{
      desired,
      authenticated,
      linked,
      relayClientStatus: .relayClient.status
    }'
)"

repository_clean=false
if [[ -z "$(git -C "$repository" status --porcelain)" ]]; then
  repository_clean=true
fi

branches_digest="$({
  git -C "$repository" for-each-ref \
    --sort=refname \
    --format='%(refname)|%(objectname)' \
    refs/heads
} | hash_stream)"

worktrees="$({
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
} | jq -s 'sort_by(.path)')"

secret_store_digest="$({
  find "$secret_dir" -type f -print0 |
    sort -z |
    while IFS= read -r -d '' secret_file; do
      printf '%s|%s|%s\n' \
        "${secret_file#"$secret_dir"/}" \
        "$(stat -c '%a:%U:%G' "$secret_file")" \
        "$(sha256sum "$secret_file" | awk '{print $1}')"
    done
} | hash_stream)"

secret_file_count=0
secret_permissions_valid=true
while IFS= read -r -d '' secret_file; do
  secret_file_count=$((secret_file_count + 1))
  if [[ "$(stat -c '%a:%U:%G' "$secret_file")" != "600:rivet:rivet" ]]; then
    secret_permissions_valid=false
  fi
done < <(find "$secret_dir" -type f -print0)

github_authenticated=false
if gh auth status --hostname github.com >/dev/null 2>&1; then
  github_authenticated=true
fi

settings_tables="$(
  sqlite3 "$database" \
    "SELECT name FROM sqlite_schema WHERE type = 'table' AND lower(name) LIKE '%setting%' ORDER BY name;"
)"
settings_digest="$({
  while IFS= read -r settings_table; do
    [[ -n "$settings_table" ]] || continue
    printf 'table:%s\n' "$settings_table"
    sqlite3 "$database" ".dump ${settings_table}"
  done <<<"$settings_tables"
} | hash_stream)"

reboot_requested_epoch="$(<"$reboot_requested_path")"
boot_epoch="$(awk '$1 == "btime" {print $2}' /proc/stat)"
context_response_epoch="$(jq -er '.contextResponseEpoch' <<<"$thread")"

for timestamp in "$reboot_requested_epoch" "$boot_epoch" "$service_active_epoch" "$context_response_epoch"; do
  if [[ ! "$timestamp" =~ ^[1-9][0-9]*$ ]]; then
    echo "Recovery timestamp is invalid: ${timestamp}" >&2
    exit 1
  fi
done

inflight_completed=false
if [[ -e "$inflight_completed_path" ]]; then
  inflight_completed=true
fi

current_boot_errors="$(
  journalctl --user -u t3code.service -b --no-pager -p err 2>/dev/null |
    grep -cve '^-- No entries --$' || true
)"

temporary_path="$(mktemp "${state_dir}/.issue-10-after.XXXXXX")"
trap 'rm -f "$temporary_path"' EXIT
chmod 0600 "$temporary_path"

jq -n \
  --arg captured_at_utc "$(date -u +'%Y-%m-%dT%H:%M:%SZ')" \
  --arg machine_fingerprint "$(hash_value "$(</etc/machine-id)")" \
  --arg boot_fingerprint "$(hash_value "$(</proc/sys/kernel/random/boot_id)")" \
  --arg boot_epoch "$boot_epoch" \
  --arg uptime_seconds "$(awk '{print $1}' /proc/uptime)" \
  --arg service_active "$service_active" \
  --arg service_enabled "$service_enabled" \
  --arg service_main_pid "$service_main_pid" \
  --arg service_started_monotonic "$service_started_monotonic" \
  --arg service_user "$service_user" \
  --arg service_restart_count "$service_restart_count" \
  --arg current_boot_errors "$current_boot_errors" \
  --arg environment_fingerprint "$(hash_value "$(<"$environment_id")")" \
  --argjson connect "$connect_status" \
  --arg history_prefix_digest "$history_prefix_digest" \
  --argjson thread "$thread" \
  --arg repository_head "$(git -C "$repository" rev-parse HEAD)" \
  --arg repository_branch "$(git -C "$repository" symbolic-ref --short HEAD)" \
  --argjson repository_clean "$repository_clean" \
  --arg branches_digest "$branches_digest" \
  --argjson worktrees "$worktrees" \
  --arg codex_active_digest "$(sha256sum "$codex_active" | awk '{print $1}')" \
  --arg secret_store_digest "$secret_store_digest" \
  --arg github_config_digest "$(sha256sum "$github_config" | awk '{print $1}')" \
  --arg settings_digest "$settings_digest" \
  --arg secret_file_count "$secret_file_count" \
  --argjson secret_permissions_valid "$secret_permissions_valid" \
  --argjson github_authenticated "$github_authenticated" \
  --arg reboot_requested_epoch "$reboot_requested_epoch" \
  --arg service_active_epoch "$service_active_epoch" \
  --arg context_response_epoch "$context_response_epoch" \
  --argjson inflight_completed "$inflight_completed" \
  '{
    schemaVersion: 1,
    capturedAtUtc: $captured_at_utc,
    host: {
      machineFingerprint: $machine_fingerprint,
      bootFingerprint: $boot_fingerprint,
      bootEpoch: ($boot_epoch | tonumber),
      uptimeSeconds: ($uptime_seconds | tonumber)
    },
    service: {
      activeState: $service_active,
      unitFileState: $service_enabled,
      mainPid: ($service_main_pid | tonumber),
      startedMonotonic: $service_started_monotonic,
      user: $service_user,
      restartCount: ($service_restart_count | tonumber),
      currentBootErrors: ($current_boot_errors | tonumber)
    },
    environment: ({fingerprint: $environment_fingerprint} + $connect),
    historyPrefixDigest: $history_prefix_digest,
    thread: $thread,
    repository: {
      path: "/home/rivet/workspaces/rivet",
      head: $repository_head,
      branch: $repository_branch,
      clean: $repository_clean,
      branchesDigest: $branches_digest,
      worktrees: $worktrees
    },
    persistentConfiguration: {
      codexActiveDigest: $codex_active_digest,
      secretStoreDigest: $secret_store_digest,
      githubConfigDigest: $github_config_digest,
      settingsDigest: $settings_digest
    },
    credentialHealth: {
      secretFileCount: ($secret_file_count | tonumber),
      secretPermissionsValid: $secret_permissions_valid,
      githubAuthenticated: $github_authenticated
    },
    inFlightProcessCompleted: $inflight_completed,
    recovery: {
      rebootRequestedEpoch: ($reboot_requested_epoch | tonumber),
      hostSeconds: (($boot_epoch | tonumber) - ($reboot_requested_epoch | tonumber)),
      serviceSeconds: (($service_active_epoch | tonumber) - ($reboot_requested_epoch | tonumber)),
      mobileThreadSeconds: (($context_response_epoch | tonumber) - ($reboot_requested_epoch | tonumber))
    }
  }' >"$temporary_path"

mv "$temporary_path" "$after_path"
trap - EXIT

comparison="$(
  jq -n \
    --slurpfile before "$baseline_path" \
    --slurpfile after "$after_path" '
      ($before[0]) as $before |
      ($after[0]) as $after |
      {
        baselineCapturedAtUtc: $before.capturedAtUtc,
        afterCapturedAtUtc: $after.capturedAtUtc,
        sameHost: ($after.host.machineFingerprint == $before.host.machineFingerprint),
        rebootOccurred: (
          $after.host.bootFingerprint != $before.host.bootFingerprint and
          $after.host.bootEpoch > $before.host.bootEpoch and
          $after.host.uptimeSeconds < $before.host.uptimeSeconds
        ),
        serviceRecovered: (
          $after.service.activeState == "active" and
          $after.service.unitFileState == "enabled" and
          $after.service.mainPid > 0 and
          $after.service.user == "rivet"
        ),
        serviceProcessRecreated: (
          $after.service.startedMonotonic != $before.service.startedMonotonic
        ),
        restartLoopFree: ($after.service.restartCount <= 1),
        currentBootServiceErrors: $after.service.currentBootErrors,
        sameEnvironment: ($after.environment.fingerprint == $before.environment.fingerprint),
        environmentReady: (
          $after.environment.desired == true and
          $after.environment.authenticated == true and
          $after.environment.linked == true and
          $after.environment.relayClientStatus == "available"
        ),
        sameThread: (
          $after.thread.threadId == $before.thread.threadId and
          $after.thread.projectId == $before.thread.projectId and
          $after.thread.workspaceRoot == $before.thread.workspaceRoot and
          $after.thread.worktreePath == $before.thread.worktreePath
        ),
        threadBranchReconciled: (
          $after.thread.branch == $after.repository.branch
        ),
        historyPreserved: ($after.historyPrefixDigest == $before.historyDigest),
        contextResponseRecorded: (
          $after.thread.messageCount > $before.thread.messageCount and
          $after.thread.contextResponsePresent == 1
        ),
        providerRuntimeRecovered: (
          $after.thread.providerName == "codex" and
          $after.thread.runtimeMode == "approval-required"
        ),
        repositoryPreserved: (
          $after.repository.path == $before.repository.path and
          $after.repository.head == $before.repository.head and
          $after.repository.branch == $before.repository.branch and
          $after.repository.branchesDigest == $before.repository.branchesDigest and
          $after.repository.worktrees == $before.repository.worktrees and
          $after.repository.clean == true
        ),
        settingsPreserved: (
          $after.persistentConfiguration.settingsDigest == $before.persistentConfiguration.settingsDigest
        ),
        providerConfigurationPreserved: (
          $after.persistentConfiguration.codexActiveDigest == $before.persistentConfiguration.codexActiveDigest
        ),
        credentialsAvailable: (
          $after.persistentConfiguration.githubConfigDigest == $before.persistentConfiguration.githubConfigDigest and
          $after.credentialHealth.secretFileCount > 0 and
          $after.credentialHealth.secretPermissionsValid == true and
          $after.credentialHealth.githubAuthenticated == true and
          $after.environment.authenticated == true and
          $after.thread.contextResponsePresent == 1
        ),
        credentialRotationObserved: (
          $after.persistentConfiguration.secretStoreDigest != $before.persistentConfiguration.secretStoreDigest
        ),
        inFlightProcessInterrupted: ($after.inFlightProcessCompleted == false),
        recoverySeconds: $after.recovery
      }
    '
)"

if ! jq -e '
  .sameHost == true and
  .rebootOccurred == true and
  .serviceRecovered == true and
  .serviceProcessRecreated == true and
  .restartLoopFree == true and
  .currentBootServiceErrors == 0 and
  .sameEnvironment == true and
  .environmentReady == true and
  .sameThread == true and
  .threadBranchReconciled == true and
  .historyPreserved == true and
  .contextResponseRecorded == true and
  .providerRuntimeRecovered == true and
  .repositoryPreserved == true and
  .settingsPreserved == true and
  .providerConfigurationPreserved == true and
  .credentialsAvailable == true and
  .inFlightProcessInterrupted == true and
  .recoverySeconds.hostSeconds >= 0 and
  .recoverySeconds.serviceSeconds >= 0 and
  .recoverySeconds.mobileThreadSeconds >= 0
' <<<"$comparison" >/dev/null; then
  echo "Reboot recovery verification failed:" >&2
  jq . <<<"$comparison" >&2
  exit 1
fi

jq . <<<"$comparison"
REMOTE
