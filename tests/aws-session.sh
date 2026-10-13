#!/usr/bin/env bash

set -euo pipefail

repository_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
readonly repository_root
readonly subject="${repository_root}/infra/bootstrap/lib/aws-session.sh"
readonly fake_bin="${repository_root}/tests/fixtures/bin"

case_output=""
case_status=0
case_log=""
case_number=0

run_root_case() {
  local identity="$1"
  local log_file

  case_number=$((case_number + 1))
  log_file="${TMPDIR:-/tmp}/rivet-aws-session-${case_number}.log"
  : >"$log_file"

  set +e
  case_output="$(
    PATH="${fake_bin}:/usr/bin:/bin" \
      FAKE_AWS_LOG="$log_file" \
      FAKE_AWS_IDENTITY="$identity" \
      bash -c 'source "$1"; require_root_aws_identity ap-south-1' _ "$subject" 2>&1
  )"
  case_status=$?
  set -e

  case_log="$(<"$log_file")"
  rm -f "$log_file"
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

assert_output() {
  local expected="$1"

  [[ "$case_output" == "$expected" ]] ||
    fail "expected output '${expected}', got '${case_output}'"
}

run_root_case '123456789012\tarn:aws:iam::123456789012:root'
assert_status 0
assert_output '123456789012'
[[ "$case_log" == *'sts get-caller-identity --region ap-south-1'* ]] ||
  fail 'expected STS identity lookup'

run_root_case '123456789012\tarn:aws:iam::123456789012:user/rivet-developer'
assert_status 1
assert_output 'error: use the AWS account root login only for IAM bootstrap'

run_root_case '123456789012\tarn:aws:sts::123456789012:assumed-role/rivet-operator/test-session'
assert_status 1
assert_output 'error: use the AWS account root login only for IAM bootstrap'

run_root_case 'not-an-account\tarn:aws:iam::123456789012:root'
assert_status 1
assert_output 'error: AWS returned an invalid account ID'

printf 'AWS session boundary tests passed\n'
