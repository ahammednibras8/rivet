#!/usr/bin/env bash

set -euo pipefail

required_variables=(
  RIVET_WORKSPACE_IP
  RIVET_WORKSPACE_PUBLIC_IP
  RIVET_OPERATOR_SSH_PRIVATE_KEY
  RIVET_ORGANIZATION_DISCOVERY_MARKER
)

for variable in "${required_variables[@]}"; do
  if [[ -z "${!variable:-}" ]]; then
    echo "Required environment variable is unset: ${variable}" >&2
    exit 1
  fi
done

if [[ ! "$RIVET_ORGANIZATION_DISCOVERY_MARKER" =~ ^[[:alnum:]_.:-]{12,128}$ ]]; then
  echo "RIVET_ORGANIZATION_DISCOVERY_MARKER must contain 12-128 non-secret identifier characters." >&2
  exit 1
fi

marker_base64="$(
  printf '%s' "$RIVET_ORGANIZATION_DISCOVERY_MARKER" |
    base64 |
    tr -d '\n'
)"

remote_command="rivet_uid=\$(id -u rivet); sudo -u rivet env HOME=/home/rivet T3CODE_HOME=/home/rivet/.t3 PATH=/home/rivet/.local/bin:/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin XDG_RUNTIME_DIR=/run/user/\${rivet_uid} DBUS_SESSION_BUS_ADDRESS=unix:path=/run/user/\${rivet_uid}/bus bash -s -- '${marker_base64}'"

ssh \
  -o "HostKeyAlias=${RIVET_WORKSPACE_PUBLIC_IP}" \
  -o StrictHostKeyChecking=yes \
  -i "${RIVET_OPERATOR_SSH_PRIVATE_KEY}" \
  "rivet-admin@${RIVET_WORKSPACE_IP}" \
  "$remote_command" <<'REMOTE'
set -euo pipefail

cd /
umask 0027

marker="$(printf '%s' "$1" | base64 --decode)"
manifest="${HOME}/.config/rivet/repositories.json"
database="${HOME}/.t3/userdata/state.sqlite"

for command in find git jq sqlite3 stat systemctl; do
  if ! command -v "$command" >/dev/null 2>&1; then
    echo "A required cloud verification command is unavailable." >&2
    exit 1
  fi
done

for path in "$manifest" "$database"; do
  if [[ ! -f "$path" || -L "$path" ]]; then
    echo "Required private onboarding state is unavailable." >&2
    exit 1
  fi
done

organization="$(jq -er '.repositories[0].organization' "$manifest")"
repository_name="$(jq -er '.repositories[0].expected_name' "$manifest")"
default_branch="$(jq -er '.repositories[0].default_branch' "$manifest")"

[[ "$organization" =~ ^[A-Za-z0-9-]+$ ]] || {
  echo "The private approval identity is invalid." >&2
  exit 1
}
[[ "$repository_name" =~ ^[A-Za-z0-9._-]+$ ]] || {
  echo "The private approval identity is invalid." >&2
  exit 1
}

checkout="${HOME}/workspaces/organizations/${organization}/${repository_name}"

repository_verified=false
if /usr/local/bin/rivet-repository status >/dev/null 2>&1; then
  repository_verified=true
fi

project_registered=false
if /usr/local/bin/rivet-repository register >/dev/null 2>&1; then
  project_registered=true
fi

active_project_count="$(
  sqlite3 "$database" <<SQL
SELECT COUNT(*)
FROM projection_projects
WHERE workspace_root = '${checkout}'
  AND deleted_at IS NULL;
SQL
)"

if ! thread_state="$(
  sqlite3 -json "$database" 2>/dev/null <<SQL
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
  COALESCE(runtime.runtime_mode, '') AS runtimeMode,
  COALESCE(runtime.provider_name, '') AS providerName,
  COUNT(messages.message_id) AS messageCount,
  SUM(CASE WHEN messages.role = 'user' THEN 1 ELSE 0 END) AS userMessageCount,
  SUM(CASE WHEN messages.role = 'assistant' THEN 1 ELSE 0 END) AS assistantMessageCount,
  MAX(CASE WHEN instr(messages.text, '${marker}') > 0 THEN 1 ELSE 0 END) AS markerPresent
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
  AND projects.deleted_at IS NULL
GROUP BY threads.thread_id;
SQL
)"; then
  echo "The private T3 thread state could not be verified." >&2
  exit 1
fi

unique_thread=false
if jq -e 'length == 1' <<<"$thread_state" >/dev/null; then
  unique_thread=true
fi

thread_matches_project=false
if jq -e \
  --arg checkout "$checkout" \
  --arg branch "$default_branch" '
    length == 1 and
    .[0].workspaceRoot == $checkout and
    .[0].branch == $branch and
    .[0].worktreePath == null
  ' <<<"$thread_state" >/dev/null; then
  thread_matches_project=true
fi

supervised_read_only_thread=false
if jq -e '
  length == 1 and
  .[0].runtimeMode == "approval-required" and
  .[0].providerName == "codex" and
  .[0].messageCount >= 2 and
  .[0].userMessageCount >= 1 and
  .[0].assistantMessageCount >= 1 and
  .[0].markerPresent == 1
' <<<"$thread_state" >/dev/null; then
  supervised_read_only_thread=true
fi

repository_clean=false
if [[ -z "$(
  git -C "$checkout" status --porcelain=v1 \
    --untracked-files=all 2>/dev/null
)" ]]; then
  repository_clean=true
fi

secure_permissions=false
if ! find "$checkout" -xdev ! -type l \
  \( -perm -0020 -o -perm -0002 \) -print -quit |
  grep -q .; then
  secure_permissions=true
fi

service_umask=false
if [[ "$(
  systemctl --user show t3code.service --property=UMask --value
)" == "0027" ]]; then
  service_umask=true
fi

verification="$(
  jq -n \
    --argjson repository_verified "$repository_verified" \
    --argjson project_registered "$project_registered" \
    --argjson active_project_count "$active_project_count" \
    --argjson unique_thread "$unique_thread" \
    --argjson thread_matches_project "$thread_matches_project" \
    --argjson supervised_read_only_thread "$supervised_read_only_thread" \
    --argjson repository_clean "$repository_clean" \
    --argjson secure_permissions "$secure_permissions" \
    --argjson service_umask "$service_umask" \
    '{
      repositoryVerified: $repository_verified,
      projectRegistered: $project_registered,
      activeProjectCount: $active_project_count,
      uniqueDiscoveryThread: $unique_thread,
      threadMatchesApprovedProject: $thread_matches_project,
      supervisedReadOnlyThread: $supervised_read_only_thread,
      repositoryClean: $repository_clean,
      securePermissions: $secure_permissions,
      serviceUmask: $service_umask
    }'
)"

if ! jq -e '
  .repositoryVerified and
  .projectRegistered and
  .activeProjectCount == 1 and
  .uniqueDiscoveryThread and
  .threadMatchesApprovedProject and
  .supervisedReadOnlyThread and
  .repositoryClean and
  .securePermissions and
  .serviceUmask
' <<<"$verification" >/dev/null; then
  echo "Organization repository onboarding verification failed:" >&2
  jq . <<<"$verification" >&2
  exit 1
fi

jq . <<<"$verification"
REMOTE
