#!/usr/bin/env bash

set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
readme="${repo_root}/README.md"
adr="${repo_root}/docs/adr/0008-use-cloud-deployment-control.md"
runbook="${repo_root}/docs/runbooks/deploy-without-the-operator-mac.md"

for required_file in "$adr" "$runbook"; do
  [[ -f "$required_file" ]] || {
    echo "Missing cloud deployment document: ${required_file}" >&2
    exit 1
  }
done

required_runbook_text=(
  'sudo /usr/local/bin/rivet-deploy-plan'
  'sudo /usr/local/bin/rivet-deploy-apply'
  'rivet-aws-session login'
  'rivet-infrastructure plan'
  'rivet-infrastructure show'
  'rivet-infrastructure apply'
  'rivet-aws-session logout'
  'Do not paste the authorization URL or code'
  'No automatic apply occurs after a merge.'
  'root-owned release'
)

for expected in "${required_runbook_text[@]}"; do
  if ! grep -Fq -- "$expected" "$runbook"; then
    echo "Cloud deployment runbook is missing: ${expected}" >&2
    exit 1
  fi
done

# These are literal documentation fragments.
# shellcheck disable=SC2016
required_adr_text=(
  'human-triggered remote execution'
  'root-owned snapshot'
  'short-lived browser login'
  'No push, merge, timer, or webhook starts an apply.'
  'The `rivet` account receives no general-purpose sudo access.'
)

for expected in "${required_adr_text[@]}"; do
  if ! grep -Fq -- "$expected" "$adr"; then
    echo "Cloud deployment ADR is missing: ${expected}" >&2
    exit 1
  fi
done

if ! grep -Fq -- \
  '[laptop-independent deployment runbook](docs/runbooks/deploy-without-the-operator-mac.md)' \
  "$readme"; then
  echo 'README must link to the laptop-independent deployment runbook.' >&2
  exit 1
fi

echo 'Laptop-independent deployment is documented with explicit human gates.'
