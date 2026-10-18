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

for command in gh git install jq sha256sum; do
  if ! command -v "$command" >/dev/null 2>&1; then
    echo "A required cloud baseline command is unavailable." >&2
    exit 1
  fi
done

if ! /usr/local/bin/rivet-repository status >/dev/null 2>&1; then
  echo "The approved checkout failed guarded verification." >&2
  exit 1
fi

organization="$(jq -er '.repositories[0].organization' "$manifest")"
repository_id="$(jq -er '.repositories[0].repository_id' "$manifest")"
repository_name="$(jq -er '.repositories[0].expected_name' "$manifest")"
default_branch="$(jq -er '.repositories[0].default_branch' "$manifest")"
checkout="${HOME}/workspaces/organizations/${organization}/${repository_name}"
expected_remote="https://github.com/${organization}/${repository_name}.git"

[[ "$organization" =~ ^[A-Za-z0-9-]+$ ]] || exit 1
[[ "$repository_name" =~ ^[A-Za-z0-9._-]+$ ]] || exit 1

if ! git -C "$checkout" fetch --prune origin >/dev/null 2>&1; then
  echo "The approved repository fetch failed." >&2
  exit 1
fi

metadata="$(
  gh api \
    --method GET \
    --header "Accept: application/vnd.github+json" \
    --header "X-GitHub-Api-Version: 2022-11-28" \
    "repos/${organization}/${repository_name}"
)"

remote_ref="$(
  gh api \
    --method GET \
    --header "Accept: application/vnd.github+json" \
    --header "X-GitHub-Api-Version: 2022-11-28" \
    "repos/${organization}/${repository_name}/git/ref/heads/${default_branch}"
)"

metadata_boundary="$(
  jq \
  --argjson repository_id "$repository_id" \
  --arg organization "$organization" \
  --arg repository_name "$repository_name" \
  --arg default_branch "$default_branch" '
    {
      repositoryIdMatches: (.id == $repository_id),
      ownerMatches: (.owner.login == $organization),
      nameMatches: (.name == $repository_name),
      defaultBranchMatches: (.default_branch == $default_branch),
      notArchived: (.archived == false),
      pullAllowed: (.permissions.pull == true),
      pushAllowed: (.permissions.push == true),
      accountRoleSufficient: (
        .permissions.pull == true and
        .permissions.push == true
      )
    }
  ' <<<"$metadata"
)"

if ! jq -e 'all(.[]; . == true)' <<<"$metadata_boundary" >/dev/null; then
  echo "The effective repository role does not match the pilot boundary." >&2
  jq . <<<"$metadata_boundary" >&2
  exit 1
fi

local_default_head="$(
  git -C "$checkout" rev-parse "refs/remotes/origin/${default_branch}"
)"
remote_default_head="$(jq -er '.object.sha' <<<"$remote_ref")"
current_branch="$(
  git -C "$checkout" symbolic-ref --quiet --short HEAD
)"
origin_url="$(git -C "$checkout" remote get-url origin)"
checkout_status="$(
  git -C "$checkout" status --porcelain=v1 --untracked-files=all
)"

if [[ "$local_default_head" != "$remote_default_head" ||
      "$current_branch" != "$default_branch" ||
      "$origin_url" != "$expected_remote" ||
      -n "$checkout_status" ]]; then
  echo "The default-branch baseline is not stable." >&2
  exit 1
fi

hash_value() {
  printf '%s' "$1" | sha256sum | awk '{print $1}'
}

install -d -m 0700 "$state_directory"

repository_fingerprint="$(
  hash_value "${repository_id}|${organization}|${repository_name}"
)"
branch_fingerprint="$(hash_value "$default_branch")"
checkout_fingerprint="$(hash_value "$checkout")"
captured_at="$(date -u +%Y-%m-%dT%H:%M:%SZ)"
temporary_baseline="$(mktemp "${state_directory}/.issue-36-before.XXXXXX")"

jq -n \
  --arg captured_at "$captured_at" \
  --arg repository_fingerprint "$repository_fingerprint" \
  --arg branch_fingerprint "$branch_fingerprint" \
  --arg checkout_fingerprint "$checkout_fingerprint" \
  --arg default_head "$remote_default_head" \
  '{
    schemaVersion: 1,
    capturedAtUtc: $captured_at,
    repositoryFingerprint: $repository_fingerprint,
    defaultBranchFingerprint: $branch_fingerprint,
    checkoutFingerprint: $checkout_fingerprint,
    defaultHead: $default_head,
    permissions: {
      pull: true,
      push: true
    }
  }' >"$temporary_baseline"

chmod 0600 "$temporary_baseline"
mv "$temporary_baseline" "$baseline"

jq -n \
  --arg captured_at "$captured_at" \
  '{
    capturedAtUtc: $captured_at,
    approvedRepositoryVerified: true,
    fetchSucceeded: true,
    repositoryIdentityRecorded: true,
    defaultBranchIdentityRecorded: true,
    defaultHeadRecorded: true,
    defaultHeadMatchesGitHub: true,
    checkoutClean: true,
    pullAllowed: true,
    issueBranchPushExpected: true,
    accountRoleSufficient: true
  }'
REMOTE
