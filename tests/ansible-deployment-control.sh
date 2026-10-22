#!/usr/bin/env bash

set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
config_file="${repo_root}/ansible/ansible.cfg"
role_dir="${repo_root}/ansible/roles/deployment_control"
playbook="${repo_root}/tests/fixtures/ansible/deployment-control.yml"

required_defaults=(
  'deployment_control_repository_path: /home/rivet/workspaces/rivet'
  'deployment_control_repository_remote: https://github.com/ahammednibras8/rivet.git'
  'deployment_control_default_branch: main'
  'deployment_control_ansible_core_version: "2.21.3"'
  'deployment_control_community_general_version: "13.4.0"'
  'deployment_control_aws_cli_version: "2.38.1"'
  'deployment_control_aws_cli_sha256: "b11ed416d91f4251da363a17706938eeaf0e520745754c104c0c1890dd8363c7"'
)

for expected in "${required_defaults[@]}"; do
  if ! grep -Fq -- "$expected" "${role_dir}/defaults/main.yml"; then
    echo "Missing deployment control pin: ${expected}" >&2
    exit 1
  fi
done

required_command_policy=(
  'dest: /usr/local/libexec/rivet-deploy'
  'rivet-deploy-plan'
  'rivet-deploy-apply'
  'rivet-aws-session'
  'rivet-infrastructure'
  'rivet ALL=(root) NOPASSWD: /usr/local/bin/rivet-deploy-plan, /usr/local/bin/rivet-deploy-apply'
  'validate: /usr/sbin/visudo -cf %s'
)

for expected in "${required_command_policy[@]}"; do
  if ! grep -Fq -- "$expected" "${role_dir}/tasks/commands.yml"; then
    echo "Missing deployment command policy: ${expected}" >&2
    exit 1
  fi
done

if grep -Eq 'rivet ALL=\(root\) NOPASSWD:[[:space:]]+ALL' \
  "${role_dir}/tasks/commands.yml"; then
  echo 'The deployment role grants broad root access to rivet.' >&2
  exit 1
fi

required_tooling_policy=(
  'ansible-core=={{ deployment_control_ansible_core_version }}'
  'community.general:{{ deployment_control_community_general_version }}'
  'checksum: "sha256:{{ deployment_control_aws_cli_sha256 }}"'
  '/usr/local/bin/aws'
  "('aws-cli/' ~ deployment_control_aws_cli_version)"
)

for expected in "${required_tooling_policy[@]}"; do
  if ! grep -Fq -- "$expected" "${role_dir}/tasks/tooling.yml"; then
    echo "Missing deployment tooling policy: ${expected}" >&2
    exit 1
  fi
done

ANSIBLE_CONFIG="$config_file" \
  ansible-playbook \
    --inventory 'localhost,' \
    --syntax-check \
    "$playbook"

echo 'The cloud deployment control role has pinned tooling and narrow privilege.'
