#!/usr/bin/env bash

set -euo pipefail

repository_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
readonly repository_root
readonly subject="${repository_root}/infra/bootstrap/operator-role.sh"
readonly fake_bin="${repository_root}/tests/fixtures/bin"

test_directory="$(mktemp -d "${TMPDIR:-/tmp}/rivet-operator-role-test.XXXXXX")"
readonly test_directory
trap 'rm -rf "$test_directory"' EXIT

case_output=""
case_status=0
case_log=""
case_number=0
fake_user_arn='arn:aws:iam::123456789012:user/rivet-developer'
fake_role_arn='arn:aws:iam::123456789012:role/rivet-operator'

run_case() {
  local action="$1"
  local log_file

  case_number=$((case_number + 1))
  log_file="${test_directory}/aws-${case_number}.log"
  : >"$log_file"

  set +e
  case_output="$(
    PATH="${fake_bin}:/usr/bin:/bin" \
      FAKE_AWS_LOG="$log_file" \
      FAKE_AWS_IDENTITY='123456789012\tarn:aws:iam::123456789012:root' \
      FAKE_USER_ARN="$fake_user_arn" \
      FAKE_ROLE_ARN="$fake_role_arn" \
      "$subject" "$action" 2>&1
  )"
  case_status=$?
  set -e

  case_log="$(<"$log_file")"
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

run_case plan
assert_status 0
assert_contains 'AWS root bootstrap preflight passed.'
assert_contains 'Account: 123456789012'
assert_contains 'Login user: rivet-developer'
assert_contains 'Operator role: rivet-operator'
assert_contains 'Plan: ensure rivet-developer can assume the least-privilege rivet-operator role.'
assert_contains 'No AWS resources were changed.'
[[ "$case_log" == *'sts get-caller-identity'* ]] || fail 'expected STS identity lookup'
[[ "$case_log" != *'iam '* ]] || fail "plan mutated or inspected IAM: ${case_log}"

run_case verify
assert_status 0
assert_contains 'Login user verified: arn:aws:iam::123456789012:user/rivet-developer'
assert_contains 'Operator role verified: arn:aws:iam::123456789012:role/rivet-operator'
assert_contains 'Identity bootstrap targets verified.'
assert_contains 'No AWS resources were changed.'
[[ "$case_log" == *'iam get-user --user-name rivet-developer'* ]] ||
  fail 'expected login user lookup'
[[ "$case_log" == *'iam get-role --role-name rivet-operator'* ]] ||
  fail 'expected operator role lookup'
[[ "$case_log" != *'iam create-'* ]] || fail "verify created IAM resources: ${case_log}"
[[ "$case_log" != *'iam update-'* ]] || fail "verify updated IAM resources: ${case_log}"
[[ "$case_log" != *'iam put-'* ]] || fail "verify installed IAM policies: ${case_log}"

fake_user_arn='arn:aws:iam::123456789012:user/another-user'
run_case verify
assert_status 1
assert_contains 'error: AWS returned an unexpected login user ARN'
fake_user_arn='arn:aws:iam::123456789012:user/rivet-developer'

fake_role_arn='arn:aws:iam::123456789012:role/another-role'
run_case verify
assert_status 1
assert_contains 'error: AWS returned an unexpected operator role ARN'
fake_role_arn='arn:aws:iam::123456789012:role/rivet-operator'

run_case invalid
assert_status 64
assert_contains 'usage:'
[[ -z "$case_log" ]] || fail "invalid action called AWS: ${case_log}"

printf 'operator role bootstrap tests passed\n'
