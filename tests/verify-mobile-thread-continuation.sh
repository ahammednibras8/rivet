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
after_path="${state_dir}/issue-8-after.json"
database="${HOME}/.t3/userdata/state.sqlite"
repository="${HOME}/workspaces/rivet"

for command in git jq sha256sum sqlite3 stat; do
  if ! command -v "$command" >/dev/null 2>&1; then
    echo "Required cloud command is unavailable: ${command}" >&2
    exit 1
  fi
done

for path in "$baseline_path" "$database" "$repository/.git"; do
  if [[ ! -e "$path" ]]; then
    echo "Required cloud state is unavailable: ${path}" >&2
    exit 1
  fi
done

if [[ "$(stat -c '%U:%G %a' "$baseline_path")" != 'rivet:rivet 600' ]]; then
  echo "The protected continuity baseline has unsafe ownership or permissions." >&2
  exit 1
fi

if ! jq -e '
  .schemaVersion == 1 and
  (.markerFingerprint | type == "string" and length == 64) and
  (.contextFingerprint | type == "string" and length == 64) and
  (.historyDigest | type == "string" and length == 64) and
  (.thread.threadId | type == "string" and length > 0) and
  (.thread.projectId | type == "string" and length > 0) and
  (.thread.latestTurnId | type == "string" and length > 0) and
  (.thread.messageCount | type == "number" and . >= 2) and
  (.thread.lastMessageCreatedAt | type == "string" and length > 0)
' "$baseline_path" >/dev/null; then
  echo "The protected continuity baseline is invalid." >&2
  exit 1
fi

baseline_message_count="$(jq -er '.thread.messageCount | floor | tostring' "$baseline_path")"

current_state="$(
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

if ! jq -e 'length == 1' <<<"$current_state" >/dev/null; then
  echo "The continuity marker no longer identifies exactly one active cloud thread." >&2
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
ORDER BY messages.created_at, messages.message_id
LIMIT ${baseline_message_count};
SQL
} | sha256sum | awk '{print $1}')"

followup_response_count="$(
  sqlite3 "$database" <<SQL
SELECT COUNT(*)
FROM projection_thread_messages AS messages
WHERE messages.thread_id = (
  SELECT DISTINCT thread_id
  FROM projection_thread_messages
  WHERE instr(text, '${marker}') > 0
)
  AND messages.role = 'assistant'
  AND messages.created_at > '$(jq -r '.thread.lastMessageCreatedAt' "$baseline_path")'
  AND instr(messages.text, '${context_phrase}') > 0;
SQL
)"

repository_clean=false
if [[ -z "$(git -C "$repository" status --porcelain)" ]]; then
  repository_clean=true
fi

comparison="$({
  jq -n \
    --slurpfile baseline "$baseline_path" \
    --argjson current "$(jq '.[0]' <<<"$current_state")" \
    --arg marker_fingerprint "$(printf '%s' "$marker" | sha256sum | awk '{print $1}')" \
    --arg context_fingerprint "$(printf '%s' "$context_phrase" | sha256sum | awk '{print $1}')" \
    --arg history_digest "$history_digest" \
    --argjson followup_response_count "$followup_response_count" \
    --arg repository_head "$(git -C "$repository" rev-parse HEAD)" \
    --arg repository_branch "$(git -C "$repository" symbolic-ref --short HEAD)" \
    --argjson repository_clean "$repository_clean" \
    '($baseline[0]) as $before |
    {
      inputsMatchBaseline: (
        $marker_fingerprint == $before.markerFingerprint and
        $context_fingerprint == $before.contextFingerprint
      ),
      sameThread: ($current.threadId == $before.thread.threadId),
      sameProject: ($current.projectId == $before.thread.projectId),
      sameWorkspace: (
        $current.workspaceRoot == $before.thread.workspaceRoot and
        $current.branch == $before.thread.branch and
        $current.worktreePath == $before.thread.worktreePath
      ),
      historyPreserved: ($history_digest == $before.historyDigest),
      latestTurnAdvanced: (
        $current.latestTurnId != $before.thread.latestTurnId and
        $current.lastMessageCreatedAt > $before.thread.lastMessageCreatedAt
      ),
      userMessageAdvanced: ($current.userMessageCount > $before.thread.userMessageCount),
      assistantMessageAdvanced: ($current.assistantMessageCount > $before.thread.assistantMessageCount),
      contextDependentResponseRecorded: ($followup_response_count > 0),
      markerStillUnique: ($current.markerPresent == 1),
      contextStillPresent: ($current.contextPresent == 1),
      supervisedMode: (
        $current.runtimeMode == "approval-required" and
        $current.providerName == "codex"
      ),
      sameRepository: (
        $before.repository.path == "/home/rivet/workspaces/rivet" and
        $repository_head == $before.repository.head and
        $repository_branch == $before.repository.branch and
        $repository_clean == $before.repository.clean
      ),
      repositoryClean: $repository_clean,
      before: {
        messageCount: $before.thread.messageCount,
        userMessageCount: $before.thread.userMessageCount,
        assistantMessageCount: $before.thread.assistantMessageCount
      },
      after: {
        messageCount: $current.messageCount,
        userMessageCount: $current.userMessageCount,
        assistantMessageCount: $current.assistantMessageCount,
        branch: $current.branch,
        hasWorktree: ($current.worktreePath != null),
        runtimeMode: $current.runtimeMode,
        runtimeStatus: $current.runtimeStatus,
        provider: $current.providerName
      }
    }'
})"

if ! jq -e '
  .inputsMatchBaseline and
  .sameThread and
  .sameProject and
  .sameWorkspace and
  .historyPreserved and
  .latestTurnAdvanced and
  .userMessageAdvanced and
  .assistantMessageAdvanced and
  .contextDependentResponseRecorded and
  .markerStillUnique and
  .contextStillPresent and
  .supervisedMode and
  .sameRepository and
  .repositoryClean
' <<<"$comparison" >/dev/null; then
  echo "The mobile continuation did not preserve every required invariant." >&2
  jq . <<<"$comparison" >&2
  exit 1
fi

temporary_path="$(mktemp "${state_dir}/.issue-8-after.XXXXXX")"
trap 'rm -f "$temporary_path"' EXIT
chmod 0600 "$temporary_path"

jq -n \
  --arg captured_at_utc "$(date -u +'%Y-%m-%dT%H:%M:%SZ')" \
  --slurpfile baseline "$baseline_path" \
  --argjson current "$(jq '.[0]' <<<"$current_state")" \
  --argjson comparison "$comparison" \
  '{
    schemaVersion: 1,
    capturedAtUtc: $captured_at_utc,
    baselineCapturedAtUtc: $baseline[0].capturedAtUtc,
    thread: $current,
    comparison: $comparison
  }' >"$temporary_path"

mv "$temporary_path" "$after_path"
trap - EXIT

jq '{
  baselineCapturedAtUtc,
  afterCapturedAtUtc: .capturedAtUtc,
  inputsMatchBaseline: .comparison.inputsMatchBaseline,
  sameThread: .comparison.sameThread,
  sameProject: .comparison.sameProject,
  sameWorkspace: .comparison.sameWorkspace,
  historyPreserved: .comparison.historyPreserved,
  latestTurnAdvanced: .comparison.latestTurnAdvanced,
  contextDependentResponseRecorded: .comparison.contextDependentResponseRecorded,
  supervisedMode: .comparison.supervisedMode,
  sameRepository: .comparison.sameRepository,
  repositoryClean: .comparison.repositoryClean,
  messages: {
    before: .comparison.before.messageCount,
    after: .comparison.after.messageCount,
    userDelta: (.comparison.after.userMessageCount - .comparison.before.userMessageCount),
    assistantDelta: (.comparison.after.assistantMessageCount - .comparison.before.assistantMessageCount)
  },
  branch: .comparison.after.branch,
  hasWorktree: .comparison.after.hasWorktree,
  runtimeMode: .comparison.after.runtimeMode,
  runtimeStatus: .comparison.after.runtimeStatus,
  provider: .comparison.after.provider
}' "$after_path"
REMOTE
