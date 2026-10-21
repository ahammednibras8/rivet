#!/usr/bin/env bash

set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
readme="${repo_root}/README.md"
runbook="${repo_root}/docs/runbooks/manage-repository-allowlist.md"

if [[ ! -f "$runbook" ]]; then
  echo "Missing repository allowlist runbook" >&2
  exit 1
fi

required_statements=(
  'numeric GitHub repository ID is the primary identity'
  '/home/rivet/.config/rivet/repositories.json'
  "\`root:rivet\` with mode \`0640"
  'cannot add, replace, or delete'
  'Do not use a repository-list or'
  'atomically activates the file'
  'previous active manifest unchanged.'
  'no command may enumerate and'
)

for statement in "${required_statements[@]}"; do
  if ! grep -Fq "$statement" "$runbook"; then
    echo "Repository allowlist runbook is missing: ${statement}" >&2
    exit 1
  fi
done

if grep -Eiq \
  'gh repo list|gh api (user/repos|orgs/[^ ]+/repos|repositories)([[:space:]]|$)' \
  "$runbook"; then
  echo "Repository allowlist documentation must not enumerate visible repositories" >&2
  exit 1
fi

if ! grep -Fq '[organization repository allowlist runbook](docs/runbooks/manage-repository-allowlist.md)' "$readme"; then
  echo "README must link the repository allowlist runbook" >&2
  exit 1
fi

echo "Repository allowlist documentation preserves the private approval boundary."
