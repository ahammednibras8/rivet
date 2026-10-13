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
t3_state="${HOME}/.t3/userdata"
database="${t3_state}/state.sqlite"
repository="${HOME}/workspaces/rivet"

for command in git jq sha256sum sqlite3 systemctl; do
  if ! command -v "$command" >/dev/null 2>&1; then
    echo "Required cloud command is unavailable: ${command}" >&2
    exit 1
  fi
done

for path in \
  /etc/machine-id \
  /proc/sys/kernel/random/boot_id \
  "${t3_state}/environment-id" \
  "$database"; do
  if [[ ! -r "$path" ]]; then
    echo "Required cloud identity source is unreadable: ${path}" >&2
    exit 1
  fi
done

if [[ ! -d "$repository/.git" ]]; then
  echo "Approved cloud checkout is unavailable: ${repository}" >&2
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

if [[ "$service_active" != active || "$service_enabled" != enabled ]]; then
  echo "T3 Code must be active and enabled before the laptop-off test." >&2
  exit 1
fi
if [[ ! "$service_main_pid" =~ ^[1-9][0-9]*$ ]]; then
  echo "T3 Code has no running service process." >&2
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
  echo "T3 Connect is not ready for the laptop-off test." >&2
  exit 1
fi

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

if [[ "$(jq 'length' <<<"$processes")" -lt 3 ]]; then
  echo "Expected T3 and relay process set is incomplete." >&2
  exit 1
fi

if [[ -z "$(git -C "$repository" symbolic-ref --short HEAD 2>/dev/null)" ]]; then
  echo "Approved cloud checkout is not on a branch." >&2
  exit 1
fi

repository_clean=false
if [[ -z "$(git -C "$repository" status --porcelain)" ]]; then
  repository_clean=true
fi

install -d -m 0700 "$state_dir"
temporary_path="$(mktemp "${state_dir}/.issue-7-before.XXXXXX")"
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
    startRecorded: (.service.startedMonotonic | length > 0)
  },
  environment: {
    identityRecorded: (.environment.fingerprint | length == 64),
    desired: .environment.desired,
    authenticated: .environment.authenticated,
    linked: .environment.linked,
    relayClientStatus: .environment.relayClientStatus
  },
  thread: {
    identityRecorded: (.thread.fingerprint | length == 64),
    latestTurnRecorded: (.thread.latestTurnFingerprint | length == 64),
    branch: .thread.branch,
    hasWorktree: .thread.hasWorktree,
    runtimeMode: .thread.runtime.mode,
    runtimeStatus: .thread.runtime.status,
    provider: .thread.runtime.provider
  },
  repository,
  processCommands: ([.processes[].command] | unique)
}' "$baseline_path"
REMOTE
