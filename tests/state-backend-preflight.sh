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
case_policy_file=""
case_number=0
fake_identity='123456789012\tarn:aws:sts::123456789012:assumed-role/RivetOperator/test-session'
fake_aws_status=0
fake_bucket_exists=false
fake_create_status=0
fake_bucket_region=ap-south-1
fake_fail_operation=""

run_case() {
  local action="$1"
  local confirmation="${2:-}"
  local log_file
  local policy_file

  case_number=$((case_number + 1))
  log_file="${test_directory}/aws-${case_number}.log"
  policy_file="${test_directory}/policy-${case_number}.json"
  : >"$log_file"

  set +e
  case_output="$(
    PATH="${fake_bin}:/usr/bin:/bin" \
      FAKE_AWS_IDENTITY="$fake_identity" \
      FAKE_AWS_STATUS="$fake_aws_status" \
      FAKE_AWS_LOG="$log_file" \
      FAKE_POLICY_FILE="$policy_file" \
      FAKE_BUCKET_EXISTS="$fake_bucket_exists" \
      FAKE_CREATE_STATUS="$fake_create_status" \
      FAKE_BUCKET_REGION="$fake_bucket_region" \
      FAKE_FAIL_OPERATION="$fake_fail_operation" \
      "$subject" "$action" <<<"$confirmation" 2>&1
  )"
  case_status=$?
  set -e

  case_log="$(<"$log_file")"
  case_policy_file="$policy_file"
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

assert_protection_calls() {
  assert_log_contains 's3api put-bucket-ownership-controls'
  assert_log_contains 'ObjectOwnership=BucketOwnerEnforced'
  assert_log_contains 's3api put-public-access-block'
  assert_log_contains 'BlockPublicAcls=true,IgnorePublicAcls=true,BlockPublicPolicy=true,RestrictPublicBuckets=true'
  assert_log_contains 's3api put-bucket-encryption'
  assert_log_contains 'SSEAlgorithm=AES256'
  assert_log_contains 's3api put-bucket-versioning'
  assert_log_contains 'Status=Enabled'
  assert_log_contains 's3api put-bucket-tagging'
  assert_log_contains 'Key=ManagedBy,Value=AWSCLI'
  assert_log_contains 'Key=Phase,Value=phase-1'
  assert_log_contains 'Key=Project,Value=Rivet'
  assert_log_contains 's3api put-bucket-lifecycle-configuration'
  assert_log_contains 'NoncurrentDays=90,NewerNoncurrentVersions=10'
  assert_log_contains 'ExpiredObjectDeleteMarker=true'
  assert_log_contains 's3api put-bucket-policy'
}

assert_bucket_policy() {
  [[ -s "$case_policy_file" ]] || fail 'expected a rendered bucket policy'

  jq -e '
    .Version == "2012-10-17" and
    ([.Statement[] | select(
      .Sid == "DenyInsecureTransport" and
      .Effect == "Deny" and
      .Principal == "*" and
      .Action == "s3:*" and
      .Condition.Bool."aws:SecureTransport" == "false" and
      (.Resource | sort) == ([
        "arn:aws:s3:::rivet-tofu-state-123456789012-ap-south-1-an",
        "arn:aws:s3:::rivet-tofu-state-123456789012-ap-south-1-an/*"
      ] | sort)
    )] | length) == 1 and
    ([.Statement[] | select(
      .Sid == "DenyStateDeletion" and
      .Effect == "Deny" and
      .Principal == "*" and
      (.Action | sort) == (["s3:DeleteObject", "s3:DeleteObjectVersion"] | sort) and
      .Resource == "arn:aws:s3:::rivet-tofu-state-123456789012-ap-south-1-an/phase-1/rivet.tfstate"
    )] | length) == 1 and
    ([.. | strings | select(contains("tflock"))] | length) == 0
  ' "$case_policy_file" >/dev/null || fail 'rendered bucket policy is unsafe'
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
assert_contains 'State bucket protection settings converged.'
assert_protection_calls
assert_bucket_policy

fake_bucket_exists=true
run_case apply rivet-tofu-state-123456789012-ap-south-1-an
assert_status 0
assert_contains 'State bucket already exists.'
assert_log_not_contains 's3api create-bucket'
assert_log_contains 's3api get-bucket-location'
assert_protection_calls
assert_bucket_policy

fake_fail_operation=put-public-access-block
run_case apply rivet-tofu-state-123456789012-ap-south-1-an
assert_status 71
assert_log_contains 's3api put-bucket-ownership-controls'
assert_log_contains 's3api put-public-access-block'
assert_log_not_contains 's3api put-bucket-encryption'
assert_log_not_contains 's3api put-bucket-versioning'
assert_log_not_contains 's3api put-bucket-tagging'

fake_fail_operation=""
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
