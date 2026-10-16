# ADR-0006: Use an individual fine-grained token for organization access

- Status: Accepted
- Date: 2026-10-16
- Decision owners: Project maintainer and approving organization owner
- Review trigger: Multiple users, organization-managed automation, unavailable
  fine-grained tokens, or a requirement for short-lived credentials

## Context

Rivet needs to work with organization-owned repositories without receiving a
shared organization SSH key, another employee's token, an administrator token,
or a machine credential. Repository assignments may be communicated
informally, so the operator must manually approve each exact repository before
Rivet can use it. Access through the operator's ordinary GitHub account does
not by itself authorize Rivet to clone every repository that account can see.

The first organization pilot has one developer and a small number of manually
selected repositories. A dedicated GitHub App would add installation,
credential-minting, and lifecycle machinery before that complexity is needed.

## Decision

Rivet will authenticate to approved organization repositories over HTTPS with
one fine-grained personal access token owned by the operator's individual
GitHub identity. The organization owner has approved the token request and can
review or revoke its organization access independently.

GitHub actions performed with this token retain the operator's user
attribution. Rivet will not use an installation token or bot attribution for
the pilot. A future GitHub App may use a user access token when individual
attribution remains required, or an installation token only after the
organization explicitly accepts bot attribution.

The token boundary is:

- resource owner: the approving GitHub organization;
- repository access: only repositories manually approved by the operator;
- lifetime: no more than 90 days;
- Metadata: read-only, as required by GitHub;
- Contents: read and write;
- Issues: read-only;
- Pull requests: read and write; and
- every organization, account, and other repository permission: no access.

Contents write is needed to publish an issue branch. Pull requests write is
needed to open that branch for human review. Neither permission is treated as
authorization to update the default branch, merge, approve, administer,
change workflows, read or write secrets, operate Actions, or deploy.

Before onboarding a repository, the operator must enter its exact
`owner/repository` name and confirm it manually. Rivet must resolve and retain
the immutable GitHub repository ID, reject repositories outside the approved
organization, and fail closed when the name and ID no longer match. Agents
must not add, replace, or remove approved repositories.

The token value must remain outside Git, T3 prompts and threads, shell history,
logs, screenshots, issues, pull requests, and backups. It may be transferred
to the cloud host only through a hidden-input procedure and stored in a
service-owned secret location with mode `0600`. The token must not be installed
on the host until the organization workspace and its isolation controls are
ready for verification.

## Organization approval path

The operator creates the token from their own GitHub account, selects the
organization as resource owner, selects only manually approved repositories,
and requests only the permissions in this decision. When the organization
requires approval, GitHub keeps the request pending and blocks access to its
private resources until an organization owner reviews the requested
repositories, permissions, and expiry under **Organization settings → Personal
access tokens → Pending requests** and approves it.

Approval never grants more than the requested boundary and does not replace
Rivet's repository allowlist, default-branch protection, or negative
permission tests.

## Default-branch boundary

A fine-grained token with Contents write can publish Git references allowed by
the repository's rules. Token scope alone therefore cannot enforce the human
merge boundary. Every approved repository must separately prove that:

- an issue branch can be pushed;
- a direct push to the default branch is rejected;
- the token cannot modify workflow files;
- merge, approval, administration, Actions, secrets, and deployment operations
  are rejected; and
- the default branch and unrelated repositories remain unchanged after each
  negative test.

Rivet must remain in approval-required agent mode until those checks pass.

## Rejected alternatives

### Shared organization or employee credentials

Shared SSH private keys, another employee's token, administrator tokens,
machine credentials, and copied GitHub CLI stores do not preserve individual
attribution and cannot be safely bounded to Rivet. They are prohibited.

### Classic personal access token

A classic token has broader scope semantics and does not provide the selected
repository and organization-approval boundaries required here. It is
prohibited.

### Organization-wide repository selection

Selecting every repository would turn an informal project assignment into
access to unrelated code. Manual approval applies only to the exact repository
currently assigned to the operator.

### GitHub App for the first pilot

A selected-repository GitHub App remains the preferred future design when the
organization wants short-lived tokens, centralized automation, multiple
developers, or bot attribution. It is deferred for the single-developer pilot
because the approved fine-grained token already provides selected repositories,
individual attribution, expiration, and owner-controlled revocation.

## Revocation and rotation

The operator must rotate the token before its 90-day expiry and immediately
after suspected exposure. The organization owner may revoke its organization
access without cooperation from Rivet. Removing a repository from the token is
not sufficient cleanup: Rivet must also remove that repository's checkout,
worktrees, T3 project state, logs, caches, and any approved backups under the
separate offboarding procedure.

Revocation is accepted only after authenticated fetch and push both fail while
unrelated personal access remains unaffected.

A fine-grained personal access token has no Rivet-managed refresh flow. Normal
rotation requires the operator to create a replacement with the same or
narrower boundary, obtain any required organization approval, verify the new
token, replace the stored credential through hidden input, and revoke the old
token. Rivet must never keep both credentials active after the replacement is
verified.

For suspected exposure, the operator must stop GitHub operations, revoke the
token from their GitHub account, remove the stored host credential, and notify
the organization owner. The owner can independently revoke the token's
organization access. Recovery requires a new bounded token; Rivet must not
restore the exposed credential from a backup or copy it from another device.

When a repository assignment or contract ends, Rivet must revoke access first,
then delete the checkout, worktrees, T3 project and thread state, caches,
repository-bearing logs, and every backup the organization authorized. The
operator must record redacted deletion evidence without publishing repository
names, source, credentials, prompts, or private logs.

## Consequences

- Repository changes retain the operator's individual GitHub attribution.
- The organization never shares a private key or privileged credential.
- Adding a project requires a deliberate repository-selection update and a new
  Rivet approval; repository discovery is never authorization.
- The organization can independently revoke the token.
- Token rotation is a recurring manual operation.
- A GitHub App migration remains available if the pilot outgrows this model.

## Verification

Before organization code enters Rivet, verification must record only redacted
results proving:

1. the authenticated GitHub identity is the expected individual account;
2. the token can access every manually approved repository and no tested
   unapproved private repository;
3. effective permissions match this decision;
4. an issue branch can be published while the default branch cannot;
5. prohibited merge, workflow, Actions, secrets, deployment, and
   administration operations fail; and
6. organization-owner revocation prevents subsequent fetch and push.

## References

- [GitHub: Managing requests for personal access tokens in an organization](https://docs.github.com/en/organizations/managing-programmatic-access-to-your-organization/managing-requests-for-personal-access-tokens-in-your-organization)
- [GitHub: Reviewing and revoking personal access tokens in an organization](https://docs.github.com/en/organizations/managing-programmatic-access-to-your-organization/reviewing-and-revoking-personal-access-tokens-in-your-organization)
- [GitHub: Permissions required for fine-grained personal access tokens](https://docs.github.com/en/rest/authentication/permissions-required-for-fine-grained-personal-access-tokens)
