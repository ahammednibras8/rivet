#!/usr/bin/env bash

set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
script="${repo_root}/infra/tofu/destroy-workspace.sh"

if [[ ! -x "$script" ]]; then
  echo "Workspace destruction tool must be executable: ${script}" >&2
  exit 1
fi

bash -n "$script"

# The dollar signs below are literal policy assertions.
# shellcheck disable=SC2016
required_text=(
  'required_tofu_version="1.13.1"'
  'aws_region="ap-south-1"'
  'instance_name="rivet-workspace"'
  'static_ip_name="rivet-workspace-ip"'
  'key_pair_name="rivet-operator"'
  'budget_name="rivet-monthly-cost"'
  'require_temporary_aws_identity'
  'status --porcelain --untracked-files=no'
  'terraform.tfstate.backup'
  'aws_budgets_budget.workspace'
  'aws_lightsail_instance.workspace'
  'aws_lightsail_instance_public_ports.workspace'
  'aws_lightsail_key_pair.operator'
  'aws_lightsail_static_ip.workspace'
  'aws_lightsail_static_ip_attachment.workspace'
  'tofu -chdir="$tofu_directory" state list'
  'preflight | prepare'
  'evidence_directory="${repository_root}/temp/issue-14"'
  'install -d -m 0700 "$evidence_directory"'
  'Preparation evidence already exists; review or remove it explicitly'
  'Protected preparation directory:'
  'Tracked worktree must be clean before destruction planning'
  'OpenTofu state does not match the exact destruction boundary'
  'Preflight is read-only; no infrastructure was changed.'
)

for expected in "${required_text[@]}"; do
  if ! grep -Fq -- "$expected" "$script"; then
    echo "Workspace destruction preflight is missing: ${expected}" >&2
    exit 1
  fi
done

# The dollar signs below are literal policy assertions.
# shellcheck disable=SC2016
prohibited_text=(
  'tofu destroy'
  'tofu -chdir="$tofu_directory" apply'
  '--auto-approve'
  'state rm'
  'delete-instance'
  'release-static-ip'
  'delete-key-pair'
  'delete-budget'
  'delete-instance-snapshot'
  'delete-auto-snapshot'
  'rm -rf'
  'chmod 777'
)

for prohibited in "${prohibited_text[@]}"; do
  if grep -Fq -- "$prohibited" "$script"; then
    echo "Read-only destruction preflight contains prohibited mutation: ${prohibited}" >&2
    exit 1
  fi
done

echo "The workspace destruction preflight selects exactly six managed resources."
