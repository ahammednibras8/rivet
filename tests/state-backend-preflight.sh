#!/usr/bin/env bash

set -euo pipefail

repository_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
readonly repository_root
readonly subject="${repository_root}/infra/bootstrap/state-backend.sh"
readonly fake_bin="${repository_root}/tests/fixtures/bin"

case_output=""
case_status=0

run_case() {
  local identity="$1"
  local fake_status="${2:-0}"

  set +e
  case_output="$(
    PATH="${fake_bin}:/usr/bin:/bin" \
      FAKE_AWS_IDENTITY="$identity" \
      FAKE_AWS_STATUS="$fake_status" \
      "$subject" 2>&1
  )"
  case_status=$?
  set -e
}

fail() {
  printf 'FAIL: %s\n' "$1" >&2
  exit 1
}

assert_status() {
  local expected="$1"

  [[ "$case_status" == "$expected" ]] ||
    fail "expected status ${expected}, got ${case_status}: ${case_output}"
}

assert_contains() {
  local expected="$1"

  [[ "$case_output" == *"$expected"* ]] ||
    fail "expected output to contain '${expected}', got: ${case_output}"
}

run_case '123456789012\tarn:aws:sts::123456789012:assumed-role/RivetOperator/test-session'
assert_status 0
assert_contains 'AWS temporary-role preflight passed.'
assert_contains 'Target region: ap-south-1'
assert_contains 'Target state bucket: rivet-tofu-state-123456789012-ap-south-1'

run_case '123456789012\tarn:aws:iam::123456789012:user/operator'
assert_status 1
assert_contains 'error: use temporary credentials from an assumed IAM role'

run_case '123456789012\tarn:aws:iam::123456789012:root'
assert_status 1
assert_contains 'error: use temporary credentials from an assumed IAM role'

run_case 'not-an-account\tarn:aws:sts::123456789012:assumed-role/RivetOperator/test-session'
assert_status 1
assert_contains 'error: AWS returned an invalid account ID'

run_case 'unused' 42
assert_status 42
assert_contains 'simulated AWS authentication failure'

printf 'state-backend preflight tests passed\n'
