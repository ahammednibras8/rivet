#!/usr/bin/env bash

set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
policy_library="${repo_root}/infra/bootstrap/lib/operator-role-policy.sh"

if [[ ! -f "$policy_library" ]]; then
  echo "Missing operator role policy library: ${policy_library}" >&2
  exit 1
fi

# shellcheck source=infra/bootstrap/lib/operator-role-policy.sh
source "$policy_library"

account_id="123456789012"
expected_principal="arn:aws:iam::${account_id}:user/rivet-developer"
trust_policy="$(render_operator_trust_policy "$account_id")"

if ! jq -e \
  --arg principal "$expected_principal" \
  '(
    .Version == "2012-10-17" and
    (.Statement | length) == 1 and
    .Statement[0].Sid == "AllowRivetDeveloper" and
    .Statement[0].Effect == "Allow" and
    .Statement[0].Principal == {"AWS": $principal} and
    .Statement[0].Action == "sts:AssumeRole" and
    (.Statement[0] | has("Condition") | not)
  )' <<<"$trust_policy" >/dev/null; then
  echo "The operator trust policy must allow only rivet-developer to assume the role" >&2
  exit 1
fi

if grep -Fq '"Principal": "*"' <<<"$trust_policy"; then
  echo "The operator trust policy must not contain a wildcard principal" >&2
  exit 1
fi

echo "The operator role trusts only the dedicated Rivet login identity."
