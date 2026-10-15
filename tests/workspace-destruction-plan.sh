#!/usr/bin/env bash

set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
script="${repo_root}/infra/tofu/destroy-workspace.sh"

bash -n "$script"

# Dollar signs in this list are literal product-code assertions.
# shellcheck disable=SC2016
required_text=(
  'preflight | prepare | plan'
  'usage: %s [preflight|prepare|plan|apply]\n'
  'override_file="${tofu_directory}/issue-14_override.tf.json"'
  'plan_file="${evidence_directory}/destroy.tfplan"'
  'plan_json="${evidence_directory}/destroy-plan.json"'
  'plan_record="${evidence_directory}/plan.json"'
  '"prevent_destroy": false'
  'tofu -chdir="$tofu_directory" plan'
  '-destroy'
  '-input=false'
  '-out="$plan_file"'
  'tofu -chdir="$tofu_directory" show -json "$plan_file"'
  'tofu -chdir="$tofu_directory" state pull'
  '.change.actions == ["delete"]'
  'length == 6'
  'stateLineage'
  'stateSerial'
  'planSha256'
  'repositoryCommit'
  'chmod 0600 "$plan_file" "$plan_json" "$plan_record"'
  'Exact destruction plan saved for human review:'
)

for expected in "${required_text[@]}"; do
  if ! grep -Fq -- "$expected" "$script"; then
    echo "Workspace destruction planning is missing: ${expected}" >&2
    exit 1
  fi
done

prohibited_text=(
  'tofu destroy'
  '--auto-approve'
  'state rm'
  'delete-instance-snapshot'
  's3api delete-object'
)

for prohibited in "${prohibited_text[@]}"; do
  if grep -Fq -- "$prohibited" "$script"; then
    echo "Workspace destruction planning contains prohibited behavior: ${prohibited}" >&2
    exit 1
  fi
done

echo "The saved destruction plan is protected and limited to six delete-only changes."
