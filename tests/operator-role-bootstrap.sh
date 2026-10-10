#!/usr/bin/env bash

set -euo pipefail

repository_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
readonly repository_root
readonly subject="${repository_root}/infra/bootstrap/operator-role.sh"
readonly fake_bin="${repository_root}/tests/fixtures/bin"
# shellcheck source=infra/bootstrap/lib/operator-role-policy.sh
source "${repository_root}/infra/bootstrap/lib/operator-role-policy.sh"

test_directory="$(mktemp -d "${TMPDIR:-/tmp}/rivet-operator-role-test.XXXXXX")"
readonly test_directory
trap 'rm -rf "$test_directory"' EXIT

case_output=""
case_status=0
case_log=""
case_trust_policy=""
case_user_policy=""
case_state_policy=""
case_identity_policy=""
case_lightsail_policy=""
case_budget_policy=""
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
  local state_policy_file
  local identity_policy_file
  local lightsail_policy_file
  local budget_policy_file

  case_number=$((case_number + 1))
  log_file="${test_directory}/aws-${case_number}.log"
  trust_policy_file="${test_directory}/trust-${case_number}.json"
  user_policy_file="${test_directory}/user-${case_number}.json"
  state_policy_file="${test_directory}/state-${case_number}.json"
  identity_policy_file="${test_directory}/identity-${case_number}.json"
  lightsail_policy_file="${test_directory}/lightsail-${case_number}.json"
  budget_policy_file="${test_directory}/budget-${case_number}.json"
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
      FAKE_STATE_POLICY_FILE="$state_policy_file" \
      FAKE_IDENTITY_POLICY_FILE="$identity_policy_file" \
      FAKE_LIGHTSAIL_POLICY_FILE="$lightsail_policy_file" \
      FAKE_BUDGET_POLICY_FILE="$budget_policy_file" \
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
  case_state_policy=""
  case_identity_policy=""
  case_lightsail_policy=""
  case_budget_policy=""
  [[ ! -s "$state_policy_file" ]] || case_state_policy="$(<"$state_policy_file")"
  [[ ! -s "$identity_policy_file" ]] || case_identity_policy="$(<"$identity_policy_file")"
  [[ ! -s "$lightsail_policy_file" ]] || case_lightsail_policy="$(<"$lightsail_policy_file")"
  [[ ! -s "$budget_policy_file" ]] || case_budget_policy="$(<"$budget_policy_file")"
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
assert_contains 'Operator role permission policies converged.'
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
[[ "$case_log" == *'iam put-role-policy --role-name rivet-operator --policy-name rivet-state-backend'* ]] ||
  fail 'apply did not install the state backend policy'
[[ "$case_log" == *'iam put-role-policy --role-name rivet-operator --policy-name rivet-identity'* ]] ||
  fail 'apply did not install the identity policy'
[[ "$case_log" == *'iam put-role-policy --role-name rivet-operator --policy-name rivet-lightsail'* ]] ||
  fail 'apply did not install the Lightsail policy'
[[ "$case_log" == *'iam put-role-policy --role-name rivet-operator --policy-name rivet-budget'* ]] ||
  fail 'apply did not install the budget policy'
jq -S . <<<"$case_state_policy" >"${test_directory}/actual-state.json"
render_operator_state_policy 123456789012 | jq -S . >"${test_directory}/expected-state.json"
cmp -s "${test_directory}/actual-state.json" "${test_directory}/expected-state.json" ||
  fail 'apply installed an unexpected state backend policy'
jq -S . <<<"$case_identity_policy" >"${test_directory}/actual-identity.json"
render_operator_identity_policy 123456789012 | jq -S . >"${test_directory}/expected-identity.json"
cmp -s "${test_directory}/actual-identity.json" "${test_directory}/expected-identity.json" ||
  fail 'apply installed an unexpected identity policy'
jq -S . <<<"$case_lightsail_policy" >"${test_directory}/actual-lightsail.json"
render_operator_lightsail_policy | jq -S . >"${test_directory}/expected-lightsail.json"
cmp -s "${test_directory}/actual-lightsail.json" "${test_directory}/expected-lightsail.json" ||
  fail 'apply installed an unexpected Lightsail policy'
jq -S . <<<"$case_budget_policy" >"${test_directory}/actual-budget.json"
render_operator_budget_policy 123456789012 | jq -S . >"${test_directory}/expected-budget.json"
cmp -s "${test_directory}/actual-budget.json" "${test_directory}/expected-budget.json" ||
  fail 'apply installed an unexpected budget policy'

fake_existing_role_arn='arn:aws:iam::123456789012:role/rivet-operator'
run_case apply rivet-operator
assert_status 0
assert_contains 'Operator role updated: arn:aws:iam::123456789012:role/rivet-operator'
assert_contains 'Operator role trust boundary converged.'
assert_contains 'Login user assume-role policy converged.'
assert_contains 'Operator role permission policies converged.'
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
[[ "$(rg -c 'iam put-role-policy --role-name rivet-operator' <<<"$case_log")" == "4" ]] ||
  fail 'repeat apply did not converge all four role policies'
fake_existing_role_arn=None

run_case invalid
assert_status 64
assert_contains 'usage:'
[[ -z "$case_log" ]] || fail "invalid action called AWS: ${case_log}"

printf 'operator role bootstrap tests passed\n'
