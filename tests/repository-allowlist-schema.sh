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

valid_manifest="${temporary_directory}/repositories.json"
cat >"$valid_manifest" <<'JSON'
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

validation_output="$($validator validate-manifest --manifest "$valid_manifest")"

if [[ "$validation_output" != "Repository allowlist is structurally valid." ]]; then
  echo "A valid repository allowlist must produce only the generic success message" >&2
  exit 1
fi

if grep -Eq 'example-organization|example-repository|private-approval-record' <<<"$validation_output"; then
  echo "Repository allowlist validation must not disclose manifest contents" >&2
  exit 1
fi

expect_rejected() {
  local manifest="$1"
  local description="$2"

  if "$validator" validate-manifest --manifest "$manifest" >/dev/null 2>&1; then
    echo "Repository allowlist validation accepted ${description}" >&2
    exit 1
  fi
}

jq 'del(.repositories[0].repository_id)' \
  "$valid_manifest" >"${temporary_directory}/missing-id.json"
expect_rejected "${temporary_directory}/missing-id.json" "an entry without its immutable repository ID"

jq '.repositories += [.repositories[0]]' \
  "$valid_manifest" >"${temporary_directory}/duplicate-id.json"
expect_rejected "${temporary_directory}/duplicate-id.json" "duplicate repository IDs"

jq '.repositories[0].expected_visibility = "secret"' \
  "$valid_manifest" >"${temporary_directory}/invalid-visibility.json"
expect_rejected "${temporary_directory}/invalid-visibility.json" "an unsupported visibility"

jq '.repositories[0].required_access = "admin"' \
  "$valid_manifest" >"${temporary_directory}/invalid-access.json"
expect_rejected "${temporary_directory}/invalid-access.json" "an unsupported access level"

jq '.repositories[0].expires_on = "2000-01-01"' \
  "$valid_manifest" >"${temporary_directory}/expired.json"
expect_rejected "${temporary_directory}/expired.json" "an expired approval"

jq '.repositories[0].unexpected = true' \
  "$valid_manifest" >"${temporary_directory}/unknown-field.json"
expect_rejected "${temporary_directory}/unknown-field.json" "an unknown repository field"

echo "The private repository allowlist schema fails closed."
