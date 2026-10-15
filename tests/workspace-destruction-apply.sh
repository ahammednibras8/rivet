#!/usr/bin/env bash

set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
script="${repo_root}/infra/tofu/destroy-workspace.sh"

bash -n "$script"

# Dollar signs in this list are literal product-code assertions.
# shellcheck disable=SC2016
required_text=(
  'preflight | prepare | plan | apply'
  'usage: %s [preflight|prepare|plan|apply]\n'
  'DESTROY rivet-workspace rivet-workspace-ip rivet-operator rivet-monthly-cost'
  'git -C "$repository_root" rev-parse HEAD'
  'shasum -a 256 "$plan_file"'
  'shasum -a 256 "${evidence_directory}/canary.json"'
  'shasum -a 256 "${evidence_directory}/snapshot.json"'
  'tofu -chdir="$tofu_directory" state pull'
  'current_state_lineage'
  'current_state_serial'
  '.change.actions == ["delete"]'
  'aws s3api head-object'
  'aws s3api get-object-tagging'
  'aws lightsail get-instance-snapshot'
  'tofu -chdir="$tofu_directory" apply'
  '-input=false'
  '"$plan_file"'
  'Reviewed destruction plan applied.'
)

for expected in "${required_text[@]}"; do
  if ! grep -Fq -- "$expected" "$script"; then
    echo "Workspace destruction execution is missing: ${expected}" >&2
    exit 1
  fi
done

prohibited_text=(
  'tofu destroy'
  '--auto-approve'
  'state rm'
  'delete-instance-snapshot'
  's3api delete-object'
  'delete-role'
)

for prohibited in "${prohibited_text[@]}"; do
  if grep -Fq -- "$prohibited" "$script"; then
    echo "Workspace destruction execution contains prohibited behavior: ${prohibited}" >&2
    exit 1
  fi
done

echo "Destruction can apply only the unchanged, reviewed, saved plan after typed confirmation."
