#!/usr/bin/env bash

set -euo pipefail

if (($# != 1)) || [[ ! "$1" =~ ^[1-9][0-9]*$ ]]; then
  echo "Usage: $0 <pull-request-number>" >&2
  exit 1
fi

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
repository="ahammednibras8/rivet"
pull_request_number="$1"
expected_base="main"
expected_head="feature/11-evidence-backed-pr"

for command in gh git gitleaks jq; do
  if ! command -v "$command" >/dev/null 2>&1; then
    echo "Required command is unavailable: ${command}" >&2
    exit 1
  fi
done

pull_request="$({
  gh pr view "$pull_request_number" \
    --repo "$repository" \
    --json \
      number,state,isDraft,baseRefName,headRefName,headRepository,headRepositoryOwner,body,url,files,commits,autoMergeRequest
})"

if ! jq -e \
  --arg repository "$repository" \
  --arg base "$expected_base" \
  --arg head "$expected_head" '
    .state == "OPEN" and
    .isDraft == false and
    .baseRefName == $base and
    .headRefName == $head and
    .headRepository.nameWithOwner == $repository and
    .headRepositoryOwner.login == "ahammednibras8" and
    .autoMergeRequest == null
  ' <<<"$pull_request" >/dev/null; then
  echo "Pull-request identity or review state is invalid." >&2
  jq '{number, state, isDraft, baseRefName, headRefName, headRepository, headRepositoryOwner, autoMergeRequest}' \
    <<<"$pull_request" >&2
  exit 1
fi

body="$(jq -er '.body' <<<"$pull_request")"
required_body_text=(
  'Related: #11'
  '## Declared scope'
  '## Changes'
  '## Risks'
  '## Changed files'
  '## Automated verification'
  '## Manual verification'
  '## Redacted evidence'
  '## Human gate'
  '403'
  'tests/verify-cloud-foundation.sh'
)

for expected in "${required_body_text[@]}"; do
  if [[ "$body" != *"$expected"* ]]; then
    echo "Pull-request body is missing required evidence: ${expected}" >&2
    exit 1
  fi
done

if grep -Eiq '(^|[[:space:]])(fixes|closes|resolves)[[:space:]]+#[0-9]+' <<<"$body"; then
  echo "Pull-request body must use a non-closing issue relationship." >&2
  exit 1
fi

if grep -Eiq \
  '(github_pat_[[:alnum:]_]+|gh[pousr]_[[:alnum:]]+|AKIA[0-9A-Z]{16}|-----BEGIN [A-Z ]*PRIVATE KEY-----|https://login\.tailscale\.com/a/|127\.0\.0\.1:[0-9]+/callback\?code=)' \
  <<<"$body"; then
  echo "Pull-request body contains prohibited authorization or credential material." >&2
  exit 1
fi

temporary_directory="$(mktemp -d)"
trap 'rm -rf "$temporary_directory"' EXIT
chmod 0700 "$temporary_directory"
printf '%s\n' "$body" >"${temporary_directory}/pull-request-body.md"
chmod 0600 "${temporary_directory}/pull-request-body.md"
gitleaks dir \
  --no-banner \
  --no-color \
  --redact \
  "$temporary_directory" >/dev/null

remote_base="refs/remotes/origin/${expected_base}"
remote_head="refs/remotes/origin/${expected_head}"
for reference in "$remote_base" "$remote_head"; do
  if ! git -C "$repo_root" show-ref --verify --quiet "$reference"; then
    echo "Required local remote-tracking reference is unavailable: ${reference}" >&2
    exit 1
  fi
done

expected_files="$(
  git -C "$repo_root" diff --name-only "${remote_base}...${remote_head}" |
    LC_ALL=C sort
)"
actual_files="$(
  jq -r '.files[].path' <<<"$pull_request" |
    LC_ALL=C sort
)"

if [[ "$actual_files" != "$expected_files" ]]; then
  echo "Pull-request changed files do not match the pushed branch." >&2
  diff -u \
    <(printf '%s\n' "$expected_files") \
    <(printf '%s\n' "$actual_files") >&2 || true
  exit 1
fi

expected_commits="$(
  git -C "$repo_root" rev-list --reverse "${remote_base}..${remote_head}"
)"
actual_commits="$(jq -r '.commits[].oid' <<<"$pull_request")"

if [[ "$actual_commits" != "$expected_commits" ]]; then
  echo "Pull-request commit set does not match the pushed branch." >&2
  exit 1
fi

if grep -Eq '(^|/)\.vscode(/|$)|(^|/)\.env($|\.)|\.(pem|key|tfstate|tfplan)$' \
  <<<"$actual_files"; then
  echo "Pull request contains an unrelated or prohibited file." >&2
  exit 1
fi

jq '{
  number,
  state,
  isDraft,
  base: .baseRefName,
  head: .headRefName,
  repository: .headRepository.nameWithOwner,
  autoMergeConfigured: (.autoMergeRequest != null),
  relationshipRecorded: (.body | contains("Related: #11")),
  requiredSectionsRecorded: (
    (.body | contains("## Declared scope")) and
    (.body | contains("## Risks")) and
    (.body | contains("## Changed files")) and
    (.body | contains("## Automated verification")) and
    (.body | contains("## Manual verification")) and
    (.body | contains("## Redacted evidence"))
  ),
  changedFileCount: (.files | length),
  commitCount: (.commits | length),
  url
}' <<<"$pull_request"
