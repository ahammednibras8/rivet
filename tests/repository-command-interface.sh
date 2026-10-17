#!/usr/bin/env bash

set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
command_file="${repo_root}/ansible/roles/repository_access/files/rivet-repository"
expected_usage='Usage: rivet-repository {verify|clone|status|register}'

if [[ ! -x "$command_file" ]]; then
  echo "The guarded repository command must be installed from an executable source file" >&2
  exit 1
fi

expect_usage_rejection() {
  local description="$1"
  shift
  local output

  if output="$("$command_file" "$@" 2>&1)"; then
    echo "The repository command accepted ${description}" >&2
    exit 1
  fi

  if [[ "$output" != "$expected_usage" ]]; then
    echo "The repository command must reject ${description} without disclosing metadata" >&2
    exit 1
  fi
}

expect_usage_rejection "a missing operation"
expect_usage_rejection "an arbitrary operation" unlisted
expect_usage_rejection "arbitrary repository input" verify example/repository
expect_usage_rejection "a clone target supplied by the caller" clone example/repository
expect_usage_rejection "a status target supplied by the caller" status example/repository
expect_usage_rejection "a register target supplied by the caller" register example/repository

for required_line in \
  "repository_manifest=/home/rivet/.config/rivet/repositories.json" \
  "allowlist_validator=/usr/local/bin/rivet-repository-allowlist" \
  "cd /" \
  "umask 0027" \
  "exec \"\$allowlist_validator\" verify --manifest \"\$repository_manifest\""; do
  if ! grep -Fq "$required_line" "$command_file"; then
    echo "The verify operation must use only the installed private allowlist" >&2
    exit 1
  fi
done

echo "The repository command exposes a fixed-manifest verification boundary."
