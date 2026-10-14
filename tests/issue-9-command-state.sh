#!/usr/bin/env bash

set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
fixture="${repo_root}/tests/fixtures/issue-9/command-state.sh"
temporary_directory="$(mktemp -d)"
trap 'rm -rf "$temporary_directory"' EXIT

if [[ ! -x "$fixture" ]]; then
  echo "Issue #9 command-state fixture must be executable: ${fixture}" >&2
  exit 1
fi

"$fixture" success \
  >"${temporary_directory}/success.stdout" \
  2>"${temporary_directory}/success.stderr"

set +e
"$fixture" failure \
  >"${temporary_directory}/failure.stdout" \
  2>"${temporary_directory}/failure.stderr"
failure_status=$?
set -e

if [[ "$failure_status" -ne 23 ]]; then
  echo "Issue #9 intentional failure returned ${failure_status}, expected 23." >&2
  exit 1
fi

expected_files=(
  'success.stdout:issue-9 stdout mode=success'
  'success.stderr:issue-9 stderr mode=success'
  'failure.stdout:issue-9 stdout mode=failure'
  'failure.stderr:issue-9 stderr mode=failure'
)

for expectation in "${expected_files[@]}"; do
  file="${expectation%%:*}"
  expected="${expectation#*:}"
  if [[ "$(<"${temporary_directory}/${file}")" != "$expected" ]]; then
    echo "Unexpected Issue #9 output in ${file}." >&2
    exit 1
  fi
done

echo "Issue #9 command-state fixture preserves deterministic success and failure results."
