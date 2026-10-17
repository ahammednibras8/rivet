# Manage the repository allowlist

This runbook records one human-approved organization repository without
discovering or cloning every repository visible to the operator. The private
manifest is operational state; repository names, IDs, and approval references
must not be committed, copied into issues or pull requests, or included in
published verification evidence.

The authorization decision remains governed by
[ADR-0006](../adr/0006-use-an-individual-fine-grained-token-for-organization-access.md).
The numeric GitHub repository ID is the primary identity. Owner, name, default
branch, visibility, archive state, and effective permission are constraints
that must continue to match that identity.

## Files and ownership

The operator keeps the source manifest outside the repository at:

```text
${XDG_CONFIG_HOME:-$HOME/.config}/rivet/repositories.json
```

The cloud host stores the active manifest at:

```text
/home/rivet/.config/rivet/repositories.json
```

The host directory is `root:rivet` with mode `0750`. The active manifest is
`root:rivet` with mode `0640`. T3 Code and agents run as `rivet`, so they may
read approvals but cannot add, replace, or delete them.

The manifest contains authorization metadata, not a GitHub token. GitHub
credentials remain in the separately protected credential store.

## Preconditions

Before creating an entry:

- a human has named the exact organization repository assigned to the
  operator;
- the operator has manually added that exact repository to the bounded
  fine-grained token;
- any required organization-owner approval is complete;
- the token expiration date is known; and
- the repository is not archived.

An ordinary GitHub login, organization membership, or visibility in the web
interface is not approval for Rivet.

## Resolve exactly one repository

Enter the known owner and repository name. Do not use a repository-list or
search endpoint to discover candidates.

```zsh
read -r "RIVET_APPROVED_OWNER?Exact approved organization: "
read -r "RIVET_APPROVED_REPOSITORY?Exact approved repository name: "
read -rs "RIVET_ORGANIZATION_TOKEN?Approved organization token: "
printf "\n"

metadata_file="$(mktemp)"
chmod 0600 "$metadata_file"

if ! GH_TOKEN="$RIVET_ORGANIZATION_TOKEN" gh api \
  --method GET \
  --header "Accept: application/vnd.github+json" \
  --header "X-GitHub-Api-Version: 2022-11-28" \
  "repos/${RIVET_APPROVED_OWNER}/${RIVET_APPROVED_REPOSITORY}" \
  >"$metadata_file"; then
  unset RIVET_ORGANIZATION_TOKEN
  rm -f "$metadata_file"
  echo "The exact approved repository is unavailable." >&2
  return 1
fi

unset RIVET_ORGANIZATION_TOKEN
```

The request must fail closed when the token is pending, expired, revoked, or
does not include the exact repository. A browser session successfully opening
the repository does not prove that the bounded token can access it.

## Create the private manifest

Record a non-secret approval reference and an expiry no later than the token
expiry or organization approval expiry, whichever occurs first.

```zsh
read -r "RIVET_APPROVAL_REFERENCE?Private approval reference: "
read -r "RIVET_APPROVAL_EXPIRY?Approval expiry in YYYY-MM-DD: "

manifest_directory="${XDG_CONFIG_HOME:-$HOME/.config}/rivet"
manifest="${manifest_directory}/repositories.json"

mkdir -p "$manifest_directory"
chmod 0700 "$manifest_directory"
temporary_manifest="$(mktemp "${manifest_directory}/.repositories.XXXXXX")"

jq -n \
  --arg organization "$(jq -r '.owner.login' "$metadata_file")" \
  --argjson repository_id "$(jq -r '.id' "$metadata_file")" \
  --arg expected_name "$(jq -r '.name' "$metadata_file")" \
  --arg default_branch "$(jq -r '.default_branch' "$metadata_file")" \
  --arg expected_visibility "$(jq -r '.visibility' "$metadata_file")" \
  --arg approval_reference "$RIVET_APPROVAL_REFERENCE" \
  --arg approved_on "$(date -u +%F)" \
  --arg expires_on "$RIVET_APPROVAL_EXPIRY" \
  '{
    schema_version: 1,
    repositories: [{
      organization: $organization,
      repository_id: $repository_id,
      expected_name: $expected_name,
      default_branch: $default_branch,
      expected_visibility: $expected_visibility,
      required_access: "write",
      approval_reference: $approval_reference,
      approved_on: $approved_on,
      expires_on: $expires_on
    }]
  }' >"$temporary_manifest"

chmod 0600 "$temporary_manifest"
mv "$temporary_manifest" "$manifest"
rm -f "$metadata_file"

ansible/roles/repository_access/files/rivet-repository-allowlist \
  validate-manifest \
  --manifest "$manifest"
```

The validator prints only a generic result. Do not print the manifest during
review or attach it as evidence.

## Install after workspace provisioning

After the host is provisioned, converged, and authenticated to GitHub with the
approved token, install the manifest from the operator machine:

```zsh
ANSIBLE_CONFIG=ansible/ansible.cfg ansible-playbook \
  --inventory ansible/inventory/hosts.yml \
  --private-key "$RIVET_OPERATOR_SSH_PRIVATE_KEY" \
  --ssh-common-args="-o HostKeyAlias=$RIVET_WORKSPACE_PUBLIC_IP -o StrictHostKeyChecking=yes" \
  --extra-vars "repository_allowlist_source=$manifest" \
  ansible/install-repository-allowlist.yml
```

The playbook validates the local schema, copies to a private staging file,
verifies current GitHub metadata as `rivet`, and atomically activates the file
only after verification succeeds. A failed lookup or metadata mismatch leaves
the previous active manifest unchanged.

Verify only ownership and mode in operator evidence:

```zsh
ssh \
  -o "HostKeyAlias=$RIVET_WORKSPACE_PUBLIC_IP" \
  -o StrictHostKeyChecking=yes \
  -i "$RIVET_OPERATOR_SSH_PRIVATE_KEY" \
  "rivet-admin@${RIVET_WORKSPACE_IP}" \
  "sudo stat -c '%U:%G %a' /home/rivet/.config/rivet/repositories.json"
```

Expected result:

```text
root:rivet 640
```

## Fail-closed changes

Verification rejects the approval when any of these changes:

- numeric repository ID;
- organization owner;
- repository name;
- default branch;
- visibility;
- archive state;
- required read or write permission; or
- approval expiry.

A repository rename, transfer, visibility change, archival, token restriction,
or expiry requires work to stop. The operator must review the change and
create a new approval; Rivet must not silently rewrite the existing entry.

Adding another repository repeats this exact-repository workflow. Repository
listing is never treated as authorization, and no command may enumerate and
clone every repository visible to the account.
