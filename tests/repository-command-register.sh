#!/usr/bin/env bash

set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
source_command="${repo_root}/ansible/roles/repository_access/files/rivet-repository"
temporary_directory="$(mktemp -d)"
trap 'rm -rf "$temporary_directory"' EXIT

manifest="${temporary_directory}/repositories.json"
validator="${temporary_directory}/rivet-repository-allowlist"
workspace_root="${temporary_directory}/workspaces"
organization_workspace="${workspace_root}/organizations"
checkout="${organization_workspace}/example-organization/example-repository"
t3_home="${temporary_directory}/t3"
database="${t3_home}/userdata/state.sqlite"
t3_binary="${temporary_directory}/bin/t3"
test_command="${temporary_directory}/rivet-repository"
calls="${temporary_directory}/t3-calls"

mkdir -p \
  "$(dirname "$checkout")" \
  "$(dirname "$database")" \
  "$(dirname "$t3_binary")"

cat >"$manifest" <<'JSON'
{
  "repositories": [
    {
      "organization": "example-organization",
      "expected_name": "example-repository",
      "default_branch": "main"
    }
  ]
}
JSON

cat >"$validator" <<'SH'
#!/usr/bin/env bash
set -euo pipefail
[[ "$1" == "verify" && "$2" == "--manifest" ]]
SH
chmod +x "$validator"

git init --quiet --initial-branch=main "$checkout"
git -C "$checkout" remote add origin \
  https://github.com/example-organization/example-repository.git
chmod -R g-w,o-w "$checkout"

sqlite3 "$database" <<'SQL'
CREATE TABLE projection_projects (
  project_id TEXT NOT NULL,
  title TEXT NOT NULL,
  workspace_root TEXT NOT NULL,
  deleted_at TEXT
);
SQL

cat >"$t3_binary" <<'SH'
#!/usr/bin/env bash
set -euo pipefail
printf '%s\n' "$*" >>"$RIVET_TEST_CALLS"
[[ "$1 $2" == "project add" ]]
[[ "$3" == "$RIVET_TEST_CHECKOUT" ]]
[[ "$4" == "--title" && "$5" == "example-repository" ]]
sqlite3 "$RIVET_TEST_DATABASE" <<SQL
INSERT INTO projection_projects (
  project_id,
  title,
  workspace_root,
  deleted_at
) VALUES (
  'test-project',
  'example-repository',
  '$RIVET_TEST_CHECKOUT',
  NULL
);
SQL
SH
chmod +x "$t3_binary"

sed \
  -e "s|^repository_manifest=.*|repository_manifest=${manifest}|" \
  -e "s|^allowlist_validator=.*|allowlist_validator=${validator}|" \
  -e "s|^workspace_root=.*|workspace_root=${workspace_root}|" \
  -e "s|^organization_workspace=.*|organization_workspace=${organization_workspace}|" \
  -e "s|^t3_binary=.*|t3_binary=${t3_binary}|" \
  -e "s|^t3_home=.*|t3_home=${t3_home}|" \
  "$source_command" >"$test_command"
chmod +x "$test_command"

register() {
  RIVET_TEST_CALLS="$calls" \
    RIVET_TEST_CHECKOUT="$checkout" \
    RIVET_TEST_DATABASE="$database" \
    "$test_command" register
}

registration_output="$(register)"

if [[ "$registration_output" != \
    "Approved repository project is registered." ]]; then
  echo "Repository registration must return only its generic success result" >&2
  exit 1
fi

if [[ "$(wc -l <"$calls" | tr -d ' ')" != "1" ]]; then
  echo "First registration must invoke T3 exactly once" >&2
  exit 1
fi

if [[ "$(
  sqlite3 "$database" \
    "SELECT COUNT(*) FROM projection_projects WHERE deleted_at IS NULL;"
)" != "1" ]]; then
  echo "First registration must create exactly one active project" >&2
  exit 1
fi

second_output="$(register)"

if [[ "$second_output" != \
    "Approved repository project is registered." ]]; then
  echo "Existing registration must return the generic success result" >&2
  exit 1
fi

if [[ "$(wc -l <"$calls" | tr -d ' ')" != "1" ]]; then
  echo "Existing registration must not invoke T3 again" >&2
  exit 1
fi

sqlite3 "$database" <<SQL
INSERT INTO projection_projects (
  project_id,
  title,
  workspace_root,
  deleted_at
) VALUES (
  'duplicate-project',
  'example-repository',
  '$checkout',
  NULL
);
SQL

if register >/dev/null 2>&1; then
  echo "Repository registration accepted duplicate active projects" >&2
  exit 1
fi

if [[ "$(wc -l <"$calls" | tr -d ' ')" != "1" ]]; then
  echo "Duplicate rejection must happen before invoking T3" >&2
  exit 1
fi

sqlite3 "$database" \
  "DELETE FROM projection_projects WHERE project_id = 'duplicate-project';"
git -C "$checkout" remote set-url origin \
  https://github.com/example-organization/different-repository.git

if register >/dev/null 2>&1; then
  echo "Repository registration accepted an invalid checkout" >&2
  exit 1
fi

if [[ "$(wc -l <"$calls" | tr -d ' ')" != "1" ]]; then
  echo "Checkout rejection must happen before invoking T3" >&2
  exit 1
fi

echo "Repository registration is guarded and idempotent."
