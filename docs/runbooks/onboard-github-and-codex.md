# Onboard GitHub and standalone Codex

This runbook retains the repository onboarding verified by Issue #6 and applies
the provider decision in ADR-0007. It grants one cloud service account
read-only access to one approved GitHub repository, registers that checkout
with T3 Code, authenticates the Ansible-installed standalone Codex CLI, and
selects its existing login in a supervised mobile thread.

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
| Agent provider | T3 existing-CLI instance named `Standalone Codex` |
| Codex CLI | `0.163.0`, pinned and checksum-verified by Ansible |
| Codex binary | `/usr/local/bin/codex` |
| Codex home | `/home/rivet/.codex`, file credential mode |
| First thread mode | Current checkout, Supervised permissions, read-only task |

“Cloud-owned” means the checkout used by T3, its thread database, standalone
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
- Use only the Ansible-owned standalone Codex CLI at `/usr/local/bin/codex` for
  T3's existing-CLI provider. Do not use a package-manager or installer-script
  duplicate, and do not copy a Codex authentication cache from another host.
- Ansible may create only the empty protected `/home/rivet/.codex` directory.
  Authentication is a later human action as `rivet`; never automate it or
  access credential contents.
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

## Install the reviewed CLIs

Apply the committed Ansible configuration over private SSH:

```bash
ANSIBLE_CONFIG=ansible/ansible.cfg ansible-playbook \
  --inventory ansible/inventory/hosts.yml \
  --private-key "$RIVET_OPERATOR_SSH_PRIVATE_KEY" \
  --ssh-common-args \
    "-o HostKeyAlias=$RIVET_WORKSPACE_PUBLIC_IP -o StrictHostKeyChecking=yes" \
  ansible/site.yml
```

The `github_cli` and `codex_cli` roles download pinned Linux AMD64 artifacts,
verify their SHA-256 digests, install them in root-owned locations, and verify
their versions as `rivet`. The Codex role prepares only the empty private
configuration directory; it does not perform authentication. A second full
convergence must report `changed=0`, `unreachable=0`, and `failed=0`.

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

Inspect the standalone Codex installation without authenticating or accessing
credential files:

```bash
sudo -u rivet env \
  HOME=/home/rivet \
  CODEX_HOME=/home/rivet/.codex \
  PATH=/home/rivet/.local/bin:/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin \
  codex --version
readlink -f /usr/local/bin/codex
stat -c '%U:%G %a %n' \
  /opt/rivet/codex-cli/0.163.0/bin/codex \
  /opt/rivet/codex-cli/0.163.0/bin/codex-code-mode-host \
  /usr/local/bin/codex \
  /home/rivet/.codex
sha256sum \
  /var/cache/rivet/codex-cli/codex-package-x86_64-unknown-linux-musl.tar.gz
```

Require `codex-cli 0.163.0`, a stable link resolving into the versioned
root-owned installation, CLI and code-mode-host executable mode `0755`, Codex home owner
`rivet:rivet` and mode `0700`, and archive SHA-256
`582646c6bf0561eb0de540f7fc85b9121b0091a826bc6e96830b7f1722122182`.

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

## Authenticate the standalone Codex CLI

Perform this checkpoint only after both Ansible convergences pass. Use a
private interactive terminal; do not capture its transcript. The reviewed
headless-host credential mode is `file`, which lets Codex refresh and reuse its
own login across T3 service restarts and host reboots without a desktop
keyring.

Create only the non-secret credential-mode configuration as `rivet`:

```bash
sudo -u rivet install -m 0600 /dev/null /home/rivet/.codex/config.toml
sudo -u rivet tee /home/rivet/.codex/config.toml >/dev/null <<'EOF'
cli_auth_credentials_store = "file"
EOF
```

Then enter a login shell for `rivet` and run OpenAI's preferred device flow for
a headless machine:

```bash
sudo -iu rivet
export HOME=/home/rivet
export CODEX_HOME=/home/rivet/.codex
export PATH=/home/rivet/.local/bin:/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin
umask 077
codex login --device-auth
if codex login status >/dev/null; then
  echo "Codex login status: authenticated"
else
  echo "ERROR: Codex login status failed" >&2
  exit 1
fi
exit
```

Open the displayed address on a trusted device, sign in to the approved
ChatGPT account, and enter the one-time code. The address and code are secrets
for this procedure: never paste them into T3, chat, evidence, an issue, a pull
request, a command argument, or shell history. Do not use an API key, Codex
access token, copied `auth.json`, or T3-managed token for this provider.

Verify only status and filesystem metadata; never read, print, copy, or hash
the authentication file:

```bash
sudo -u rivet env \
  HOME=/home/rivet \
  CODEX_HOME=/home/rivet/.codex \
  PATH=/home/rivet/.local/bin:/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin \
  codex login status >/dev/null
sudo -u rivet grep -Fqx \
  'cli_auth_credentials_store = "file"' \
  /home/rivet/.codex/config.toml
stat -c '%U:%G %a %n' \
  /home/rivet/.codex \
  /home/rivet/.codex/config.toml \
  /home/rivet/.codex/auth.json
```

Require successful status, the exact reviewed file-mode setting, owner
`rivet:rivet`, directory mode `0700`, and file mode `0600`. Stop if the mode
setting differs or any path is group- or world-accessible.

## Select T3's existing-CLI provider

Use a trusted T3 desktop or web client because the Android application may
display configured providers without exposing provider-administration
controls. Keep the current managed instance intact until all standalone
acceptance checks pass:

1. Select the cloud environment before opening provider settings.
2. Open **Settings → Providers** and choose **Add provider**.
3. Select **Codex**, then choose **Configure manually** rather than
   **Continue with ChatGPT**.
4. Set the label to `Standalone Codex` and the instance ID to
   `codex_standalone`.
5. Set **Binary path** to `/usr/local/bin/codex`.
6. Set **CODEX_HOME path** to `/home/rivet/.codex`.
7. Leave **Shadow home path** empty and add the instance.
8. Require the provider card to report an authenticated installed CLI at
   version `0.163.0` with no compatibility warning.
9. In the new thread's model picker, explicitly select `Standalone Codex`.

This is T3's existing-login mode. T3 launches the Ansible-owned executable and
lets that CLI use and refresh its own login; it must not install a managed
runtime for this instance or copy its managed provider token into the process.

## Start the supervised mobile thread

From T3 mobile:

1. Select **Rivet** under the cloud environment.
2. Start a new task using **Current checkout**, not **New worktree**.
3. Select the `Standalone Codex` provider. Do not accept the managed Codex
   default if the picker retained it from an earlier thread.
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

## Verify refresh and restart persistence

Keep all evidence redacted. Record labels such as `initial turn`, `after one
hour`, `after T3 restart`, and `after host reboot`; do not record thread IDs,
account identifiers, authorization addresses, provider secrets, prompts, or
responses.

1. Complete one supervised turn with `Standalone Codex` and confirm T3 records
   provider instance `codex_standalone` and Codex version `0.163.0`.
2. Keep the same thread idle until more than 60 minutes have elapsed from the
   initial successful turn, then send another read-only request. Require it to
   complete without a new login or a T3 service restart.
3. At a scheduled checkpoint with no active turn, restart `t3code.service` by
   following the T3 operations procedure. Reopen the same project and confirm
   a new read-only turn succeeds through `codex_standalone` without login.
4. At a separately approved maintenance checkpoint, reboot the host by
   following the reboot-recovery runbook. After T3 reconnects, require
   `codex login status` to succeed with output suppressed and another
   `codex_standalone` turn to complete without login.
5. Re-run the worktree and history secret scans before publishing evidence.

Failure at any checkpoint stops acceptance. Do not restart T3 merely to clear
an expired-token error, silently select the managed provider, broaden the
credential mode, or copy an authentication cache.

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

To rotate standalone Codex access, run `codex logout` and then
`codex login --device-auth` in the same protected `rivet` login shell. Verify
status with output suppressed, then start a new supervised
`codex_standalone` turn. Never retain the old login, copy the authentication
file, or include the authorization exchange in evidence.

## Roll back to the retained managed provider

If standalone verification fails, stop new work on `codex_standalone` and use
the retained managed provider; do not alter credentials while a turn is
running:

1. In a new supervised thread, select the previously verified managed Codex
   instance from the model picker and complete a read-only turn.
2. In **Settings → Providers**, disable or remove only the
   `codex_standalone` instance. Keep existing thread history.
3. If the standalone login is being retired, enter the protected `rivet`
   shell and run `codex logout`. Do not manually edit or remove `auth.json`.
4. Revert the standalone-Codex deployment commit through the normal reviewed
   Git workflow and converge Ansible twice.
5. After the reverted configuration is active, remove only these now-unmanaged
   root-owned paths:

   ```bash
   sudo rm -f -- /usr/local/bin/codex
   sudo rm -rf -- /opt/rivet/codex-cli /var/cache/rivet/codex-cli
   sudo -u rivet rmdir --ignore-fail-on-non-empty /home/rivet/.codex
   ```

6. Confirm the managed provider works, `/usr/local/bin/codex` is absent, and
   the standalone provider no longer appears in a new thread's picker.

Do not disconnect or delete the retained managed provider until the full
standalone acceptance gate has passed and the rollback window is explicitly
closed.

## Failure boundaries

| Failure | Safe response |
| --- | --- |
| `gh` reports an authentication error | Check token expiration and repository selection; never broaden access merely to clear the error. |
| Clone succeeds but authenticated API access fails | Public cloning did not prove token access; repeat `gh api user` and the approved-repository query. |
| Denied-write probe returns `422` instead of `403` | Treat write scope as unproven and inspect the token permissions before continuing. |
| Provider appears only on the personal machine | Reopen provider settings after explicitly selecting the cloud environment and reconnect there. |
| T3 cannot find Codex | Require `/usr/local/bin/codex`, the explicit provider binary path, and `/usr/local/bin` in the T3 service `PATH`; do not use an installer script or package-manager duplicate. |
| `codex login status` fails | Stop provider setup and repeat the human device login as `rivet`; do not copy credentials or switch to an API key merely to clear the error. |
| T3 reports an unsupported Codex version | Reapply the reviewed Ansible pin and reject the provider until it reports `0.163.0`; do not use T3's update control. |
| A post-hour turn fails but restart makes it work | Treat standalone acceptance as failed and preserve only redacted diagnostics; do not call restart a credential-refresh solution. |
| Mobile cannot administer providers | Configure the selected cloud environment from a trusted desktop/web client, then consume it from mobile. |
| Thread requests a write during read-only verification | Reject the request and inspect the prompt, project, workspace, branch, and permission mode. |

## Authoritative references

- [GitHub fine-grained personal access tokens](https://docs.github.com/en/authentication/keeping-your-account-and-data-secure/managing-your-personal-access-tokens)
- [GitHub CLI authentication](https://cli.github.com/manual/gh_auth_login)
- [ADR-0007: standalone Codex CLI](../adr/0007-use-standalone-codex-cli.md)
- [T3 Code 0.1.0 Codex provider](https://github.com/pingdotgg/t3code/blob/v0.1.0/docs/user/providers-codex.md)
- [T3 Code 0.1.0 provider installation](https://github.com/pingdotgg/t3code/blob/v0.1.0/docs/user/install.md#providers)
- [T3 Code 0.1.0 permission modes](https://github.com/pingdotgg/t3code/blob/v0.1.0/docs/user/permission-modes.md)
- [T3 Code 0.1.0 thread workflow](https://github.com/pingdotgg/t3code/blob/v0.1.0/docs/user/thread-sidebar.md)
- [OpenAI Codex CLI](https://learn.chatgpt.com/docs/codex/cli)
- [OpenAI Codex authentication](https://learn.chatgpt.com/docs/auth)
- [OpenAI Codex `rust-v0.163.0` release](https://github.com/openai/codex/releases/tag/rust-v0.163.0)
