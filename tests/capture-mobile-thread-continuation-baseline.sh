#!/usr/bin/env bash

set -euo pipefail

required_variables=(
  RIVET_WORKSPACE_IP
  RIVET_WORKSPACE_PUBLIC_IP
  RIVET_OPERATOR_SSH_PRIVATE_KEY
  RIVET_CONTINUITY_MARKER
  RIVET_CONTINUITY_CONTEXT
)

for variable in "${required_variables[@]}"; do
  if [[ -z "${!variable:-}" ]]; then
    echo "Required environment variable is unset: ${variable}" >&2
    exit 1
  fi
done

for variable in RIVET_CONTINUITY_MARKER RIVET_CONTINUITY_CONTEXT; do
  if [[ ! "${!variable}" =~ ^[[:alnum:]_.:-]{12,128}$ ]]; then
    echo "${variable} must contain 12-128 non-secret identifier characters." >&2
    exit 1
  fi
done

marker_base64="$(printf '%s' "$RIVET_CONTINUITY_MARKER" | base64 | tr -d '\n')"
context_base64="$(printf '%s' "$RIVET_CONTINUITY_CONTEXT" | base64 | tr -d '\n')"
remote_command="sudo -u rivet env HOME=/home/rivet PATH=/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin bash -s -- '${marker_base64}' '${context_base64}'"

ssh \
  -o "HostKeyAlias=${RIVET_WORKSPACE_PUBLIC_IP}" \
  -o StrictHostKeyChecking=yes \
  -i "${RIVET_OPERATOR_SSH_PRIVATE_KEY}" \
  "rivet-admin@${RIVET_WORKSPACE_IP}" \
  "$remote_command" <<'REMOTE'
set -euo pipefail

marker="$(printf '%s' "$1" | base64 --decode)"
context_phrase="$(printf '%s' "$2" | base64 --decode)"
state_dir="${HOME}/.local/state/rivet-verification"
baseline_path="${state_dir}/issue-8-before.json"
database="${HOME}/.t3/userdata/state.sqlite"
repository="${HOME}/workspaces/rivet"

for command in git jq sha256sum sqlite3; do
  if ! command -v "$command" >/dev/null 2>&1; then
    echo "Required cloud command is unavailable: ${command}" >&2
    exit 1
  fi
done

for path in "$database" "$repository/.git"; do
  if [[ ! -e "$path" ]]; then
    echo "Required cloud state is unavailable: ${path}" >&2
    exit 1
  fi
done

hash_value() {
  printf '%s' "$1" | sha256sum | awk '{print $1}'
}

thread_state="$(
  sqlite3 -json "$database" <<SQL
WITH marker_threads AS (
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
  SUM(CASE WHEN messages.role = 'user' THEN 1 ELSE 0 END) AS userMessageCount,
  SUM(CASE WHEN messages.role = 'assistant' THEN 1 ELSE 0 END) AS assistantMessageCount,
  MAX(messages.created_at) AS lastMessageCreatedAt,
  MAX(CASE WHEN instr(messages.text, '${marker}') > 0 THEN 1 ELSE 0 END) AS markerPresent,
  MAX(CASE WHEN instr(messages.text, '${context_phrase}') > 0 THEN 1 ELSE 0 END) AS contextPresent
FROM projection_threads AS threads
INNER JOIN marker_threads
  ON marker_threads.thread_id = threads.thread_id
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
  echo "The continuity marker must identify exactly one active cloud thread." >&2
  exit 1
fi

if ! jq -e '
  .[0].workspaceRoot == "/home/rivet/workspaces/rivet" and
  .[0].worktreePath == null and
  .[0].runtimeMode == "approval-required" and
  .[0].providerName == "codex" and
  .[0].messageCount >= 2 and
  .[0].userMessageCount >= 1 and
  .[0].assistantMessageCount >= 1 and
  .[0].markerPresent == 1 and
  .[0].contextPresent == 1
' <<<"$thread_state" >/dev/null; then
  echo "The marked thread does not satisfy the continuation baseline." >&2
  exit 1
fi

history_digest="$({
  sqlite3 "$database" <<SQL
SELECT
  hex(CAST(messages.message_id AS BLOB)) || '|' ||
  hex(CAST(messages.role AS BLOB)) || '|' ||
  hex(CAST(messages.text AS BLOB)) || '|' ||
  hex(CAST(messages.created_at AS BLOB))
FROM projection_thread_messages AS messages
WHERE messages.thread_id = (
  SELECT DISTINCT thread_id
  FROM projection_thread_messages
  WHERE instr(text, '${marker}') > 0
)
ORDER BY messages.created_at, messages.message_id;
SQL
} | sha256sum | awk '{print $1}')"

repository_clean=false
if [[ -z "$(git -C "$repository" status --porcelain)" ]]; then
  repository_clean=true
fi

install -d -m 0700 "$state_dir"
temporary_path="$(mktemp "${state_dir}/.issue-8-before.XXXXXX")"
trap 'rm -f "$temporary_path"' EXIT
chmod 0600 "$temporary_path"

jq -n \
  --arg captured_at_utc "$(date -u +'%Y-%m-%dT%H:%M:%SZ')" \
  --arg marker_fingerprint "$(hash_value "$marker")" \
  --arg context_fingerprint "$(hash_value "$context_phrase")" \
  --arg history_digest "$history_digest" \
  --argjson thread "$(jq '.[0]' <<<"$thread_state")" \
  --arg repository_head "$(git -C "$repository" rev-parse HEAD)" \
  --arg repository_branch "$(git -C "$repository" symbolic-ref --short HEAD)" \
  --argjson repository_clean "$repository_clean" \
  '{
    schemaVersion: 1,
    capturedAtUtc: $captured_at_utc,
    markerFingerprint: $marker_fingerprint,
    contextFingerprint: $context_fingerprint,
    historyDigest: $history_digest,
    thread: $thread,
    repository: {
      path: "/home/rivet/workspaces/rivet",
      head: $repository_head,
      branch: $repository_branch,
      clean: $repository_clean
    }
  }' >"$temporary_path"

mv "$temporary_path" "$baseline_path"
trap - EXIT

jq '{
  capturedAtUtc,
  marker: {
    uniqueThread: true,
    markerRecorded: (.markerFingerprint | length == 64),
    contextRecorded: (.contextFingerprint | length == 64)
  },
  thread: {
    identityRecorded: (.thread.threadId | length > 0),
    projectIdentityRecorded: (.thread.projectId | length > 0),
    latestTurnRecorded: (.thread.latestTurnId | length > 0),
    historyDigestRecorded: (.historyDigest | length == 64),
    messageCount: .thread.messageCount,
    userMessageCount: .thread.userMessageCount,
    assistantMessageCount: .thread.assistantMessageCount,
    branch: .thread.branch,
    hasWorktree: (.thread.worktreePath != null),
    runtimeMode: .thread.runtimeMode,
    runtimeStatus: .thread.runtimeStatus,
    provider: .thread.providerName
  },
  repository
}' "$baseline_path"
REMOTE
