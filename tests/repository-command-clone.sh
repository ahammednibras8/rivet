#!/usr/bin/env bash

set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
source_command="${repo_root}/ansible/roles/repository_access/files/rivet-repository"
temporary_directory="$(mktemp -d)"
trap 'rm -rf "$temporary_directory"' EXIT

manifest="${temporary_directory}/repositories.json"
validator="${temporary_directory}/rivet-repository-allowlist"
workspace="${temporary_directory}/workspaces/organizations"
fake_bin="${temporary_directory}/bin"
test_command="${temporary_directory}/rivet-repository"
calls="${temporary_directory}/calls"

mkdir -p "$fake_bin"

cat >"$manifest" <<'JSON'
{
  "schema_version": 1,
  "repositories": [{
    "organization": "example-organization",
    "repository_id": 123456789,
    "expected_name": "example-repository",
    "default_branch": "main",
    "expected_visibility": "private",
    "required_access": "read",
    "approval_reference": "private-approval-record-001",
    "approved_on": "2026-01-01",
    "expires_on": "2099-12-31"
  }]
}
JSON

cat >"$validator" <<'SH'
#!/usr/bin/env bash
set -euo pipefail
printf 'validator %s\n' "$*" >>"$RIVET_TEST_CALLS"
if [[ "${RIVET_TEST_REJECT:-false}" == "true" ]]; then
  exit 1
fi
echo "Approved repositories verified."
SH
chmod +x "$validator"

cat >"$fake_bin/gh" <<'SH'
#!/usr/bin/env bash
set -euo pipefail
printf 'gh %s\n' "$*" >>"$RIVET_TEST_CALLS"
if [[ "${RIVET_TEST_CLONE_FAIL:-false}" == "true" ]]; then
  mkdir -p "$4"
  exit 1
fi
if [[ "$1 $2 $3" != "repo clone example-organization/example-repository" ]]; then
  echo "Unexpected clone target" >&2
  exit 1
fi
git init --quiet --initial-branch=main "$4"
git -C "$4" remote add origin \
  https://github.com/example-organization/example-repository.git
chmod g+w "$4"
SH
chmod +x "$fake_bin/gh"

sed \
  -e "s|^repository_manifest=.*|repository_manifest=${manifest}|" \
  -e "s|^allowlist_validator=.*|allowlist_validator=${validator}|" \
  -e "s|^organization_workspace=.*|organization_workspace=${workspace}|" \
  "$source_command" >"$test_command"
chmod +x "$test_command"

if ! grep -Fqx "organization_workspace=${workspace}" "$test_command"; then
  echo "The clone test could not isolate the organization workspace" >&2
  exit 1
fi

clone_output="$(
  PATH="${fake_bin}:$PATH" \
    RIVET_TEST_CALLS="$calls" \
    "$test_command" clone
)"

if [[ "$clone_output" != "Approved repository cloned." ]]; then
  echo "The clone operation must return only its generic success result" >&2
  exit 1
fi

if grep -Eq 'example-organization|example-repository|private-approval-record' \
  <<<"$clone_output"; then
  echo "The clone operation must not disclose private approval metadata" >&2
  exit 1
fi

expected_checkout="${workspace}/example-organization/example-repository"
if [[ ! -d "$expected_checkout" ]]; then
  echo "The approved repository must clone into its isolated organization workspace" >&2
  exit 1
fi

if [[ "$(sed -n '1p' "$calls")" != \
    "validator verify --manifest ${manifest}" ]]; then
  echo "The active allowlist must be verified before cloning" >&2
  exit 1
fi

clone_call="$(sed -n '2p' "$calls")"
expected_clone_prefix="gh repo clone example-organization/example-repository ${workspace}/example-organization/.clone."
if [[ "$clone_call" != "${expected_clone_prefix}"*"/checkout -- --branch main --single-branch" ]]; then
  echo "The clone target and default branch must come only from the approved entry" >&2
  exit 1
fi

if find "$expected_checkout" -xdev \
  \( -perm -0020 -o -perm -0002 \) -print -quit |
  grep -q .; then
  echo "Repository clone retained group-writable or world-writable state" >&2
  exit 1
fi

status_output="$(
  PATH="${fake_bin}:$PATH" \
    RIVET_TEST_CALLS="$calls" \
    "$test_command" status
)"

if [[ "$status_output" != "Approved repository checkout is valid." ]]; then
  echo "Repository status must return only its generic success result" >&2
  exit 1
fi

git -C "$expected_checkout" remote set-url origin \
  https://github.com/example-organization/different-repository.git

if PATH="${fake_bin}:$PATH" \
  RIVET_TEST_CALLS="$calls" \
  "$test_command" status >/dev/null 2>&1; then
  echo "Repository status accepted a mismatched remote" >&2
  exit 1
fi

git -C "$expected_checkout" remote set-url origin \
  https://github.com/example-organization/example-repository.git
touch "${expected_checkout}/untracked-file"

if PATH="${fake_bin}:$PATH" \
  RIVET_TEST_CALLS="$calls" \
  "$test_command" status >/dev/null 2>&1; then
  echo "Repository status accepted a dirty checkout" >&2
  exit 1
fi

rm -f "${expected_checkout}/untracked-file"
git -C "$expected_checkout" symbolic-ref HEAD refs/heads/different-branch

if PATH="${fake_bin}:$PATH" \
  RIVET_TEST_CALLS="$calls" \
  "$test_command" status >/dev/null 2>&1; then
  echo "Repository status accepted a different branch" >&2
  exit 1
fi

git -C "$expected_checkout" symbolic-ref HEAD refs/heads/main
chmod g+w "$expected_checkout"

if PATH="${fake_bin}:$PATH" \
  RIVET_TEST_CALLS="$calls" \
  "$test_command" status >/dev/null 2>&1; then
  echo "Repository status accepted group-writable checkout state" >&2
  exit 1
fi

chmod g-w "$expected_checkout"

: >"$calls"
RIVET_TEST_REJECT=true \
  PATH="${fake_bin}:$PATH" \
  RIVET_TEST_CALLS="$calls" \
  "$test_command" clone >/dev/null 2>&1 && {
    echo "A rejected approval must stop before clone" >&2
    exit 1
  }

if grep -q '^gh ' "$calls"; then
  echo "A metadata mismatch reached the clone operation" >&2
  exit 1
fi

rm -rf -- "$expected_checkout"
: >"$calls"
RIVET_TEST_CLONE_FAIL=true \
  PATH="${fake_bin}:$PATH" \
  RIVET_TEST_CALLS="$calls" \
  "$test_command" clone >/dev/null 2>&1 && {
    echo "A failed clone must not report success" >&2
    exit 1
  }

if find "${workspace}/example-organization" \
  -mindepth 1 -maxdepth 1 -name '.clone.*' -print -quit | grep -q .; then
  echo "A failed clone left private staging data behind" >&2
  exit 1
fi

echo "The repository command clones only the live-verified approval."
