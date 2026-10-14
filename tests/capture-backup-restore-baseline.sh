#!/usr/bin/env bash

set -euo pipefail

required_variables=(
  RIVET_WORKSPACE_IP
  RIVET_WORKSPACE_PUBLIC_IP
  RIVET_OPERATOR_SSH_PRIVATE_KEY
  RIVET_BACKUP_MARKER
  RIVET_BACKUP_CONTEXT
)

for variable in "${required_variables[@]}"; do
  if [[ -z "${!variable:-}" ]]; then
    echo "Required environment variable is unset: ${variable}" >&2
    exit 1
  fi
done

for variable in RIVET_BACKUP_MARKER RIVET_BACKUP_CONTEXT; do
  if [[ ! "${!variable}" =~ ^[[:alnum:]_.:-]{5,128}$ ]]; then
    echo "${variable} must contain 5-128 non-secret identifier characters." >&2
    exit 1
  fi
done

marker_base64="$(printf '%s' "$RIVET_BACKUP_MARKER" | base64 | tr -d '\n')"
context_base64="$(printf '%s' "$RIVET_BACKUP_CONTEXT" | base64 | tr -d '\n')"
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
state_dir="${HOME}/.local/state/rivet-verification"
baseline_path="${state_dir}/issue-13-before.json"
database="${HOME}/.t3/userdata/state.sqlite"
environment_id="${HOME}/.t3/userdata/environment-id"
repository="${HOME}/workspaces/rivet"
fixture_worktree="${HOME}/workspaces/rivet-issue-13-worktree"
codex_active="${HOME}/.t3/tools/codex/active.json"
secret_dir="${HOME}/.t3/userdata/secrets"
github_config="${HOME}/.config/gh/hosts.yml"

for command in du find git jq sha256sum sqlite3 stat systemctl; do
  if ! command -v "$command" >/dev/null 2>&1; then
    echo "Required cloud command is unavailable: ${command}" >&2
    exit 1
  fi
done

durable_paths=(
  "${HOME}/.t3/userdata"
  "${HOME}/.t3/worktrees"
  "${HOME}/workspaces"
  "${HOME}/.config/gh"
)

for path in \
  "$database" \
  "$environment_id" \
  "$repository/.git" \
  "$fixture_worktree/.git" \
  "$codex_active" \
  "$secret_dir" \
  "$github_config" \
  "${durable_paths[@]}"; do
  if [[ ! -r "$path" ]]; then
    echo "Required durable state is unreadable: ${path}" >&2
    exit 1
  fi
done

hash_stream() {
  sha256sum | awk '{print $1}'
}

hash_value() {
  printf '%s' "$1" | hash_stream
}

service_active="$(systemctl --user show t3code.service --property=ActiveState --value)"
service_enabled="$(systemctl --user show t3code.service --property=UnitFileState --value)"

if [[ "$service_active" != inactive || "$service_enabled" != enabled ]]; then
  echo "T3 Code must be stopped but enabled while capturing the recovery point." >&2
  printf 'ActiveState=%s UnitFileState=%s\n' "$service_active" "$service_enabled" >&2
  exit 1
fi

sqlite_check="$(sqlite3 "$database" 'PRAGMA wal_checkpoint(TRUNCATE); PRAGMA integrity_check;')"
if [[ "$sqlite_check" != $'0|0|0\nok' ]]; then
  echo "T3 SQLite state did not checkpoint cleanly." >&2
  printf '%s\n' "$sqlite_check" >&2
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
  COALESCE(threads.latest_turn_id, '') AS latestTurnId,
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
  echo "The backup marker must identify exactly one active cloud thread." >&2
  exit 1
fi

if ! jq -e '
  .[0].workspaceRoot == "/home/rivet/workspaces/rivet" and
  .[0].branch == "feature/13-backup-restoration" and
  .[0].providerName == "codex" and
  .[0].runtimeMode == "approval-required" and
  .[0].messageCount >= 2 and
  .[0].markerPresent == 1 and
  .[0].contextPresent == 1
' <<<"$thread_state" >/dev/null; then
  echo "The marked thread does not satisfy the Issue #13 baseline." >&2
  jq '.[0] | {workspaceRoot, branch, worktreePath, runtimeMode, runtimeStatus, providerName, messageCount, markerPresent, contextPresent}' \
    <<<"$thread_state" >&2
  exit 1
fi

thread="$(jq '.[0]' <<<"$thread_state")"
thread_id="$(jq -er '.threadId' <<<"$thread")"
history_digest="$(
  sqlite3 "$database" <<SQL | hash_stream
SELECT
  hex(CAST(message_id AS BLOB)) || '|' ||
  hex(CAST(role AS BLOB)) || '|' ||
  hex(CAST(text AS BLOB)) || '|' ||
  hex(CAST(created_at AS BLOB))
FROM projection_thread_messages
WHERE thread_id = '${thread_id}'
ORDER BY created_at, message_id;
SQL
)"

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

if ! jq -e '
  length == 2 and
  all(.[]; .clean == true) and
  any(.[]; .path == "/home/rivet/workspaces/rivet" and .branch == "feature/13-backup-restoration") and
  any(.[]; .path == "/home/rivet/workspaces/rivet-issue-13-worktree" and .branch == "verification/13-restore-fixture")
' <<<"$worktrees" >/dev/null; then
  echo "The two clean Issue #13 worktrees are required before backup." >&2
  jq . <<<"$worktrees" >&2
  exit 1
fi

branches_digest="$(
  git -C "$repository" for-each-ref \
    --sort=refname \
    --format='%(refname)|%(objectname)' \
    refs/heads |
    hash_stream
)"

durable_inventory="$(
  for path in "${durable_paths[@]}"; do
    jq -n \
      --arg path "$path" \
      --arg owner "$(stat -c '%U' "$path")" \
      --arg group "$(stat -c '%G' "$path")" \
      --arg mode "$(stat -c '%a' "$path")" \
      --arg bytes "$(du -sb "$path" | awk '{print $1}')" \
      --arg files "$(find "$path" -type f | wc -l | tr -d ' ')" \
      --arg directories "$(find "$path" -type d | wc -l | tr -d ' ')" \
      '{
        path: $path,
        owner: $owner,
        group: $group,
        mode: $mode,
        bytes: ($bytes | tonumber),
        files: ($files | tonumber),
        directories: ($directories | tonumber)
      }'
  done
)"
durable_inventory="$(jq -s 'sort_by(.path)' <<<"$durable_inventory")"

if ! jq -e 'length == 4 and all(.[]; .owner == "rivet" and .group == "rivet")' \
  <<<"$durable_inventory" >/dev/null; then
  echo "Durable state roots must be owned by rivet." >&2
  jq . <<<"$durable_inventory" >&2
  exit 1
fi

secret_file_count="$(find "$secret_dir" -type f | wc -l | tr -d ' ')"
insecure_secret_count="$(
  find "$secret_dir" -type f ! -perm 0600 | wc -l | tr -d ' '
)"
if ((secret_file_count < 1 || insecure_secret_count != 0)); then
  echo "Provider secrets must exist and every file must use mode 0600." >&2
  exit 1
fi

secret_store_digest="$(
  find "$secret_dir" -type f -print0 |
    sort -z |
    while IFS= read -r -d '' secret_file; do
      printf '%s|%s|%s\n' \
        "${secret_file#"$secret_dir"/}" \
        "$(stat -c '%a:%U:%G' "$secret_file")" \
        "$(sha256sum "$secret_file" | awk '{print $1}')"
    done |
    hash_stream
)"

install -d -m 0700 "$state_dir"
temporary_path="$(mktemp "${state_dir}/.issue-13-before.XXXXXX")"
trap 'rm -f "$temporary_path"' EXIT
chmod 0600 "$temporary_path"

jq -n \
  --arg captured_at_utc "$(date -u +'%Y-%m-%dT%H:%M:%SZ')" \
  --arg environment_fingerprint "$(hash_value "$(<"$environment_id")")" \
  --arg marker_fingerprint "$(hash_value "$marker")" \
  --arg context_fingerprint "$(hash_value "$context_word")" \
  --arg history_digest "$history_digest" \
  --argjson thread "$thread" \
  --arg repository_head "$(git -C "$repository" rev-parse HEAD)" \
  --arg repository_branch "$(git -C "$repository" symbolic-ref --quiet --short HEAD)" \
  --arg branches_digest "$branches_digest" \
  --argjson worktrees "$worktrees" \
  --argjson durable_inventory "$durable_inventory" \
  --arg sqlite_digest "$(sha256sum "$database" | awk '{print $1}')" \
  --arg codex_active_digest "$(sha256sum "$codex_active" | awk '{print $1}')" \
  --arg secret_store_digest "$secret_store_digest" \
  --arg github_config_digest "$(sha256sum "$github_config" | awk '{print $1}')" \
  --arg secret_file_count "$secret_file_count" \
  '{
    schemaVersion: 1,
    capturedAtUtc: $captured_at_utc,
    service: {
      activeState: "inactive",
      unitFileState: "enabled",
      sqliteIntegrity: "ok"
    },
    environmentFingerprint: $environment_fingerprint,
    markerFingerprint: $marker_fingerprint,
    contextFingerprint: $context_fingerprint,
    historyDigest: $history_digest,
    thread: $thread,
    repository: {
      path: "/home/rivet/workspaces/rivet",
      head: $repository_head,
      branch: $repository_branch,
      branchesDigest: $branches_digest,
      worktrees: $worktrees
    },
    durableInventory: $durable_inventory,
    integrity: {
      sqliteDigest: $sqlite_digest,
      codexActiveDigest: $codex_active_digest,
      secretStoreDigest: $secret_store_digest,
      githubConfigDigest: $github_config_digest,
      secretFileCount: ($secret_file_count | tonumber)
    }
  }' >"$temporary_path"

mv "$temporary_path" "$baseline_path"
trap - EXIT

jq '{
  capturedAtUtc,
  service,
  environmentIdentityRecorded: (.environmentFingerprint | length == 64),
  markerRecorded: (.markerFingerprint | length == 64),
  contextRecorded: (.contextFingerprint | length == 64),
  thread: {
    identityRecorded: (.thread.threadId | length > 0),
    projectIdentityRecorded: (.thread.projectId | length > 0),
    branch: .thread.branch,
    messageCount: .thread.messageCount,
    runtimeMode: .thread.runtimeMode,
    provider: .thread.providerName
  },
  repository: {
    head: .repository.head,
    branch: .repository.branch,
    worktreeCount: (.repository.worktrees | length),
    allWorktreesClean: all(.repository.worktrees[]; .clean == true)
  },
  durableState: [
    .durableInventory[] |
    {
      path,
      owner,
      group,
      mode,
      bytes,
      files,
      directories
    }
  ],
  integrity: {
    sqlite: .service.sqliteIntegrity,
    fingerprintsRecorded: ([
      .integrity.sqliteDigest,
      .integrity.codexActiveDigest,
      .integrity.secretStoreDigest,
      .integrity.githubConfigDigest
    ] | all(length == 64)),
    secretFileCount: .integrity.secretFileCount
  }
}' "$baseline_path"
REMOTE
