#!/usr/bin/env bash

set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
readme="${repo_root}/Readme.md"
pull_request_template="${repo_root}/.github/pull_request_template.md"

required_readme_text=(
  'Leave the pull request open for human review and merge.'
  'Rivet must not'
  'approve, auto-merge, merge, or deploy it.'
  'no direct pushes to a protected default branch;'
  'no autonomous merge or deployment;'
  'human review before every generated pull request is merged.'
)

for expected in "${required_readme_text[@]}"; do
  if ! grep -Fq -- "$expected" "$readme"; then
    echo "README is missing the human merge boundary: ${expected}" >&2
    exit 1
  fi
done

required_template_text=(
  'This PR remains open for human review and merge.'
  'No automatic merge or deployment is configured.'
)

for expected in "${required_template_text[@]}"; do
  if ! grep -Fq -- "$expected" "$pull_request_template"; then
    echo "Pull-request template is missing the human gate: ${expected}" >&2
    exit 1
  fi
done

if [[ -d "${repo_root}/.github/workflows" ]] &&
  find "${repo_root}/.github/workflows" -type f -print -quit | grep -q .; then
  echo 'GitHub workflow files are outside the Rivet human-merge boundary.' >&2
  exit 1
fi

automation_paths=()
for candidate in ansible infra; do
  if [[ -e "${repo_root}/${candidate}" ]]; then
    automation_paths+=("${repo_root}/${candidate}")
  fi
done

prohibited_patterns=(
  'gh[[:space:]]+pr[[:space:]]+merge'
  'gh[[:space:]]+pr[[:space:]]+review[[:space:]]+--approve'
  'gh[[:space:]]+pr[[:space:]]+merge.*--auto'
  'git[[:space:]]+push[^#\n]*([[:space:]]|:)main([[:space:]]|$)'
  '/pulls/[^/[:space:]]+/merge'
  '/repos/[^[:space:]]+/deployments'
  'workflow_dispatch'
  'pull_request_target'
)

for pattern in "${prohibited_patterns[@]}"; do
  if grep -RIEq --exclude-dir=.terraform -- "$pattern" "${automation_paths[@]}"; then
    echo "Rivet automation contains a prohibited merge or deployment path: ${pattern}" >&2
    exit 1
  fi
done

echo 'Rivet exposes no merge, approval, deployment, or direct-main automation path.'
