#!/usr/bin/env bash

set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
readme="${repo_root}/README.md"
runbook="${repo_root}/docs/runbooks/verify-mobile-thread-continuation.md"
evidence="${repo_root}/docs/evidence/issue-8-mobile-thread-continuation.md"

for required_file in "$runbook" "$evidence"; do
  if [[ ! -f "$required_file" ]]; then
    echo "Missing mobile thread-continuation document: ${required_file}" >&2
    exit 1
  fi
done

required_runbook_text=(
  'tests/capture-mobile-thread-continuation-baseline.sh'
  'tests/verify-mobile-thread-continuation.sh'
  "\`RIVET_CONTINUITY_MARKER\` and \`RIVET_CONTINUITY_CONTEXT\`"
  'Do not select **New task**.'
  'complete baseline message prefix with an identical history digest'
  '**Security → Active sessions**'
  'Revoke only that Android account session.'
  'cannot access either the environment or'
  'Do not deregister or relink the cloud environment'
  'issue-8-before.json'
  'issue-8-after.json'
)

for expected in "${required_runbook_text[@]}"; do
  if ! grep -Fq -- "$expected" "$runbook"; then
    echo "Mobile thread-continuation runbook is missing: ${expected}" >&2
    exit 1
  fi
done

required_evidence_text=(
  'Android used mobile data to reopen the existing thread'
  '"sameThread": true'
  '"inputsMatchBaseline": true'
  '"historyPreserved": true'
  '"contextDependentResponseRecorded": true'
  '"before": 3'
  '"after": 6'
  'denied both environment and thread access'
  'without relinking the host'
)

for expected in "${required_evidence_text[@]}"; do
  if ! grep -Fq -- "$expected" "$evidence"; then
    echo "Issue #8 evidence is missing: ${expected}" >&2
    exit 1
  fi
done

if ! grep -Fq -- \
  '[mobile thread-continuation runbook](docs/runbooks/verify-mobile-thread-continuation.md)' \
  "$readme"; then
  echo "README must link to the mobile thread-continuation runbook" >&2
  exit 1
fi

echo "Mobile thread continuation and revocation are documented without sensitive evidence."
