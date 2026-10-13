#!/usr/bin/env bash

set -euo pipefail

repository_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
readonly repository_root
readonly source_subject="${repository_root}/infra/bootstrap/init-tofu-backend.sh"
readonly source_session_library="${repository_root}/infra/bootstrap/lib/aws-session.sh"
readonly fake_bin="${repository_root}/tests/fixtures/bin"
jq_directory="$(dirname "$(command -v jq)")"
readonly jq_directory
temporary_parent="${TMPDIR:-/tmp}"
readonly temporary_parent
test_directory="$(mktemp -d "${temporary_parent%/}/rivet-tofu-init-test.XXXXXX")"
readonly test_directory
trap 'rm -rf "$test_directory"' EXIT

readonly copied_repository="${test_directory}/repository"
readonly copied_bootstrap="${copied_repository}/infra/bootstrap"
readonly copied_tofu="${copied_repository}/infra/tofu"
readonly subject="${copied_bootstrap}/init-tofu-backend.sh"

mkdir -p "${copied_bootstrap}/lib" "$copied_tofu"
cp "$source_subject" "$subject"
cp "$source_session_library" "${copied_bootstrap}/lib/aws-session.sh"
chmod +x "$subject"

case_output=""
case_status=0
case_aws_log=""
case_tofu_log=""
case_number=0
fake_tofu_version=1.13.1
fake_aws_status=0

run_case() {
  local aws_log
  local tofu_log

  case_number=$((case_number + 1))
  aws_log="${test_directory}/aws-${case_number}.log"
  tofu_log="${test_directory}/tofu-${case_number}.log"
  : >"$aws_log"
  : >"$tofu_log"

  set +e
  case_output="$(
    PATH="${fake_bin}:${jq_directory}:/usr/bin:/bin" \
      FAKE_AWS_LOG="$aws_log" \
      FAKE_AWS_IDENTITY='123456789012\tarn:aws:sts::123456789012:assumed-role/rivet-operator/test-session' \
      FAKE_AWS_STATUS="$fake_aws_status" \
      FAKE_ROLE_ARN='arn:aws:iam::123456789012:role/rivet-operator' \
      FAKE_TOFU_LOG="$tofu_log" \
      FAKE_TOFU_VERSION="$fake_tofu_version" \
      FAKE_TOFU_DIRECTORY="$copied_tofu" \
      "$subject" 2>&1
  )"
  case_status=$?
  set -e

  case_aws_log="$(<"$aws_log")"
  case_tofu_log="$(<"$tofu_log")"
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

assert_output_contains() {
  local expected="$1"

  [[ "$case_output" == *"$expected"* ]] ||
    fail "expected output to contain '${expected}', got: ${case_output}"
}

assert_tofu_log_contains() {
  local expected="$1"

  [[ "$case_tofu_log" == *"$expected"* ]] ||
    fail "expected OpenTofu log to contain '${expected}', got: ${case_tofu_log}"
}

assert_tofu_log_not_contains() {
  local unexpected="$1"

  [[ "$case_tofu_log" != *"$unexpected"* ]] ||
    fail "expected OpenTofu log not to contain '${unexpected}', got: ${case_tofu_log}"
}

run_case
assert_status 0
assert_output_contains 'Operator role: arn:aws:iam::123456789012:role/rivet-operator'
assert_output_contains 'Initializing backend bucket: rivet-tofu-state-123456789012-ap-south-1-an'
assert_output_contains 'OpenTofu backend initialized.'
[[ "$case_aws_log" == *'sts get-caller-identity'* ]] || fail 'expected STS identity lookup'
[[ "$case_aws_log" == *'iam get-role --role-name rivet-operator'* ]] || fail 'expected IAM role lookup'
[[ "$case_aws_log" != *'s3api'* ]] || fail 'backend initialization unexpectedly mutated S3'
assert_tofu_log_contains 'version -json'
assert_tofu_log_contains "-chdir=${copied_tofu} init -input=false -reconfigure -backend-config=bucket=rivet-tofu-state-123456789012-ap-south-1-an"

fake_tofu_version=1.12.0
run_case
assert_status 1
assert_output_contains 'error: OpenTofu 1.13.1 is required; found 1.12.0'
[[ -z "$case_aws_log" ]] || fail "version failure called AWS: ${case_aws_log}"
assert_tofu_log_not_contains ' init '

fake_tofu_version=1.13.1
: >"${copied_tofu}/terraform.tfstate"
run_case
assert_status 1
assert_output_contains 'error: local state exists; review migration before initializing S3'
[[ -z "$case_aws_log" ]] || fail "local-state failure called AWS: ${case_aws_log}"
assert_tofu_log_not_contains ' init '
rm "${copied_tofu}/terraform.tfstate"

fake_aws_status=42
run_case
assert_status 42
assert_output_contains 'simulated AWS authentication failure'
assert_tofu_log_not_contains ' init '

printf 'tofu backend initialization tests passed\n'
