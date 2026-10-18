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
result="${state_directory}/issue-36-branch-lifecycle.json"

for command in git install jq sha256sum; do
  if ! command -v "$command" >/dev/null 2>&1; then
    echo "A required cloud branch-verification command is unavailable." >&2
    exit 1
  fi
done

if [[ ! -f "$baseline" ]] ||
   ! /usr/local/bin/rivet-repository status >/dev/null 2>&1; then
  echo "The organization access baseline is unavailable or stale." >&2
  exit 1
fi

organization="$(jq -er '.repositories[0].organization' "$manifest")"
repository_name="$(jq -er '.repositories[0].expected_name' "$manifest")"
default_branch="$(jq -er '.repositories[0].default_branch' "$manifest")"
checkout="${HOME}/workspaces/organizations/${organization}/${repository_name}"
baseline_default_head="$(jq -er '.defaultHead' "$baseline")"
branch="rivet-verification/issue-36-$(date -u +%Y%m%d%H%M%S)"

[[ "$organization" =~ ^[A-Za-z0-9-]+$ ]] || exit 1
[[ "$repository_name" =~ ^[A-Za-z0-9._-]+$ ]] || exit 1
[[ "$branch" =~ ^rivet-verification/issue-36-[0-9]{14}$ ]] || exit 1

remote_default_before="$(
  git -C "$checkout" ls-remote --exit-code origin \
    "refs/heads/${default_branch}" |
    awk 'NR == 1 {print $1}'
)"

if [[ "$remote_default_before" != "$baseline_default_head" ]]; then
  echo "The approved default branch changed after baseline capture." >&2
  exit 1
fi

if git -C "$checkout" ls-remote --exit-code --heads origin \
  "refs/heads/${branch}" >/dev/null 2>&1; then
  echo "The disposable verification branch already exists." >&2
  exit 1
fi

pushed=false
cleanup() {
  if [[ "$pushed" == true ]]; then
    git -C "$checkout" push --quiet origin \
      ":refs/heads/${branch}" >/dev/null 2>&1 || true
  fi
}
trap cleanup EXIT

tree="$(git -C "$checkout" rev-parse "${baseline_default_head}^{tree}")"
commit_sha="$(
  printf '%s\n' 'Rivet Issue #36 disposable access verification' |
    GIT_AUTHOR_NAME='Rivet verification' \
    GIT_AUTHOR_EMAIL='rivet-verification@invalid.example' \
    GIT_COMMITTER_NAME='Rivet verification' \
    GIT_COMMITTER_EMAIL='rivet-verification@invalid.example' \
    git -C "$checkout" commit-tree "$tree" -p "$baseline_default_head"
)"

git -C "$checkout" push --quiet origin \
  "${commit_sha}:refs/heads/${branch}"
pushed=true

published_head="$(
  git -C "$checkout" ls-remote --exit-code --heads origin \
    "refs/heads/${branch}" |
    awk 'NR == 1 {print $1}'
)"

if [[ "$published_head" != "$commit_sha" ]]; then
  echo "The disposable branch did not publish the expected commit." >&2
  exit 1
fi

git -C "$checkout" push --quiet origin ":refs/heads/${branch}"
pushed=false

if git -C "$checkout" ls-remote --exit-code --heads origin \
  "refs/heads/${branch}" >/dev/null 2>&1; then
  echo "The disposable branch still exists after deletion." >&2
  exit 1
fi

remote_default_after="$(
  git -C "$checkout" ls-remote --exit-code origin \
    "refs/heads/${default_branch}" |
    awk 'NR == 1 {print $1}'
)"
checkout_status="$(
  git -C "$checkout" status --porcelain=v1 --untracked-files=all
)"
current_branch="$(
  git -C "$checkout" symbolic-ref --quiet --short HEAD
)"

if [[ "$remote_default_after" != "$baseline_default_head" ||
      "$current_branch" != "$default_branch" ||
      -n "$checkout_status" ]]; then
  echo "The default branch or approved checkout changed during verification." >&2
  exit 1
fi

hash_value() {
  printf '%s' "$1" | sha256sum | awk '{print $1}'
}

captured_at="$(date -u +%Y-%m-%dT%H:%M:%SZ)"
branch_fingerprint="$(hash_value "$branch")"
temporary_result="$(mktemp "${state_directory}/.issue-36-branch.XXXXXX")"

jq -n \
  --arg captured_at "$captured_at" \
  --arg branch_fingerprint "$branch_fingerprint" \
  --arg commit_sha "$commit_sha" \
  --arg default_head "$baseline_default_head" '
    {
      schemaVersion: 1,
      capturedAtUtc: $captured_at,
      branchFingerprint: $branch_fingerprint,
      disposableCommit: $commit_sha,
      defaultHead: $default_head,
      branchCreated: true,
      branchDeleted: true,
      defaultBranchUnchanged: true,
      checkoutClean: true
    }
  ' >"$temporary_result"

chmod 0600 "$temporary_result"
mv "$temporary_result" "$result"

jq -n \
  --arg captured_at "$captured_at" '
    {
      capturedAtUtc: $captured_at,
      approvedRepositoryVerified: true,
      disposableBranchCreated: true,
      disposableBranchObservedRemotely: true,
      disposableBranchDeleted: true,
      defaultBranchUnchanged: true,
      checkoutClean: true
    }
  '
REMOTE
