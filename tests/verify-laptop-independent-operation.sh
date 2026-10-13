#!/usr/bin/env bash

set -euo pipefail

required_variables=(
  RIVET_WORKSPACE_IP
  RIVET_WORKSPACE_PUBLIC_IP
  RIVET_OPERATOR_SSH_PRIVATE_KEY
)

for variable in "${required_variables[@]}"; do
  if [[ -z "${!variable:-}" ]]; then
    echo "Required environment variable is unset: ${variable}" >&2
    exit 1
  fi
done

ssh \
  -o "HostKeyAlias=${RIVET_WORKSPACE_PUBLIC_IP}" \
  -o StrictHostKeyChecking=yes \
  -i "${RIVET_OPERATOR_SSH_PRIVATE_KEY}" \
  "rivet-admin@${RIVET_WORKSPACE_IP}" \
  'rivet_uid=$(id -u rivet); sudo -u rivet env HOME=/home/rivet T3CODE_HOME=/home/rivet/.t3 PATH=/home/rivet/.local/bin:/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin XDG_RUNTIME_DIR=/run/user/${rivet_uid} DBUS_SESSION_BUS_ADDRESS=unix:path=/run/user/${rivet_uid}/bus bash -s' <<'REMOTE'
set -euo pipefail

state_dir="${HOME}/.local/state/rivet-verification"
baseline_path="${state_dir}/issue-7-before.json"
after_path="${state_dir}/issue-7-after.json"
t3_state="${HOME}/.t3/userdata"
database="${t3_state}/state.sqlite"
repository="${HOME}/workspaces/rivet"

for command in git jq sha256sum sqlite3 systemctl; do
  if ! command -v "$command" >/dev/null 2>&1; then
    echo "Required cloud command is unavailable: ${command}" >&2
    exit 1
  fi
done

if [[ ! -r "$baseline_path" ]]; then
  echo "Protected Issue #7 baseline is unavailable: ${baseline_path}" >&2
  exit 1
fi

baseline_mode="$(stat -c '%a' "$baseline_path")"
baseline_owner="$(stat -c '%U:%G' "$baseline_path")"
if [[ "$baseline_mode" != 600 || "$baseline_owner" != rivet:rivet ]]; then
  echo "Protected Issue #7 baseline ownership or mode is invalid." >&2
  exit 1
fi

hash_value() {
  printf '%s' "$1" | sha256sum | awk '{print $1}'
}

thread_state="$(
  sqlite3 -json "$database" <<'SQL'
SELECT
  threads.thread_id AS threadId,
  threads.project_id AS projectId,
  COALESCE(threads.branch, '') AS branch,
  CASE WHEN threads.worktree_path IS NULL THEN 0 ELSE 1 END AS hasWorktree,
  COALESCE(threads.latest_turn_id, '') AS latestTurnId,
  threads.updated_at AS updatedAt,
  COALESCE(runtime.runtime_mode, '') AS runtimeMode,
  COALESCE(runtime.status, '') AS runtimeStatus,
  COALESCE(runtime.provider_name, '') AS providerName,
  COALESCE(runtime.last_seen_at, '') AS runtimeLastSeenAt
FROM projection_threads AS threads
INNER JOIN projection_projects AS projects
  ON projects.project_id = threads.project_id
LEFT JOIN provider_session_runtime AS runtime
  ON runtime.thread_id = threads.thread_id
WHERE projects.workspace_root = '/home/rivet/workspaces/rivet'
  AND threads.deleted_at IS NULL
ORDER BY threads.updated_at DESC
LIMIT 1;
SQL
)"

if ! jq -e 'length == 1' <<<"$thread_state" >/dev/null; then
  echo "No active Rivet thread exists in the cloud T3 database." >&2
  exit 1
fi

thread_id="$(jq -er '.[0].threadId' <<<"$thread_state")"
project_id="$(jq -er '.[0].projectId' <<<"$thread_state")"
thread_branch="$(jq -er '.[0].branch' <<<"$thread_state")"
thread_has_worktree="$(jq -r '.[0].hasWorktree == 1' <<<"$thread_state")"
latest_turn_id="$(jq -er '.[0].latestTurnId' <<<"$thread_state")"
thread_updated_at="$(jq -er '.[0].updatedAt' <<<"$thread_state")"
runtime_mode="$(jq -er '.[0].runtimeMode' <<<"$thread_state")"
runtime_status="$(jq -er '.[0].runtimeStatus' <<<"$thread_state")"
provider_name="$(jq -er '.[0].providerName' <<<"$thread_state")"
runtime_last_seen_at="$(jq -er '.[0].runtimeLastSeenAt' <<<"$thread_state")"

service_active="$(systemctl --user show t3code.service --property=ActiveState --value)"
service_enabled="$(systemctl --user show t3code.service --property=UnitFileState --value)"
service_main_pid="$(systemctl --user show t3code.service --property=MainPID --value)"
service_started_monotonic="$(
  systemctl --user show t3code.service --property=ExecMainStartTimestampMonotonic --value
)"

connect_status="$(
  "${HOME}/.local/bin/t3" connect status --json |
    jq '{
      desired,
      authenticated,
      linked,
      relayClientStatus: .relayClient.status
    }'
)"

processes="$({
  ps -eo pid=,ppid=,user=,comm= |
    awk '$3 == "rivet" && ($4 == "node-MainThread" || $4 == "cloudflared" || $4 == "codex") {
      print $1 "\t" $2 "\t" $3 "\t" $4
    }' |
    jq -Rsc '
      split("\n") |
      map(
        select(length > 0) |
        split("\t") |
        {
          pid: (.[0] | tonumber),
          parentPid: (.[1] | tonumber),
          user: .[2],
          command: .[3]
        }
      )
    '
} )"

repository_clean=false
if [[ -z "$(git -C "$repository" status --porcelain)" ]]; then
  repository_clean=true
fi

temporary_path="$(mktemp "${state_dir}/.issue-7-after.XXXXXX")"
trap 'rm -f "$temporary_path"' EXIT
chmod 0600 "$temporary_path"

jq -n \
  --arg captured_at_utc "$(date -u +'%Y-%m-%dT%H:%M:%SZ')" \
  --arg machine_fingerprint "$(hash_value "$(</etc/machine-id)")" \
  --arg boot_fingerprint "$(hash_value "$(</proc/sys/kernel/random/boot_id)")" \
  --arg boot_epoch "$(awk '$1 == "btime" { print $2 }' /proc/stat)" \
  --arg uptime_seconds "$(awk '{ print $1 }' /proc/uptime)" \
  --arg service_active "$service_active" \
  --arg service_enabled "$service_enabled" \
  --arg service_main_pid "$service_main_pid" \
  --arg service_started_monotonic "$service_started_monotonic" \
  --arg environment_fingerprint "$(hash_value "$(<"${t3_state}/environment-id")")" \
  --argjson connect "$connect_status" \
  --arg thread_fingerprint "$(hash_value "$thread_id")" \
  --arg project_fingerprint "$(hash_value "$project_id")" \
  --arg thread_branch "$thread_branch" \
  --arg thread_has_worktree "$thread_has_worktree" \
  --arg latest_turn_fingerprint "$(hash_value "$latest_turn_id")" \
  --arg thread_updated_at "$thread_updated_at" \
  --arg runtime_mode "$runtime_mode" \
  --arg runtime_status "$runtime_status" \
  --arg provider_name "$provider_name" \
  --arg runtime_last_seen_at "$runtime_last_seen_at" \
  --arg repository_head "$(git -C "$repository" rev-parse HEAD)" \
  --arg repository_branch "$(git -C "$repository" symbolic-ref --short HEAD)" \
  --argjson repository_clean "$repository_clean" \
  --argjson processes "$processes" \
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
      startedMonotonic: $service_started_monotonic
    },
    environment: ({fingerprint: $environment_fingerprint} + $connect),
    thread: {
      fingerprint: $thread_fingerprint,
      projectFingerprint: $project_fingerprint,
      branch: $thread_branch,
      hasWorktree: ($thread_has_worktree == "true"),
      latestTurnFingerprint: $latest_turn_fingerprint,
      updatedAt: $thread_updated_at,
      runtime: {
        mode: $runtime_mode,
        status: $runtime_status,
        provider: $provider_name,
        lastSeenAt: $runtime_last_seen_at
      }
    },
    repository: {
      path: "/home/rivet/workspaces/rivet",
      head: $repository_head,
      branch: $repository_branch,
      clean: $repository_clean
    },
    processes: $processes
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
        elapsedUptimeSeconds: ($after.host.uptimeSeconds - $before.host.uptimeSeconds),
        sameHost: ($after.host.machineFingerprint == $before.host.machineFingerprint),
        sameBoot: (
          $after.host.bootFingerprint == $before.host.bootFingerprint and
          $after.host.bootEpoch == $before.host.bootEpoch
        ),
        sameServiceProcess: (
          $after.service.mainPid == $before.service.mainPid and
          $after.service.startedMonotonic == $before.service.startedMonotonic
        ),
        serviceActiveAndEnabled: (
          $after.service.activeState == "active" and
          $after.service.unitFileState == "enabled"
        ),
        sameEnvironment: (
          $after.environment.fingerprint == $before.environment.fingerprint
        ),
        environmentReady: (
          $after.environment.desired == true and
          $after.environment.authenticated == true and
          $after.environment.linked == true and
          $after.environment.relayClientStatus == "available"
        ),
        sameThread: (
          $after.thread.fingerprint == $before.thread.fingerprint and
          $after.thread.projectFingerprint == $before.thread.projectFingerprint
        ),
        authenticatedTurnRecorded: (
          $after.thread.latestTurnFingerprint != $before.thread.latestTurnFingerprint and
          $after.thread.updatedAt > $before.thread.updatedAt and
          $after.thread.runtime.provider == "codex"
        ),
        supervisedMode: ($after.thread.runtime.mode == "approval-required"),
        sameRepository: (
          $after.repository.path == $before.repository.path and
          $after.repository.head == $before.repository.head and
          $after.repository.branch == $before.repository.branch
        ),
        repositoryClean: $after.repository.clean,
        processCommands: ([$after.processes[].command] | unique)
      }
    '
)"

if ! jq -e '
  .elapsedUptimeSeconds > 0 and
  .sameHost == true and
  .sameBoot == true and
  .sameServiceProcess == true and
  .serviceActiveAndEnabled == true and
  .sameEnvironment == true and
  .environmentReady == true and
  .sameThread == true and
  .authenticatedTurnRecorded == true and
  .supervisedMode == true and
  .sameRepository == true and
  .repositoryClean == true and
  (.processCommands | index("node-MainThread") != null) and
  (.processCommands | index("cloudflared") != null) and
  (.processCommands | index("codex") != null)
' <<<"$comparison" >/dev/null; then
  echo "Laptop-independent continuity verification failed:" >&2
  jq . <<<"$comparison" >&2
  exit 1
fi

jq . <<<"$comparison"
REMOTE
