#!/usr/bin/env bash

set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
script="${repo_root}/infra/bootstrap/workspace-destroy-role.sh"
fixtures="${repo_root}/tests/fixtures/bin"
test_directory="$(mktemp -d "${TMPDIR:-/tmp}/rivet-destroy-role-test.XXXXXX")"

cleanup() {
  rm -f \
    "${test_directory}/aws.log" \
    "${test_directory}/destroy-policy.json" \
    "${test_directory}/plan.stderr"
  rmdir "$test_directory" 2>/dev/null || true
}
trap cleanup EXIT

if [[ ! -x "$script" ]]; then
  echo "Temporary workspace-destroy role tool must be executable: ${script}" >&2
  exit 1
fi

bash -n "$script"

run_tool() {
  PATH="${fixtures}:$PATH" \
    FAKE_AWS_LOG="${test_directory}/aws.log" \
    FAKE_AWS_IDENTITY=$'123456789012\tarn:aws:iam::123456789012:root' \
    FAKE_STATIC_IP_ARN='arn:aws:lightsail:ap-south-1:123456789012:StaticIp/11111111-2222-3333-4444-555555555555' \
    FAKE_DESTROY_POLICY_FILE="${test_directory}/destroy-policy.json" \
    "$script" "$@"
}

if ! plan_output="$(run_tool plan 2>"${test_directory}/plan.stderr")"; then
  echo "Workspace-destroy IAM plan failed" >&2
  exit 1
fi

if [[ -s "${test_directory}/plan.stderr" ]]; then
  echo "Workspace-destroy IAM plan wrote unexpected stderr" >&2
  cat "${test_directory}/plan.stderr" >&2
  exit 1
fi

required_output=(
  'AWS root IAM preflight passed.'
  'Operator role: rivet-operator'
  'Temporary policy: rivet-workspace-destroy'
  'Static IP: rivet-workspace-ip'
  'Retained backup deletion: denied'
  'State backend deletion: denied'
  'No AWS resources were changed.'
)

for expected in "${required_output[@]}"; do
  if ! grep -Fq -- "$expected" <<<"$plan_output"; then
    echo "Workspace-destroy IAM plan is missing: ${expected}" >&2
    exit 1
  fi
done

if ! grep -Fxq \
  'lightsail get-static-ip --static-ip-name rivet-workspace-ip --region ap-south-1 --query staticIp.arn --output text' \
  "${test_directory}/aws.log"; then
  echo "Workspace-destroy IAM plan did not resolve the exact static IP ARN" >&2
  exit 1
fi

if grep -Eq '(put-role-policy|delete-role-policy|delete-instance|release-static-ip|delete-budget|put-object)' \
  "${test_directory}/aws.log"; then
  echo "Workspace-destroy IAM plan performed a mutation" >&2
  exit 1
fi

if invalid_output="$(run_tool unsupported 2>&1)"; then
  echo "Workspace-destroy IAM tool accepted an unsupported action" >&2
  exit 1
fi

if ! grep -Fq 'usage:' <<<"$invalid_output" ||
  ! grep -Fq '[plan|apply|verify|revoke]' <<<"$invalid_output"; then
  echo "Workspace-destroy IAM tool did not explain its supported action" >&2
  exit 1
fi

rm -f "${test_directory}/aws.log"
if printf 'wrong confirmation\n' | run_tool apply >/dev/null 2>&1; then
  echo "Workspace-destroy IAM tool accepted an invalid authorization confirmation" >&2
  exit 1
fi

if [[ -e "${test_directory}/destroy-policy.json" ]] ||
  grep -Fq 'iam put-role-policy' "${test_directory}/aws.log"; then
  echo "Invalid authorization confirmation changed IAM" >&2
  exit 1
fi

rm -f "${test_directory}/aws.log"
apply_output="$(printf 'AUTHORIZE rivet-workspace DESTROY POLICY\n' | run_tool apply)"

if ! grep -Fq 'Temporary destroy policy installed and verified.' <<<"$apply_output";
then
  echo "Workspace-destroy IAM apply did not report verified installation" >&2
  exit 1
fi

if [[ ! -s "${test_directory}/destroy-policy.json" ]] ||
  ! grep -Fq 'iam put-role-policy --role-name rivet-operator --policy-name rivet-workspace-destroy' \
    "${test_directory}/aws.log"; then
  echo "Workspace-destroy IAM apply did not install its exact inline policy" >&2
  exit 1
fi

verify_output="$(run_tool verify)"
if ! grep -Fq 'Temporary destroy policy matches the reviewed boundary.' \
  <<<"$verify_output"; then
  echo "Workspace-destroy IAM verify did not compare the installed policy" >&2
  exit 1
fi

if printf 'wrong confirmation\n' | run_tool revoke >/dev/null 2>&1; then
  echo "Workspace-destroy IAM tool accepted an invalid revocation confirmation" >&2
  exit 1
fi

revoke_output="$(printf 'REVOKE rivet-workspace DESTROY POLICY\n' | run_tool revoke)"
if ! grep -Fq 'Temporary destroy policy revoked.' <<<"$revoke_output" ||
  [[ -e "${test_directory}/destroy-policy.json" ]]; then
  echo "Workspace-destroy IAM revoke did not remove the temporary policy" >&2
  exit 1
fi

echo "The workspace-destroy IAM policy is planned, installed, verified, and revoked safely."
