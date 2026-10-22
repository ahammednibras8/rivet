#!/usr/bin/env bash

set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
role_dir="${repo_root}/ansible/roles/deployment_control"
deploy_template="${role_dir}/templates/rivet-deploy.j2"
aws_session="${role_dir}/files/rivet-aws-session"
infrastructure="${role_dir}/files/rivet-infrastructure"

for command_file in \
  "${role_dir}/files/rivet-deploy-plan" \
  "${role_dir}/files/rivet-deploy-apply" \
  "$aws_session" \
  "$infrastructure"; do
  bash -n "$command_file"
done

# These are literal source fragments, not expressions for this test to expand.
# shellcheck disable=SC2016
required_deploy_controls=(
  '[[ "$(id -u)" == 0 ]]'
  'flock -n 9'
  'refs/remotes/origin/${default_branch}^{commit}'
  '"${repository_api}/commits/${default_branch}"'
  '--no-hardlinks'
  '"refs/remotes/origin/${default_branch}:refs/remotes/origin/${default_branch}"'
  'chown -R root:rivet "$staging_directory"'
  'tofu -chdir="$release_directory/infra/tofu" init'
  'tofu -chdir="$release_directory/tests/fixtures/tofu-cloud-init" init'
  'run_ansible "$operator_key" --check --diff'
  'origin/main changed after planning'
  'run_ansible "$operator_key" --diff'
  "\$recap\" == *'changed=0'*"
  "\$recap\" == *'unreachable=0'*"
  "\$recap\" == *'failed=0'*"
)

for expected in "${required_deploy_controls[@]}"; do
  if ! grep -Fq -- "$expected" "$deploy_template"; then
    echo "Missing privileged deployment control: ${expected}" >&2
    exit 1
  fi
done

# shellcheck disable=SC2016
required_aws_controls=(
  'aws login --remote --profile "$login_profile"'
  'unset AWS_ACCESS_KEY_ID AWS_SECRET_ACCESS_KEY AWS_SESSION_TOKEN AWS_PROFILE'
  'user/${expected_user}'
  'assumed-role/rivet-operator/'
  'chmod 0600 "$AWS_CONFIG_FILE"'
  'aws logout --profile "$login_profile"'
)

for expected in "${required_aws_controls[@]}"; do
  if ! grep -Fq -- "$expected" "$aws_session"; then
    echo "Missing temporary AWS session control: ${expected}" >&2
    exit 1
  fi
done

# shellcheck disable=SC2016
required_infrastructure_controls=(
  '/usr/local/bin/rivet-aws-session verify'
  'tofu -chdir="$release_directory/infra/tofu" plan'
  '-out="$plan_file"'
  'tofu -chdir="$release_directory/infra/tofu" apply -input=false "$plan_file"'
  '-detailed-exitcode'
  'the post-apply drift check did not return a clean state'
)

for expected in "${required_infrastructure_controls[@]}"; do
  if ! grep -Fq -- "$expected" "$infrastructure"; then
    echo "Missing cloud infrastructure control: ${expected}" >&2
    exit 1
  fi
done

if grep -ERq -- '(AWS_ACCESS_KEY_ID=|AWS_SECRET_ACCESS_KEY=|--auto-approve|tofu[[:space:]]+destroy)' \
  "$role_dir"; then
  echo 'The deployment controls contain a permanent credential or unsafe apply path.' >&2
  exit 1
fi

echo 'Deployment commands require merged releases, temporary AWS login, and explicit saved-plan apply.'
