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
  'sudo -u rivet env HOME=/home/rivet PATH=/home/rivet/.local/bin:/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin bash -s' <<'REMOTE'
set -euo pipefail

cd /
umask 0077

manifest="${HOME}/.config/rivet/repositories.json"
state_directory="${HOME}/.local/state/rivet-verification"
baseline="${state_directory}/issue-36-before.json"
result="${state_directory}/issue-36-safe-denials.json"
expected_usage='Usage: rivet-repository {verify|clone|status|register}'

for command in gh git jq sha256sum; do
  if ! command -v "$command" >/dev/null 2>&1; then
    echo "A required cloud permission-verification command is unavailable." >&2
    exit 1
  fi
done

if [[ ! -f "$baseline" ]] ||
   ! /usr/local/bin/rivet-repository verify >/dev/null 2>&1; then
  echo "The organization access baseline or approval is unavailable." >&2
  exit 1
fi

organization="$(jq -er '.repositories[0].organization' "$manifest")"
repository_name="$(jq -er '.repositories[0].expected_name' "$manifest")"
default_branch="$(jq -er '.repositories[0].default_branch' "$manifest")"
checkout="${HOME}/workspaces/organizations/${organization}/${repository_name}"
baseline_default_head="$(jq -er '.defaultHead' "$baseline")"

[[ "$organization" =~ ^[A-Za-z0-9-]+$ ]] || exit 1
[[ "$repository_name" =~ ^[A-Za-z0-9._-]+$ ]] || exit 1

if [[ ! -d "$checkout" || -L "$checkout" ]]; then
  echo "The approved checkout is unavailable." >&2
  exit 1
fi

expected_remote="https://github.com/${organization}/${repository_name}.git"
actual_remote="$(git -C "$checkout" remote get-url origin 2>/dev/null)"
current_user="$(id -un)"
current_group="$(id -gn)"

if [[ "$actual_remote" != "$expected_remote" ]] ||
   ! find "$checkout" -maxdepth 0 \
     -user "$current_user" -group "$current_group" -print |
     grep -Fxq "$checkout" ||
   find "$checkout" -xdev ! -type l \
     \( -perm -0020 -o -perm -0002 \) -print -quit |
     grep -q .; then
  echo "The approved checkout identity or permissions are invalid." >&2
  exit 1
fi

remote_default_before="$(
  git -C "$checkout" ls-remote --exit-code origin \
    "refs/heads/${default_branch}" |
    awk 'NR == 1 {print $1}'
)"
checkout_state_before="$(
  git -C "$checkout" status --porcelain=v1 -z --untracked-files=all |
    sha256sum |
    awk '{print $1}'
)"
branch_before="$(git -C "$checkout" symbolic-ref --quiet HEAD)"
head_before="$(git -C "$checkout" rev-parse HEAD)"

if [[ "$remote_default_before" != "$baseline_default_head" ]]; then
  echo "The approved default branch changed after baseline capture." >&2
  exit 1
fi

set +e
unlisted_output="$(
  /usr/local/bin/rivet-repository verify example/repository 2>&1
)"
unlisted_status=$?
set -e

if [[ "$unlisted_status" != 2 || "$unlisted_output" != "$expected_usage" ]]; then
  echo "The guarded command did not reject caller-supplied repository input." >&2
  exit 1
fi

if ! gh api \
  --method GET \
  --header "Accept: application/vnd.github+json" \
  --header "X-GitHub-Api-Version: 2022-11-28" \
  "repos/${organization}/${repository_name}" \
  >/dev/null 2>&1; then
  echo "The approved repository metadata preflight failed." >&2
  exit 1
fi

expect_read_denied() {
  local endpoint="$1"

  if gh api \
    --method GET \
    --header "Accept: application/vnd.github+json" \
    --header "X-GitHub-Api-Version: 2022-11-28" \
    "$endpoint" \
    >/dev/null 2>&1; then
    echo "A prohibited read-only GitHub capability is available." >&2
    exit 1
  fi
}

expect_read_denied \
  "repos/${organization}/${repository_name}/actions/workflows?per_page=1"
expect_read_denied \
  "repos/${organization}/${repository_name}/actions/permissions/access"
expect_read_denied \
  "repos/${organization}/${repository_name}/actions/secrets?per_page=1"
expect_read_denied \
  "repos/${organization}/${repository_name}/hooks?per_page=1"
expect_read_denied \
  "repos/${organization}/${repository_name}/deployments?per_page=1"

remote_default_after="$(
  git -C "$checkout" ls-remote --exit-code origin \
    "refs/heads/${default_branch}" |
    awk 'NR == 1 {print $1}'
)"
checkout_state_after="$(
  git -C "$checkout" status --porcelain=v1 -z --untracked-files=all |
    sha256sum |
    awk '{print $1}'
)"
branch_after="$(git -C "$checkout" symbolic-ref --quiet HEAD)"
head_after="$(git -C "$checkout" rev-parse HEAD)"

if [[ "$remote_default_after" != "$baseline_default_head" ||
      "$checkout_state_after" != "$checkout_state_before" ||
      "$branch_after" != "$branch_before" ||
      "$head_after" != "$head_before" ]]; then
  echo "The default branch or approved checkout changed during safe probes." >&2
  exit 1
fi

captured_at="$(date -u +%Y-%m-%dT%H:%M:%SZ)"
temporary_result="$(mktemp "${state_directory}/.issue-36-denials.XXXXXX")"

jq -n \
  --arg captured_at "$captured_at" '
    {
      schemaVersion: 1,
      capturedAtUtc: $captured_at,
      callerSuppliedRepositoryRejected: true,
      workflowReadDenied: true,
      actionsAdministrationReadDenied: true,
      secretsMetadataReadDenied: true,
      webhookAdministrationReadDenied: true,
      deploymentReadDenied: true,
      defaultBranchUnchanged: true,
      checkoutStateUnchanged: true,
      defaultPushNotExercised: true,
      mergeNotExercised: true,
      approvalNotExercised: true
    }
  ' >"$temporary_result"

chmod 0600 "$temporary_result"
mv "$temporary_result" "$result"

jq -n \
  --arg captured_at "$captured_at" '
    {
      capturedAtUtc: $captured_at,
      callerSuppliedRepositoryRejected: true,
      workflowReadDenied: true,
      actionsAdministrationReadDenied: true,
      secretsMetadataReadDenied: true,
      webhookAdministrationReadDenied: true,
      deploymentReadDenied: true,
      defaultBranchUnchanged: true,
      checkoutStateUnchanged: true,
      unsafeStateChangingTestsSkipped: true,
      residualDefaultMergeApprovalRisk: true
    }
  '
REMOTE
