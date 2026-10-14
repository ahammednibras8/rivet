#!/usr/bin/env bash

set -euo pipefail

required_variables=(
  RIVET_WORKSPACE_IP
  RIVET_WORKSPACE_PUBLIC_IP
  RIVET_OPERATOR_SSH_PRIVATE_KEY
  RIVET_ISSUE9_MARKER
)

for variable in "${required_variables[@]}"; do
  if [[ -z "${!variable:-}" ]]; then
    echo "Required environment variable is unset: ${variable}" >&2
    exit 1
  fi
done

if [[ ! "$RIVET_ISSUE9_MARKER" =~ ^[[:alnum:]_.:-]{12,128}$ ]]; then
  echo "RIVET_ISSUE9_MARKER must contain 12-128 non-secret identifier characters." >&2
  exit 1
fi

marker_base64="$(printf '%s' "$RIVET_ISSUE9_MARKER" | base64 | tr -d '\n')"
remote_command="sudo -u rivet env HOME=/home/rivet PATH=/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin bash -s -- '${marker_base64}'"

ssh \
  -o "HostKeyAlias=${RIVET_WORKSPACE_PUBLIC_IP}" \
  -o StrictHostKeyChecking=yes \
  -i "${RIVET_OPERATOR_SSH_PRIVATE_KEY}" \
  "rivet-admin@${RIVET_WORKSPACE_IP}" \
  "$remote_command" <<'REMOTE'
set -euo pipefail

marker="$(printf '%s' "$1" | base64 --decode)"
database="${HOME}/.t3/userdata/state.sqlite"
default_checkout="${HOME}/workspaces/rivet"
expected_head='1a0bba01e1ba3e072f66625bcd05a1a4aadf5acb'
state_dir="${HOME}/.local/state/rivet-verification"
evidence_path="${state_dir}/issue-9-isolated-worktree.json"

for command in git jq sha256sum sqlite3 stat; do
  if ! command -v "$command" >/dev/null 2>&1; then
    echo "Required cloud command is unavailable: ${command}" >&2
    exit 1
  fi
done

for required_path in "$database" "$default_checkout/.git"; do
  if [[ ! -e "$required_path" ]]; then
    echo "Required cloud state is unavailable: ${required_path}" >&2
    exit 1
  fi
done

thread_state="$({
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
  COUNT(messages.message_id) AS messageCount
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
})"

if ! jq -e 'length == 1' <<<"$thread_state" >/dev/null; then
  echo "The Issue #9 marker must identify exactly one active cloud thread." >&2
  exit 1
fi

thread="$(jq '.[0]' <<<"$thread_state")"
worktree="$(jq -r '.worktreePath // ""' <<<"$thread")"
isolated_checkout="$default_checkout"
isolation_mode='branch'

if [[ -n "$worktree" ]]; then
  if [[ "$worktree" == "$default_checkout" || "$worktree" != /home/rivet/* ]]; then
    echo "The marked thread has an invalid worktree path." >&2
    exit 1
  fi

  isolated_checkout="$worktree"
  isolation_mode='worktree'
fi

if [[ ! -e "$isolated_checkout/.git" ]]; then
  echo "The isolated checkout no longer exists." >&2
  exit 1
fi

fixture="${isolated_checkout}/tests/fixtures/issue-9/command-state.sh"
expected_fixture_sha="$({
  cat <<'EXPECTED'
#!/usr/bin/env bash
set -euo pipefail

mode="${1:-success}"

printf 'issue-9 stdout mode=%s\n' "$mode"
printf 'issue-9 stderr mode=%s\n' "$mode" >&2

case "$mode" in
  success) exit 0 ;;
  failure) exit 23 ;;
  *) exit 64 ;;
esac
EXPECTED
} | sha256sum | awk '{print $1}')"

actual_fixture_sha=''
fixture_executable=false
if [[ -f "$fixture" ]]; then
  actual_fixture_sha="$(sha256sum "$fixture" | awk '{print $1}')"
  if [[ -x "$fixture" ]]; then
    fixture_executable=true
  fi
fi

isolated_dirty=false
if [[ -n "$(git -C "$isolated_checkout" status --porcelain)" ]]; then
  isolated_dirty=true
fi

mapfile -t registered_worktrees < <(
  git -C "$default_checkout" worktree list --porcelain |
    awk '/^worktree / {sub(/^worktree /, ""); print}'
)

unrelated_worktree_count=0
for registered_worktree in "${registered_worktrees[@]}"; do
  if [[ "$registered_worktree" != "$default_checkout" && "$registered_worktree" != "$isolated_checkout" ]]; then
    unrelated_worktree_count=$((unrelated_worktree_count + 1))
  fi
done

main_head="$(git -C "$default_checkout" rev-parse refs/heads/main)"
origin_main_head="$(git -C "$default_checkout" rev-parse refs/remotes/origin/main)"
isolated_head="$(git -C "$isolated_checkout" rev-parse HEAD)"
isolated_branch="$(git -C "$isolated_checkout" symbolic-ref --short HEAD)"

verification="$(
  jq -n \
    --argjson thread "$thread" \
    --arg isolation_mode "$isolation_mode" \
    --arg main_head "$main_head" \
    --arg origin_main_head "$origin_main_head" \
    --arg isolated_head "$isolated_head" \
    --arg isolated_branch "$isolated_branch" \
    --arg expected_head "$expected_head" \
    --arg expected_fixture_sha "$expected_fixture_sha" \
    --arg actual_fixture_sha "$actual_fixture_sha" \
    --argjson fixture_executable "$fixture_executable" \
    --argjson isolated_dirty "$isolated_dirty" \
    --argjson worktree_count "${#registered_worktrees[@]}" \
    --argjson unrelated_worktree_count "$unrelated_worktree_count" \
    '{
      uniqueThread: true,
      isolationMode: $isolation_mode,
      workspaceMatches: ($thread.workspaceRoot == "/home/rivet/workspaces/rivet"),
      separateWorktree: ($isolation_mode == "worktree"),
      issueSpecificBranch: ($isolated_branch != "main"),
      branchMatchesThread: (
        $isolation_mode == "branch" or
        $isolated_branch == $thread.branch
      ),
      baseCommitMatches: ($isolated_head == $expected_head),
      deterministicChangePresent: ($actual_fixture_sha | length == 64),
      deterministicChangeMatches: ($actual_fixture_sha == $expected_fixture_sha),
      deterministicChangeExecutable: $fixture_executable,
      isolatedWorktreeDirty: $isolated_dirty,
      defaultBranchUntouched: (
        $main_head == $expected_head and
        $origin_main_head == $expected_head
      ),
      registeredWorktreeCount: $worktree_count,
      unrelatedWorktreeCount: $unrelated_worktree_count,
      noUnrelatedWorktrees: ($unrelated_worktree_count == 0),
      thread: {
        identityRecorded: ($thread.threadId | length > 0),
        projectIdentityRecorded: ($thread.projectId | length > 0),
        latestTurnRecorded: ($thread.latestTurnId | length > 0),
        messageCount: $thread.messageCount,
        runtimeMode: $thread.runtimeMode,
        runtimeStatus: $thread.runtimeStatus,
        provider: $thread.providerName
      }
    }'
)"

if ! jq -e '
  .uniqueThread and
  .workspaceMatches and
  .issueSpecificBranch and
  .branchMatchesThread and
  .baseCommitMatches and
  .deterministicChangePresent and
  .deterministicChangeMatches and
  .deterministicChangeExecutable and
  .isolatedWorktreeDirty and
  .defaultBranchUntouched and
  .noUnrelatedWorktrees and
  .thread.identityRecorded and
  .thread.projectIdentityRecorded and
  .thread.latestTurnRecorded and
  (.thread.messageCount >= 4) and
  (.thread.provider == "codex")
' <<<"$verification" >/dev/null; then
  echo "The isolated-worktree state does not satisfy Issue #9." >&2
  jq . <<<"$verification" >&2
  exit 1
fi

install -d -m 0700 "$state_dir"
temporary_path="$(mktemp "${state_dir}/.issue-9-isolated-worktree.XXXXXX")"
trap 'rm -f "$temporary_path"' EXIT
chmod 0600 "$temporary_path"

jq -n \
  --arg captured_at_utc "$(date -u +'%Y-%m-%dT%H:%M:%SZ')" \
  --arg marker_fingerprint "$(printf '%s' "$marker" | sha256sum | awk '{print $1}')" \
  --argjson thread "$thread" \
  --argjson verification "$verification" \
  '{
    schemaVersion: 1,
    capturedAtUtc: $captured_at_utc,
    markerFingerprint: $marker_fingerprint,
    thread: $thread,
    verification: $verification
  }' >"$temporary_path"

mv "$temporary_path" "$evidence_path"
trap - EXIT

jq '{
  capturedAtUtc,
  uniqueThread: .verification.uniqueThread,
  isolationMode: .verification.isolationMode,
  workspaceMatches: .verification.workspaceMatches,
  separateWorktree: .verification.separateWorktree,
  issueSpecificBranch: .verification.issueSpecificBranch,
  branchMatchesThread: .verification.branchMatchesThread,
  baseCommitMatches: .verification.baseCommitMatches,
  deterministicChangePresent: .verification.deterministicChangePresent,
  deterministicChangeMatches: .verification.deterministicChangeMatches,
  deterministicChangeExecutable: .verification.deterministicChangeExecutable,
  isolatedWorktreeDirty: .verification.isolatedWorktreeDirty,
  defaultBranchUntouched: .verification.defaultBranchUntouched,
  registeredWorktreeCount: .verification.registeredWorktreeCount,
  unrelatedWorktreeCount: .verification.unrelatedWorktreeCount,
  thread: .verification.thread
}' "$evidence_path"
REMOTE
