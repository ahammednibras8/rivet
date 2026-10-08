#!/usr/bin/env bash

set -euo pipefail

repository_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
readonly repository_root
readonly subject="${repository_root}/infra/bootstrap/state-backend.sh"
readonly fake_bin="${repository_root}/tests/fixtures/bin"
test_directory="$(mktemp -d "${TMPDIR:-/tmp}/rivet-state-backend-test.XXXXXX")"
readonly test_directory
trap 'rm -rf "$test_directory"' EXIT

case_output=""
case_status=0
case_log=""
case_number=0
fake_identity='123456789012\tarn:aws:sts::123456789012:assumed-role/RivetOperator/test-session'
fake_aws_status=0
fake_bucket_exists=false
fake_create_status=0
fake_bucket_region=ap-south-1

run_case() {
  local action="$1"
  local confirmation="${2:-}"
  local log_file

  case_number=$((case_number + 1))
  log_file="${test_directory}/aws-${case_number}.log"
  : >"$log_file"

  set +e
  case_output="$(
    PATH="${fake_bin}:/usr/bin:/bin" \
      FAKE_AWS_IDENTITY="$fake_identity" \
      FAKE_AWS_STATUS="$fake_aws_status" \
      FAKE_AWS_LOG="$log_file" \
      FAKE_BUCKET_EXISTS="$fake_bucket_exists" \
      FAKE_CREATE_STATUS="$fake_create_status" \
      FAKE_BUCKET_REGION="$fake_bucket_region" \
      "$subject" "$action" <<<"$confirmation" 2>&1
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

assert_not_contains() {
  local unexpected="$1"

  [[ "$case_output" != *"$unexpected"* ]] ||
    fail "expected output not to contain '${unexpected}', got: ${case_output}"
}

assert_log_contains() {
  local expected="$1"

  [[ "$case_log" == *"$expected"* ]] ||
    fail "expected AWS log to contain '${expected}', got: ${case_log}"
}

assert_log_not_contains() {
  local unexpected="$1"

  [[ "$case_log" != *"$unexpected"* ]] ||
    fail "expected AWS log not to contain '${unexpected}', got: ${case_log}"
}

run_case plan
assert_status 0
assert_contains 'AWS temporary-role preflight passed.'
assert_contains 'Target region: ap-south-1'
assert_contains 'Target state bucket: rivet-tofu-state-123456789012-ap-south-1-an'
assert_contains 'No AWS resources were changed.'
assert_log_not_contains 's3api'

run_case invalid
assert_status 64
assert_contains 'usage:'
[[ -z "$case_log" ]] || fail "invalid action called AWS: ${case_log}"

run_case apply wrong-bucket
assert_status 1
assert_contains 'error: confirmation did not match the target bucket'
assert_log_not_contains 's3api'

run_case apply rivet-tofu-state-123456789012-ap-south-1-an
assert_status 0
assert_contains 'State bucket created.'
assert_contains 'State bucket ownership and region verified.'
assert_log_contains 's3api head-bucket'
assert_log_contains 's3api create-bucket'
assert_log_contains 's3api get-bucket-location'

fake_bucket_exists=true
run_case apply rivet-tofu-state-123456789012-ap-south-1-an
assert_status 0
assert_contains 'State bucket already exists.'
assert_log_not_contains 's3api create-bucket'
assert_log_contains 's3api get-bucket-location'

fake_bucket_exists=false
fake_create_status=73
run_case apply rivet-tofu-state-123456789012-ap-south-1-an
assert_status 73
assert_contains 'simulated bucket collision'
assert_log_not_contains 's3api get-bucket-location'

fake_create_status=0
fake_bucket_exists=true
fake_bucket_region=us-east-1
run_case apply rivet-tofu-state-123456789012-ap-south-1-an
assert_status 1
assert_contains 'error: state bucket exists in unexpected region us-east-1'

fake_bucket_region=ap-south-1
fake_bucket_exists=false
fake_identity='123456789012\tarn:aws:iam::123456789012:user/operator'
run_case plan
assert_status 1
assert_contains 'error: use temporary credentials from an assumed IAM role'

fake_identity='123456789012\tarn:aws:iam::123456789012:root'
run_case plan
assert_status 1
assert_contains 'error: use temporary credentials from an assumed IAM role'

fake_identity='not-an-account\tarn:aws:sts::123456789012:assumed-role/RivetOperator/test-session'
run_case plan
assert_status 1
assert_contains 'error: AWS returned an invalid account ID'

fake_identity=unused
fake_aws_status=42
run_case plan
assert_status 42
assert_contains 'simulated AWS authentication failure'

printf 'state-backend preflight tests passed\n'
