# Onboard GitHub and managed Codex

This runbook reproduces the repository and coding-agent onboarding verified by
Issue #6. It grants one cloud service account read-only access to one approved
GitHub repository, registers that checkout with T3 Code, connects T3's managed
Codex runtime to ChatGPT, and starts a supervised mobile thread.

This procedure does not authorize source changes, pushes, pull requests,
merges, deployments, additional repositories, or additional agent providers.
Those capabilities require a later issue and an explicit credential review.

## Accepted boundary

| Resource | Accepted value |
| --- | --- |
| Host account | Non-root `rivet` service account |
| GitHub owner | `ahammednibras8` |
| Approved repository | `ahammednibras8/rivet` only |
| Checkout | `/home/rivet/workspaces/rivet` |
| GitHub permission | Repository contents, read-only |
| GitHub client | GitHub CLI `2.102.0`, pinned and checksum-verified by Ansible |
| Agent provider | T3-managed Codex connected to `ChatGPT Personal` |
| Managed Codex version | `0.156.1`, selected by the reviewed T3 Code `0.0.45` release |
| First thread mode | Current checkout, Supervised permissions, read-only task |

“Cloud-owned” means the checkout used by T3, its thread database, managed
provider runtime, and credentials are stored and executed on the cloud host.
It does not prohibit the developer from separately owning another checkout or
using the same GitHub or ChatGPT account on a personal device.

## Security boundaries

- Create a fine-grained personal access token, never a classic token.
- Select only `ahammednibras8/rivet` and grant only **Contents: Read-only**.
  GitHub adds read-only metadata access automatically.
- Use a short expiration. The verified initial lifetime is 30 days.
- Never place the token in a command argument, shell history, repository
  file—including an ignored `.env` file—issue, pull request, log, screenshot,
  or chat.
- Store GitHub CLI state only under `/home/rivet/.config/gh`, owned by `rivet`,
  with directory mode `0700` and credential-file mode `0600`.
- Use T3's managed Codex installation and ChatGPT connection. Do not install a
  duplicate global Codex CLI or copy a local Codex authentication cache.
- Never read or publish files in `/home/rivet/.t3/userdata/secrets`. T3 owns
  that directory at mode `0700` and its secret files at mode `0600`.
- Start the first verification thread in **Supervised** mode. Approve only
  read-only inspection commands.
- Human review remains mandatory before every generated pull request is
  merged. Rivet never approves or merges a pull request.

The shell examples expect `RIVET_WORKSPACE_IP`,
`RIVET_WORKSPACE_PUBLIC_IP`, and `RIVET_OPERATOR_SSH_PRIVATE_KEY` from the
[cloud-foundation runbook](provision-cloud-foundation.md). Routine SSH uses the
private Tailscale address while retaining the verified public-address host-key
alias.

## Install the reviewed GitHub CLI

Apply the committed Ansible configuration over private SSH:

```bash
ANSIBLE_CONFIG=ansible/ansible.cfg ansible-playbook \
  --inventory ansible/inventory/hosts.yml \
  --private-key "$RIVET_OPERATOR_SSH_PRIVATE_KEY" \
  --ssh-common-args \
    "-o HostKeyAlias=$RIVET_WORKSPACE_PUBLIC_IP -o StrictHostKeyChecking=yes" \
  ansible/site.yml
```

The `github_cli` role downloads the pinned Linux AMD64 package, verifies its
SHA-256 digest, installs it, verifies the installed version, and maintains the
private GitHub CLI configuration directory. A second full convergence must
report `changed=0`, `unreachable=0`, and `failed=0`.

Inspect the installed package without reading credentials:

```bash
ssh \
  -o "HostKeyAlias=$RIVET_WORKSPACE_PUBLIC_IP" \
  -o StrictHostKeyChecking=yes \
  -i "$RIVET_OPERATOR_SSH_PRIVATE_KEY" \
  "rivet-admin@${RIVET_WORKSPACE_IP}" \
  "sudo -u rivet gh --version | sed -n '1p'; \
  dpkg-query -W gh; \
  sha256sum /var/cache/rivet/github-cli/gh_2.102.0_linux_amd64.deb"
```

Require GitHub CLI `2.102.0` and SHA-256
`7e54a307f90afdc59796c325ec0c49fb09e6c18537727207a8ac7513584ea5b0`.

## Create and store the GitHub credential

In GitHub's fine-grained personal access token settings, select:

- token name `rivet-cloud-read-only`;
- expiration of 30 days;
- resource owner `ahammednibras8`;
- **Only select repositories** with only `rivet` selected; and
- repository permission **Contents: Read-only**, with every other
  configurable permission set to **No access**.

Copy the one-time token value without saving it locally. Open a private SSH
session, switch to the `rivet` account, and capture the token with terminal
echo disabled:

```bash
sudo -iu rivet
read -rsp "GitHub token: " RIVET_GITHUB_TOKEN; echo
printf '%s\n' "$RIVET_GITHUB_TOKEN" |
  gh auth login \
    --hostname github.com \
    --git-protocol https \
    --with-token
unset RIVET_GITHUB_TOKEN
```

Exit the host and clear the trusted device's clipboard. On macOS:

```bash
pbcopy </dev/null
```

Configure Git to ask GitHub CLI for credentials. This stores only a helper
command in `.gitconfig`; it does not duplicate the token:

```bash
sudo -u rivet env HOME=/home/rivet \
  gh auth setup-git --hostname github.com
```

Verify identity, repository visibility, and filesystem modes without printing
the token:

```bash
sudo -u rivet env HOME=/home/rivet gh api user --jq '.login'
sudo -u rivet env HOME=/home/rivet \
  gh api repos/ahammednibras8/rivet \
    --jq '{repository: .full_name, visibility: .visibility, defaultBranch: .default_branch}'
stat -c '%U:%G %a %n' \
  /home/rivet/.config/gh \
  /home/rivet/.config/gh/hosts.yml
```

Require owner `rivet:rivet`, directory mode `0700`, and file mode `0600`.

Prove the token cannot write by sending an incomplete contents request. The
request omits the required content and therefore cannot create a file even if
the credential were accidentally broader:

```bash
if sudo -u rivet env HOME=/home/rivet \
  gh api \
    --method PUT \
    repos/ahammednibras8/rivet/contents/.rivet-permission-probe; then
  echo "ERROR: GitHub unexpectedly accepted the write request" >&2
  exit 1
fi
```

Require HTTP `403` with `Resource not accessible by personal access token`.
HTTP `422` means GitHub reached input validation and does not prove that write
permission is absent; stop and inspect the token's configured permissions.

## Clone and register the approved repository

Create the workspace and clone only the approved repository as `rivet`:

```bash
sudo -u rivet install -d -m 0750 /home/rivet/workspaces
sudo -u rivet env HOME=/home/rivet \
  gh repo clone \
    ahammednibras8/rivet \
    /home/rivet/workspaces/rivet
```

Require the origin URL to contain no token:

```bash
sudo -u rivet \
  git -C /home/rivet/workspaces/rivet remote get-url origin
sudo -u rivet \
  git -C /home/rivet/workspaces/rivet status --short --branch
```

Register the existing checkout with the running T3 service:

```bash
sudo -u rivet env \
  HOME=/home/rivet \
  T3CODE_HOME=/home/rivet/.t3 \
  PATH=/home/rivet/.local/bin:/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin \
  /home/rivet/.local/bin/t3 project add \
    /home/rivet/workspaces/rivet \
    --title Rivet
```

If the project already exists, do not add a duplicate. Confirm that the T3
mobile project list shows **Rivet** under the intended cloud environment.

## Connect managed Codex

Use a trusted T3 desktop or web client because the Android application may
display configured providers without exposing provider-administration
controls:

1. Select the cloud environment before opening provider settings.
2. Open **Settings → Providers → Codex**.
3. Choose **Connect with ChatGPT** and allow T3 to install its managed runtime.
4. Sign in to the approved ChatGPT account and approve plan sharing.
5. If the final localhost callback cannot load, paste its complete URL into
   T3's sign-in panel. Never paste that URL into chat or evidence.
6. Confirm that the cloud environment and Android client show
   `ChatGPT Personal` as the provider.

Do not run `codex login` or copy `~/.codex/auth.json` for this managed flow.
T3 injects the managed access token only into its Codex process and persists
the provider credential in its private server secret store.

Verify only the installation record, executable version, and storage modes:

```bash
sudo -u rivet jq -r .version /home/rivet/.t3/tools/codex/active.json
sudo -u rivet \
  /home/rivet/.t3/tools/codex/0.156.1/bin/codex --version
stat -c '%U:%G %a %n' /home/rivet/.t3/userdata/secrets
find /home/rivet/.t3/userdata/secrets \
  -maxdepth 1 -type f -printf '%m\n' |
  sort -u
```

Require managed version `0.156.1`, directory mode `0700`, and only `0600`
secret-file modes. Never list, read, hash, copy, or publish secret contents.

## Start the supervised mobile thread

From T3 mobile:

1. Select **Rivet** under the cloud environment.
2. Start a new task using **Current checkout**, not **New worktree**.
3. Select the `ChatGPT Personal` Codex provider.
4. Select **Supervised** permissions.
5. Ask the agent to inspect repository documentation, report the cloud
   provider, region, remote-access method, branch, and clean-tree state, and
   explicitly prohibit modifications, branches, commits, and pushes.
6. Approve only read-only commands such as `pwd`, `git status`, `rg`, `sed`,
   and `cat`.

Require a completed turn in the cloud T3 database, the intended provider
instance, `approval-required` runtime mode, the expected branch, no separate
worktree, and no working-tree changes. Evidence may include those metadata
fields and `git status --short --branch`; it must exclude prompts, responses,
account identifiers, tokens, and private repository content.

## Rotate or revoke access

Rotate the GitHub token before expiration or immediately after suspected
exposure:

1. Create a replacement with the same single-repository, read-only boundary.
2. Repeat the hidden-input `gh auth login --with-token` procedure on the cloud
   host.
3. Re-run the identity, repository, filesystem-mode, clone/fetch, and denied
   write checks.
4. Revoke the previous token in GitHub.
5. Confirm the checkout can still fetch and still cannot write.

To remove GitHub access, run `gh auth logout --hostname github.com` as `rivet`,
revoke the fine-grained token in GitHub, and verify authenticated API access
fails. Removing the credential must not delete the checkout.

To remove managed Codex access, disconnect the provider from the selected
cloud environment in T3 provider settings. Confirm new Codex threads cannot
start while the existing thread history remains. Do not manually delete files
from T3's secret store.

## Failure boundaries

| Failure | Safe response |
| --- | --- |
| `gh` reports an authentication error | Check token expiration and repository selection; never broaden access merely to clear the error. |
| Clone succeeds but authenticated API access fails | Public cloning did not prove token access; repeat `gh api user` and the approved-repository query. |
| Denied-write probe returns `422` instead of `403` | Treat write scope as unproven and inspect the token permissions before continuing. |
| Provider appears only on the personal machine | Reopen provider settings after explicitly selecting the cloud environment and reconnect there. |
| Managed Codex files are absent | Use T3's provider installation control; do not install an unreviewed global CLI. |
| Mobile cannot administer providers | Configure the selected cloud environment from a trusted desktop/web client, then consume it from mobile. |
| Thread requests a write during read-only verification | Reject the request and inspect the prompt, project, workspace, branch, and permission mode. |

## Authoritative references

- [GitHub fine-grained personal access tokens](https://docs.github.com/en/authentication/keeping-your-account-and-data-secure/managing-your-personal-access-tokens)
- [GitHub CLI authentication](https://cli.github.com/manual/gh_auth_login)
- [T3 Code 0.0.45 Codex provider](https://github.com/pingdotgg/t3code/blob/v0.0.45/docs/user/providers-codex.md)
- [T3 Code 0.0.45 permission modes](https://github.com/pingdotgg/t3code/blob/v0.0.45/docs/user/permission-modes.md)
- [T3 Code 0.0.45 thread workflow](https://github.com/pingdotgg/t3code/blob/v0.0.45/docs/user/thread-sidebar.md)
- [OpenAI Codex authentication](https://learn.chatgpt.com/docs/auth)
