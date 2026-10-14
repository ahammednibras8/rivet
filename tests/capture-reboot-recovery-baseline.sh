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
database="${HOME}/.t3/userdata/state.sqlite"
environment_id="${HOME}/.t3/userdata/environment-id"
repository="${HOME}/workspaces/rivet"
codex_active="${HOME}/.t3/tools/codex/active.json"
secret_dir="${HOME}/.t3/userdata/secrets"
github_config="${HOME}/.config/gh/hosts.yml"

for command in git jq sha256sum sqlite3 systemctl; do
  if ! command -v "$command" >/dev/null 2>&1; then
    echo "Required cloud command is unavailable: ${command}" >&2
    exit 1
  fi
done

for path in \
  /etc/machine-id \
  /proc/sys/kernel/random/boot_id \
  "$database" \
  "$environment_id" \
  "$repository/.git" \
  "$codex_active" \
  "$secret_dir" \
  "$github_config"; do
  if [[ ! -r "$path" ]]; then
    echo "Required persistent state is unreadable: ${path}" >&2
    exit 1
  fi
done

hash_stream() {
  sha256sum | awk '{print $1}'
}

hash_value() {
  printf '%s' "$1" | hash_stream
}

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
  echo "The reboot marker must identify exactly one active cloud thread." >&2
  exit 1
fi

if ! jq -e '
  .[0].workspaceRoot == "/home/rivet/workspaces/rivet" and
  .[0].branch != "" and
  .[0].branch != "main" and
  .[0].providerName == "codex" and
  .[0].runtimeMode == "approval-required" and
  .[0].messageCount >= 2 and
  .[0].markerPresent == 1 and
  .[0].contextPresent == 1
' <<<"$thread_state" >/dev/null; then
  echo "The marked thread does not satisfy the Issue #10 baseline." >&2
  jq '.[0] | {workspaceRoot, branch, worktreePath, runtimeMode, runtimeStatus, providerName, messageCount, markerPresent, contextPresent}' \
    <<<"$thread_state" >&2
  exit 1
fi

thread="$(jq '.[0]' <<<"$thread_state")"
thread_id="$(jq -er '.threadId' <<<"$thread")"

history_digest="$({
  sqlite3 "$database" <<SQL
SELECT
  hex(CAST(message_id AS BLOB)) || '|' ||
  hex(CAST(role AS BLOB)) || '|' ||
  hex(CAST(text AS BLOB)) || '|' ||
  hex(CAST(created_at AS BLOB))
FROM projection_thread_messages
WHERE thread_id = '${thread_id}'
ORDER BY created_at, message_id;
SQL
} | hash_stream)"

service_active="$(systemctl --user show t3code.service --property=ActiveState --value)"
service_enabled="$(systemctl --user show t3code.service --property=UnitFileState --value)"
service_main_pid="$(systemctl --user show t3code.service --property=MainPID --value)"
service_started_monotonic="$(
  systemctl --user show t3code.service --property=ExecMainStartTimestampMonotonic --value
)"
service_user="$(ps -o user= -p "$service_main_pid" | xargs)"

if [[ "$service_active" != active || "$service_enabled" != enabled || "$service_user" != rivet ]]; then
  echo "T3 Code must be active, enabled, and running as rivet before reboot." >&2
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
  echo "T3 Connect is not ready for reboot verification." >&2
  exit 1
fi

repository_clean=false
if [[ -z "$(git -C "$repository" status --porcelain)" ]]; then
  repository_clean=true
fi

repository_branch="$(git -C "$repository" symbolic-ref --quiet --short HEAD || true)"
if [[ "$repository_branch" != "verification/10-reboot-recovery" ]]; then
  echo "The cloud checkout is not on the Issue #10 verification branch." >&2
  printf 'Actual branch: %s\n' "$repository_branch" >&2
  exit 1
fi

if [[ "$repository_clean" != true ]]; then
  echo "The approved cloud checkout must be clean before reboot." >&2
  git -C "$repository" status --short >&2
  exit 1
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

if ! jq -e 'length >= 1 and all(.[]; .clean == true)' <<<"$worktrees" >/dev/null; then
  echo "Every registered worktree must be clean before reboot." >&2
  jq . <<<"$worktrees" >&2
  exit 1
fi

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
settings_table_count="$(grep -cve '^$' <<<"$settings_tables" || true)"

install -d -m 0700 "$state_dir"
temporary_path="$(mktemp "${state_dir}/.issue-10-before.XXXXXX")"
trap 'rm -f "$temporary_path"' EXIT
chmod 0600 "$temporary_path"

jq -n \
  --arg captured_at_utc "$(date -u +'%Y-%m-%dT%H:%M:%SZ')" \
  --arg machine_fingerprint "$(hash_value "$(</etc/machine-id)")" \
  --arg boot_fingerprint "$(hash_value "$(</proc/sys/kernel/random/boot_id)")" \
  --arg boot_epoch "$(awk '$1 == "btime" {print $2}' /proc/stat)" \
  --arg uptime_seconds "$(awk '{print $1}' /proc/uptime)" \
  --arg service_active "$service_active" \
  --arg service_enabled "$service_enabled" \
  --arg service_main_pid "$service_main_pid" \
  --arg service_started_monotonic "$service_started_monotonic" \
  --arg service_user "$service_user" \
  --arg environment_fingerprint "$(hash_value "$(<"$environment_id")")" \
  --argjson connect "$connect_status" \
  --arg marker_fingerprint "$(hash_value "$marker")" \
  --arg context_fingerprint "$(hash_value "$context_word")" \
  --arg history_digest "$history_digest" \
  --argjson thread "$thread" \
  --arg repository_head "$(git -C "$repository" rev-parse HEAD)" \
  --arg repository_branch "$repository_branch" \
  --argjson repository_clean "$repository_clean" \
  --arg branches_digest "$branches_digest" \
  --argjson worktrees "$worktrees" \
  --arg codex_active_digest "$(sha256sum "$codex_active" | awk '{print $1}')" \
  --arg secret_store_digest "$secret_store_digest" \
  --arg github_config_digest "$(sha256sum "$github_config" | awk '{print $1}')" \
  --arg settings_digest "$settings_digest" \
  --arg settings_table_count "$settings_table_count" \
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
      user: $service_user
    },
    environment: ({fingerprint: $environment_fingerprint} + $connect),
    markerFingerprint: $marker_fingerprint,
    contextFingerprint: $context_fingerprint,
    historyDigest: $history_digest,
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
      settingsDigest: $settings_digest,
      settingsTableCount: ($settings_table_count | tonumber)
    }
  }' >"$temporary_path"

mv "$temporary_path" "$baseline_path"
trap - EXIT

jq '{
  capturedAtUtc,
  host: {
    identityRecorded: (.host.machineFingerprint | length == 64),
    bootRecorded: (.host.bootFingerprint | length == 64),
    uptimeSeconds: .host.uptimeSeconds
  },
  service: {
    activeState: .service.activeState,
    unitFileState: .service.unitFileState,
    processRecorded: (.service.mainPid > 0),
    user: .service.user
  },
  environment: {
    identityRecorded: (.environment.fingerprint | length == 64),
    desired: .environment.desired,
    authenticated: .environment.authenticated,
    linked: .environment.linked,
    relayClientStatus: .environment.relayClientStatus
  },
  thread: {
    identityRecorded: (.thread.threadId | length > 0),
    projectIdentityRecorded: (.thread.projectId | length > 0),
    markerRecorded: (.markerFingerprint | length == 64),
    contextRecorded: (.contextFingerprint | length == 64),
    branch: .thread.branch,
    hasWorktree: (.thread.worktreePath != null),
    runtimeMode: .thread.runtimeMode,
    runtimeStatus: .thread.runtimeStatus,
    provider: .thread.providerName
  },
  repository: {
    head: .repository.head,
    branch: .repository.branch,
    clean: .repository.clean,
    worktreeCount: (.repository.worktrees | length)
  },
  persistentConfiguration: {
    providerRecorded: (.persistentConfiguration.codexActiveDigest | length == 64),
    credentialsRecorded: (.persistentConfiguration.secretStoreDigest | length == 64),
    githubRecorded: (.persistentConfiguration.githubConfigDigest | length == 64),
    settingsRecorded: (.persistentConfiguration.settingsDigest | length == 64),
    settingsTableCount: .persistentConfiguration.settingsTableCount
  }
}' "$baseline_path"
REMOTE
