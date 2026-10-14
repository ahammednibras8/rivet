#!/usr/bin/env bash

set -euo pipefail

if (($# != 2)) || [[ ! "$1" =~ ^(capture|verify)$ ]] ||
  [[ ! "$2" =~ ^[1-9][0-9]*$ ]]; then
  echo "Usage: $0 <capture|verify> <pull-request-number>" >&2
  exit 1
fi

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
repository="ahammednibras8/rivet"
mode="$1"
pull_request_number="$2"
git_directory="$(git -C "$repo_root" rev-parse --git-dir)"
state_directory="${git_directory}/rivet-verification"
baseline="${state_directory}/issue-12-human-merge-boundary.json"

for command in gh jq; do
  if ! command -v "$command" >/dev/null 2>&1; then
    echo "Required command is unavailable: ${command}" >&2
    exit 1
  fi
done

pull_request="$({
  gh pr view "$pull_request_number" \
    --repo "$repository" \
    --json number,state,isDraft,baseRefName,headRefName,body,url,autoMergeRequest
})"
protection="$({
  gh api "repos/${repository}/branches/main/protection" \
    -H 'X-GitHub-Api-Version: 2022-11-28'
})"
blockers="$({
  gh api "repos/${repository}/issues/12/dependencies/blocked_by" \
    -H 'X-GitHub-Api-Version: 2022-11-28'
})"
main_sha="$(
  gh api "repos/${repository}/git/ref/heads/main" \
    -H 'X-GitHub-Api-Version: 2022-11-28' \
    --jq '.object.sha'
)"
deployment_count="$(
  gh api "repos/${repository}/deployments?per_page=100" \
    -H 'X-GitHub-Api-Version: 2022-11-28' \
    --jq 'length'
)"
workflow_count="$(
  gh api "repos/${repository}/actions/workflows?per_page=100" \
    -H 'X-GitHub-Api-Version: 2022-11-28' \
    --jq '.total_count'
)"

if ! jq -e '
  .state == "OPEN" and
  .isDraft == false and
  .baseRefName == "main" and
  .headRefName == "verification/12-human-merge-evidence" and
  .autoMergeRequest == null and
  (.body | contains("Related: #12"))
' <<<"$pull_request" >/dev/null; then
  echo 'Issue #12 pull request crossed or does not express the human gate.' >&2
  jq '{number, state, isDraft, baseRefName, headRefName, autoMergeRequest}' \
    <<<"$pull_request" >&2
  exit 1
fi

if ! jq -e '
  .enforce_admins.enabled == true and
  .required_pull_request_reviews != null and
  .required_conversation_resolution.enabled == true and
  .allow_force_pushes.enabled == false and
  .allow_deletions.enabled == false
' <<<"$protection" >/dev/null; then
  echo 'Default-branch protection does not enforce the human boundary.' >&2
  exit 1
fi

if ! jq -e 'any(.[]; .number == 11 and .state == "closed")' \
  <<<"$blockers" >/dev/null; then
  echo 'Issue #12 must remain blocked by completed Issue #11.' >&2
  exit 1
fi

if [[ "$workflow_count" != 0 ]]; then
  echo "Repository workflows are outside the human boundary: ${workflow_count}" >&2
  exit 1
fi

current="$({
  jq -n \
    --argjson pullRequestNumber "$pull_request_number" \
    --arg mainSha "$main_sha" \
    --argjson deploymentCount "$deployment_count" \
    --arg url "$(jq -r '.url' <<<"$pull_request")" \
    '{
      pullRequestNumber: $pullRequestNumber,
      pullRequestState: "OPEN",
      autoMergeConfigured: false,
      mainSha: $mainSha,
      deploymentCount: $deploymentCount,
      workflowCount: 0,
      url: $url
    }'
})"

if [[ "$mode" == capture ]]; then
  mkdir -p "$state_directory"
  chmod 0700 "$state_directory"
  printf '%s\n' "$current" >"$baseline"
  chmod 0600 "$baseline"
  jq '{
    pullRequestNumber,
    pullRequestState,
    autoMergeConfigured,
    mainRecorded: (.mainSha | length == 40),
    deploymentCount,
    workflowCount,
    baselineStored: true
  }' <<<"$current"
  exit 0
fi

if [[ ! -f "$baseline" ]]; then
  echo "Human merge-boundary baseline is unavailable: ${baseline}" >&2
  exit 1
fi

if ! jq -e --argjson current "$current" '
  .pullRequestNumber == $current.pullRequestNumber and
  .mainSha == $current.mainSha and
  .deploymentCount == $current.deploymentCount
' "$baseline" >/dev/null; then
  echo 'A merge, default-branch update, or deployment occurred after capture.' >&2
  jq -n \
    --slurpfile before "$baseline" \
    --argjson after "$current" \
    '{before: $before[0], after: $after}' >&2
  exit 1
fi

jq '{
  pullRequestNumber,
  pullRequestStillOpen: (.pullRequestState == "OPEN"),
  autoMergeConfigured,
  mainUnchanged: true,
  deploymentCountUnchanged: true,
  workflowCount,
  humanMergeBoundaryPreserved: true
}' <<<"$current"
