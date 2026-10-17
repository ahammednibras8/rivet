#!/usr/bin/env bash

set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
validator="${repo_root}/ansible/roles/repository_access/files/rivet-repository-allowlist"

if [[ ! -x "$validator" ]]; then
  echo "Missing executable repository allowlist validator: ${validator}" >&2
  exit 1
fi

temporary_directory="$(mktemp -d)"
trap 'rm -rf "$temporary_directory"' EXIT

manifest="${temporary_directory}/repositories.json"
response="${temporary_directory}/response.json"
calls="${temporary_directory}/gh-calls"
fake_bin="${temporary_directory}/bin"
mkdir -p "$fake_bin"

cat >"$manifest" <<'JSON'
{
  "schema_version": 1,
  "repositories": [
    {
      "organization": "example-organization",
      "repository_id": 123456789,
      "expected_name": "example-repository",
      "default_branch": "main",
      "expected_visibility": "private",
      "required_access": "read",
      "approval_reference": "private-approval-record-001",
      "approved_on": "2026-01-01",
      "expires_on": "2099-12-31"
    }
  ]
}
JSON

cat >"$fake_bin/gh" <<'SH'
#!/usr/bin/env bash
set -euo pipefail
printf '%s\n' "$*" >>"$RIVET_TEST_GH_CALLS"

if [[ "${RIVET_TEST_GH_FAIL:-false}" == "true" ]]; then
  exit 1
fi

if [[ "$*" != *"repos/example-organization/example-repository"* ]]; then
  echo "Unexpected GitHub API endpoint" >&2
  exit 1
fi

cat "$RIVET_TEST_GH_RESPONSE"
SH
chmod +x "$fake_bin/gh"

write_response() {
  local repository_id="$1"
  local organization="$2"
  local name="$3"
  local default_branch="$4"
  local visibility="$5"
  local archived="$6"
  local pull="$7"
  local push="$8"

  jq -n \
    --argjson repository_id "$repository_id" \
    --arg organization "$organization" \
    --arg name "$name" \
    --arg default_branch "$default_branch" \
    --arg visibility "$visibility" \
    --argjson archived "$archived" \
    --argjson pull "$pull" \
    --argjson push "$push" \
    '{
      id: $repository_id,
      owner: {login: $organization},
      name: $name,
      default_branch: $default_branch,
      visibility: $visibility,
      archived: $archived,
      permissions: {pull: $pull, push: $push}
    }' >"$response"
}

run_validator() {
  PATH="${fake_bin}:$PATH" \
    RIVET_TEST_GH_CALLS="$calls" \
    RIVET_TEST_GH_RESPONSE="$response" \
    "$validator" verify --manifest "$manifest"
}

expect_rejected() {
  local description="$1"

  if run_validator >/dev/null 2>&1; then
    echo "Repository allowlist verification accepted ${description}" >&2
    exit 1
  fi
}

write_response 123456789 example-organization example-repository main private false true false
verification_output="$(run_validator)"

if [[ "$verification_output" != "Approved repositories verified." ]]; then
  echo "Successful repository verification must produce only the generic success message" >&2
  exit 1
fi

if grep -Eq 'example-organization|example-repository|private-approval-record' <<<"$verification_output"; then
  echo "Repository verification must not disclose manifest contents" >&2
  exit 1
fi

if [[ "$(wc -l <"$calls" | tr -d ' ')" != "1" ]] ||
   ! grep -Fq 'repos/example-organization/example-repository' "$calls"; then
  echo "Repository verification must query only the exact approved repository" >&2
  exit 1
fi

if grep -Eq '(^|[[:space:]])(/?user/repos|/?orgs/[^/]+/repos|/?repositories)([[:space:]]|$)' "$calls"; then
  echo "Repository verification must never enumerate repositories" >&2
  exit 1
fi

write_response 987654321 example-organization example-repository main private false true false
expect_rejected "a different repository ID"

write_response 123456789 different-organization example-repository main private false true false
expect_rejected "a transferred repository"

write_response 123456789 example-organization renamed-repository main private false true false
expect_rejected "a renamed repository"

write_response 123456789 example-organization example-repository trunk private false true false
expect_rejected "a changed default branch"

write_response 123456789 example-organization example-repository main public false true false
expect_rejected "a visibility change"

write_response 123456789 example-organization example-repository main private true true false
expect_rejected "an archived repository"

write_response 123456789 example-organization example-repository main private false false false
expect_rejected "missing read access"

jq '.repositories[0].required_access = "write"' "$manifest" >"${manifest}.tmp"
mv "${manifest}.tmp" "$manifest"
write_response 123456789 example-organization example-repository main private false true false
expect_rejected "missing write access"

write_response 123456789 example-organization example-repository main private false true true
run_validator >/dev/null

RIVET_TEST_GH_FAIL=true expect_rejected "an unavailable GitHub API"

echo "Repository verification uses immutable identity and fails closed."
