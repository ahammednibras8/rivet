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
case_trust_policy=""
case_user_policy=""
case_number=0
fake_user_arn='arn:aws:iam::123456789012:user/rivet-developer'
fake_role_arn='arn:aws:iam::123456789012:role/rivet-operator'
fake_existing_role_arn=None

run_case() {
  local action="$1"
  local confirmation="${2:-}"
  local log_file
  local trust_policy_file
  local user_policy_file

  case_number=$((case_number + 1))
  log_file="${test_directory}/aws-${case_number}.log"
  trust_policy_file="${test_directory}/trust-${case_number}.json"
  user_policy_file="${test_directory}/user-${case_number}.json"
  : >"$log_file"

  set +e
  case_output="$(
    PATH="${fake_bin}:/usr/bin:/bin" \
      FAKE_AWS_LOG="$log_file" \
      FAKE_AWS_IDENTITY='123456789012\tarn:aws:iam::123456789012:root' \
      FAKE_USER_ARN="$fake_user_arn" \
      FAKE_ROLE_ARN="$fake_role_arn" \
      FAKE_EXISTING_ROLE_ARN="$fake_existing_role_arn" \
      FAKE_TRUST_POLICY_FILE="$trust_policy_file" \
      FAKE_USER_POLICY_FILE="$user_policy_file" \
      "$subject" "$action" <<<"$confirmation" 2>&1
  )"
  case_status=$?
  set -e

  case_log="$(<"$log_file")"
  case_trust_policy=""
  if [[ -s "$trust_policy_file" ]]; then
    case_trust_policy="$(<"$trust_policy_file")"
  fi
  case_user_policy=""
  if [[ -s "$user_policy_file" ]]; then
    case_user_policy="$(<"$user_policy_file")"
  fi
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

run_case apply wrong-role
assert_status 1
assert_contains 'error: confirmation did not match rivet-operator'
[[ "$case_log" != *'iam '* ]] || fail "rejected apply called IAM: ${case_log}"

run_case apply rivet-operator
assert_status 0
assert_contains 'Operator role created: arn:aws:iam::123456789012:role/rivet-operator'
assert_contains 'Operator role trust boundary converged.'
assert_contains 'Login user assume-role policy converged.'
[[ "$case_log" == *'iam get-user --user-name rivet-developer'* ]] ||
  fail 'apply did not verify the login user'
[[ "$case_log" == *'iam list-roles '* ]] || fail 'apply did not inspect existing roles'
[[ "$case_log" == *'iam create-role --role-name rivet-operator'* ]] ||
  fail 'apply did not create the operator role'
[[ "$case_log" == *'--max-session-duration 3600'* ]] ||
  fail 'created role does not have a one-hour session limit'
[[ "$case_log" == *'Key=ManagedBy,Value=AWSCLI'* ]] || fail 'missing ManagedBy role tag'
[[ "$case_log" == *'Key=Project,Value=Rivet'* ]] || fail 'missing Project role tag'
[[ "$case_log" == *'Key=Workspace,Value=primary'* ]] || fail 'missing Workspace role tag'
[[ "$case_log" == *'Key=ManagedBy,Value=AWSCLI Key=Project,Value=Rivet Key=Workspace,Value=primary'* ]] ||
  fail 'role tags must be passed as three separate arguments'
jq -e '
  .Statement == [{
    "Sid": "AllowRivetDeveloper",
    "Effect": "Allow",
    "Principal": {"AWS": "arn:aws:iam::123456789012:user/rivet-developer"},
    "Action": "sts:AssumeRole"
  }]
' <<<"$case_trust_policy" >/dev/null || fail 'apply used an unexpected trust policy'
[[ "$case_log" == *'iam put-user-policy --user-name rivet-developer --policy-name rivet-assume-operator'* ]] ||
  fail 'apply did not install the login user assume-role policy'
jq -e '
  .Statement == [{
    "Sid": "AssumeRivetOperator",
    "Effect": "Allow",
    "Action": "sts:AssumeRole",
    "Resource": "arn:aws:iam::123456789012:role/rivet-operator"
  }]
' <<<"$case_user_policy" >/dev/null || fail 'apply used an unexpected login user policy'

fake_existing_role_arn='arn:aws:iam::123456789012:role/rivet-operator'
run_case apply rivet-operator
assert_status 0
assert_contains 'Operator role updated: arn:aws:iam::123456789012:role/rivet-operator'
assert_contains 'Operator role trust boundary converged.'
assert_contains 'Login user assume-role policy converged.'
[[ "$case_log" == *'iam update-assume-role-policy --role-name rivet-operator'* ]] ||
  fail 'repeat apply did not update the trust policy'
[[ "$case_log" == *'iam update-role --role-name rivet-operator'* ]] ||
  fail 'repeat apply did not update the role settings'
[[ "$case_log" == *'iam tag-role --role-name rivet-operator'* ]] ||
  fail 'repeat apply did not converge the role tags'
[[ "$case_log" == *'Key=ManagedBy,Value=AWSCLI Key=Project,Value=Rivet Key=Workspace,Value=primary'* ]] ||
  fail 'repeat apply must pass three separate role tag arguments'
[[ "$case_log" != *'iam create-role'* ]] || fail 'repeat apply recreated the role'
[[ "$case_log" == *'iam put-user-policy --user-name rivet-developer --policy-name rivet-assume-operator'* ]] ||
  fail 'repeat apply did not converge the login user policy'
fake_existing_role_arn=None

run_case invalid
assert_status 64
assert_contains 'usage:'
[[ -z "$case_log" ]] || fail "invalid action called AWS: ${case_log}"

printf 'operator role bootstrap tests passed\n'
