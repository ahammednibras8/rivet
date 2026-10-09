# Provision the Rivet cloud foundation

This runbook provisions the AWS resources and Ubuntu baseline tracked by
Issue #3. Run it from the repository root on a trusted control node. It does
not install T3 Code, configure GitHub or agent credentials, create backups, or
destroy resources.

Provisioning creates paid AWS resources. A human must review every plan and
explicitly approve each apply. Never run these commands from automation.

## Required access and tools

Use a short-lived AWS session for an assumed IAM role that is authorized to
manage the in-scope Lightsail resources, the Rivet state bucket, and the
account budget. IAM users, the root user, and long-lived access keys are
rejected by the bootstrap scripts.

The supported control-node toolchain is:

- OpenTofu 1.13.1;
- AWS CLI v2;
- Python 3 with `venv` support;
- `jq`, ShellCheck, Gitleaks, Git, OpenSSH, and `curl`;
- Ansible Core 2.21.3; and
- `community.general` 13.4.0.

Create an isolated Python environment and install the pinned Ansible
dependencies:

```bash
python3 -m venv .venv
source .venv/bin/activate
python -m pip install --upgrade pip
python -m pip install --requirement ansible/requirements.txt
ansible-galaxy collection install --requirements-file ansible/requirements.yml
```

Verify every required executable before using AWS:

```bash
tofu version
aws --version
jq --version
shellcheck --version
gitleaks version
ansible --version
ansible-galaxy collection list community.general
```

Stop unless OpenTofu reports `1.13.1`, the AWS CLI reports major version 2,
Ansible Core reports `2.21.3`, and `community.general` reports `13.4.0`.

## Start a temporary AWS session

Authenticate using the account's approved identity-provider or role workflow.
For an AWS Login profile backed by existing console access, use:

```bash
export AWS_PROFILE="YOUR_APPROVED_PROFILE"
aws login --profile "$AWS_PROFILE"
aws sts get-caller-identity --region ap-south-1
```

For an AWS IAM Identity Center profile, use:

```bash
export AWS_PROFILE="YOUR_APPROVED_PROFILE"
aws sso login --profile "$AWS_PROFILE"
aws sts get-caller-identity --region ap-south-1
```

The returned ARN must contain `:assumed-role/`. An AWS Login profile can issue
temporary credentials while still identifying its principal as an IAM user;
that is not sufficient. Configure and select an operator-role profile whose
source is the login profile before continuing. Do not continue with a root or
IAM-user ARN. The bootstrap scripts repeat this check and stop on failure.

## Prepare runtime inputs

Use an existing RSA SSH key dedicated to Rivet, or create one outside the
repository:

```bash
ssh-keygen -t rsa -b 4096 -f "$HOME/.ssh/rivet_operator_rsa" -C rivet-operator
chmod 600 "$HOME/.ssh/rivet_operator_rsa"
```

Set the runtime values in the current shell. The private key itself is never
passed to OpenTofu, Ansible, or Git.

```bash
export RIVET_OPERATOR_SSH_PRIVATE_KEY="$HOME/.ssh/rivet_operator_rsa"
export RIVET_OPERATOR_SSH_PUBLIC_KEY="$(<"${RIVET_OPERATOR_SSH_PRIVATE_KEY}.pub")"
export RIVET_OPERATOR_IPV4_CIDR="$(curl --fail --silent --show-error https://checkip.amazonaws.com | tr -d '[:space:]')/32"
printf 'Budget notification email: '
IFS= read -r RIVET_BUDGET_NOTIFICATION_EMAIL

export TF_VAR_operator_ssh_public_key="$RIVET_OPERATOR_SSH_PUBLIC_KEY"
export TF_VAR_operator_ipv4_cidr="$RIVET_OPERATOR_IPV4_CIDR"
export TF_VAR_budget_notification_email="$RIVET_BUDGET_NOTIFICATION_EMAIL"
unset RIVET_BUDGET_NOTIFICATION_EMAIL
```

Confirm that the CIDR is the control node's current public IPv4 address with a
`/32` suffix. If the address changes, create and review a new OpenTofu plan
before attempting SSH or Ansible again.

Do not place these values in a committed `.tfvars` file. The budget email and
all identifiers in later command output must be redacted before publishing
verification evidence.

## Bootstrap the protected state backend

Preview the deterministic bucket target. This command is read-only:

```bash
infra/bootstrap/state-backend.sh plan
```

Review the operator-role ARN, region, and bucket name in the output. If all
three are correct, run the apply command and type the exact bucket name when
prompted:

```bash
infra/bootstrap/state-backend.sh apply
```

This is the first human approval gate. The script creates or converges only
the account-regional state bucket, then verifies ownership, region, encryption,
versioning, public-access blocking, lifecycle retention, tags, TLS enforcement,
and its role-scoped policy.

Re-run the read-only verification and initialize OpenTofu:

```bash
infra/bootstrap/state-backend.sh verify
infra/bootstrap/init-tofu-backend.sh
```

If initialization reports local state, stop. Review and migrate that state;
never delete it merely to make initialization pass.

## Run static verification

Run the complete local gate before planning any paid resource:

```bash
tests/verify-cloud-foundation.sh
```

It must finish with `Cloud foundation static verification passed.` The gate
formats and validates both OpenTofu configurations, runs their tests, checks
all shell and Ansible policies, and scans Git history and the worktree for
secrets and prohibited files.

## Create and review a saved plan

Create a saved plan from the exact commit being reviewed:

```bash
git status --short
git rev-parse HEAD
tofu -chdir=infra/tofu plan -input=false -out=tfplan
tofu -chdir=infra/tofu show -no-color tfplan
```

The working tree must contain no unexpected file. The plan must contain only:

- one Lightsail key pair named `rivet-operator`;
- one Ubuntu 24.04 x86-64 `medium_3_0` instance named `rivet-workspace` in
  `ap-south-1a`;
- one attached static IPv4 address named `rivet-workspace-ip`;
- one Lightsail firewall policy allowing TCP port 22 only from the supplied
  IPv4 `/32` address, with no IPv6, HTTP, HTTPS, or T3 listener;
- one account-wide USD 30 monthly budget with the accepted notifications; and
- the tags `ManagedBy=OpenTofu`, `Project=Rivet`, and `Workspace=primary`.

The saved `tfplan` file is ignored by Git but may contain private identifiers.
Do not commit or publish it. Delete it later using the operating system's
recoverable trash facility.

## Apply the reviewed plan

Stop here until a human has inspected the complete saved-plan output and
confirmed that it contains only the actions above. Then apply that exact saved
plan; do not create a new implicit plan:

```bash
tofu -chdir=infra/tofu apply -input=false tfplan
```

This is the second human approval gate and begins paid AWS usage.

Export the resulting connection values without copying them into a file:

```bash
export RIVET_WORKSPACE_IP="$(tofu -chdir=infra/tofu output -raw workspace_ipv4_address)"
test "$(tofu -chdir=infra/tofu output -raw workspace_instance_name)" = rivet-workspace
test "$(tofu -chdir=infra/tofu output -raw workspace_ssh_user)" = rivet-admin
```

## Verify AWS resource state

Verify the backend again, then inspect the instance, firewall, static address,
and budget through read-only AWS APIs:

```bash
infra/bootstrap/state-backend.sh verify

aws lightsail get-instance \
  --region ap-south-1 \
  --instance-name rivet-workspace \
  --query 'instance.{state:state.name,zone:location.availabilityZone,blueprint:blueprintId,bundle:bundleId,hardware:hardware,staticIp:isStaticIp,ipType:ipAddressType,tags:tags}'

aws lightsail get-instance-port-states \
  --region ap-south-1 \
  --instance-name rivet-workspace

aws lightsail get-static-ip \
  --region ap-south-1 \
  --static-ip-name rivet-workspace-ip \
  --query 'staticIp.{attachedTo:attachedTo,isAttached:isAttached,ipAddress:ipAddress}'

aws budgets describe-budget \
  --account-id "$(aws sts get-caller-identity --query Account --output text)" \
  --budget-name rivet-monthly-cost

aws budgets describe-notifications-for-budget \
  --account-id "$(aws sts get-caller-identity --query Account --output text)" \
  --budget-name rivet-monthly-cost

tofu -chdir=infra/tofu state list
```

Confirm the values match the reviewed plan and that the only public firewall
entry is TCP port 22 from `RIVET_OPERATOR_IPV4_CIDR`.

## Trust the SSH host key

Obtain the ED25519 fingerprint witnessed by the authenticated Lightsail API,
then compare it with the key presented over the network:

```bash
expected_host_fingerprint="$(
  aws lightsail get-instance-access-details \
    --region ap-south-1 \
    --instance-name rivet-workspace \
    --protocol ssh \
    --query "accessDetails.hostKeys[?algorithm=='ssh-ed25519'].fingerprintSHA256 | [0]" \
    --output text
)"

host_key_line="$(ssh-keyscan -T 10 -t ed25519 "$RIVET_WORKSPACE_IP" 2>/dev/null)"
observed_host_fingerprint="$(
  printf '%s\n' "$host_key_line" | ssh-keygen -E sha256 -lf - | awk '{print $2}'
)"

printf 'AWS-witnessed: %s\nNetwork-presented: %s\n' \
  "$expected_host_fingerprint" \
  "$observed_host_fingerprint"
test "$expected_host_fingerprint" = "$observed_host_fingerprint"
```

Do not continue if the comparison fails or either value is empty. After a
successful comparison, add the already-verified key to the control node:

```bash
install -d -m 700 "$HOME/.ssh"
printf '%s\n' "$host_key_line" >>"$HOME/.ssh/known_hosts"
chmod 600 "$HOME/.ssh/known_hosts"
```

## Converge the Ubuntu baseline

First confirm the cloud-init bridge completed:

```bash
ssh \
  -i "$RIVET_OPERATOR_SSH_PRIVATE_KEY" \
  "rivet-admin@${RIVET_WORKSPACE_IP}" \
  'cloud-init status --wait --long'
```

Preview the Ansible convergence. Review every predicted change:

```bash
ANSIBLE_CONFIG=ansible/ansible.cfg ansible-playbook \
  --inventory ansible/inventory/hosts.yml \
  --private-key "$RIVET_OPERATOR_SSH_PRIVATE_KEY" \
  --check \
  --diff \
  ansible/site.yml
```

After human review, perform the real convergence:

```bash
ANSIBLE_CONFIG=ansible/ansible.cfg ansible-playbook \
  --inventory ansible/inventory/hosts.yml \
  --private-key "$RIVET_OPERATOR_SSH_PRIVATE_KEY" \
  --diff \
  ansible/site.yml
```

Run the same command again without `--diff`. The second play recap must report
`changed=0`, `unreachable=0`, and `failed=0`:

```bash
ANSIBLE_CONFIG=ansible/ansible.cfg ansible-playbook \
  --inventory ansible/inventory/hosts.yml \
  --private-key "$RIVET_OPERATOR_SSH_PRIVATE_KEY" \
  ansible/site.yml
```

## Verify no infrastructure drift

Run a fresh plan without saving it and preserve OpenTofu's detailed exit code:

```bash
set +e
tofu -chdir=infra/tofu plan -input=false -detailed-exitcode
drift_exit_code=$?
set -e
test "$drift_exit_code" -eq 0
```

Exit code `0` means no drift. Exit code `2` means OpenTofu found changes; do
not apply them until their cause is understood and a new saved plan receives
human approval. Any other nonzero value is an execution failure.

## Record redacted evidence

Attach a concise summary to the implementation pull request containing:

- the reviewed Git commit and OpenTofu plan resource counts;
- successful backend verification;
- the instance's region, image, bundle, disk, and running state;
- the firewall rule shape with addresses redacted;
- confirmation that all three budget notifications exist;
- the first Ansible recap and the second run's `changed=0` recap;
- the no-drift plan's exit code `0`; and
- the paid-resource inventory and expected monthly base cost.

Never publish account IDs, ARNs, email addresses, public or private IP
addresses, SSH keys, state, saved plans, environment values, or unredacted
logs.

## Recover an interrupted run

Do not destroy or recreate resources to recover from an interruption. Restore
the temporary AWS session and runtime environment variables, then run:

```bash
infra/bootstrap/state-backend.sh verify
infra/bootstrap/init-tofu-backend.sh
tests/verify-cloud-foundation.sh
tofu -chdir=infra/tofu plan -input=false
```

If OpenTofu reports no unintended change, re-establish the verified SSH host
key and rerun Ansible. Both the backend bootstrap and Ansible baseline are
idempotent. Resource destruction requires a separate reviewed procedure and
explicit approval; it is intentionally absent from this runbook.

## Authoritative references

- [ADR-0001: AWS Lightsail cloud foundation](../adr/0001-phase-1-cloud-foundation.md)
- [ADR-0004: OpenTofu and Ansible automation](../adr/0004-use-opentofu-and-ansible-for-phase-1-automation.md)
- [AWS Lightsail SSH key and connection behavior](https://docs.aws.amazon.com/lightsail/latest/userguide/understanding-ssh-in-amazon-lightsail.html)
- [AWS CLI `get-instance-access-details`](https://docs.aws.amazon.com/cli/latest/reference/lightsail/get-instance-access-details.html)
- [AWS CLI Login temporary credentials](https://docs.aws.amazon.com/cli/latest/userguide/cli-configure-sign-in.html)
- [AWS CLI role profiles](https://docs.aws.amazon.com/cli/latest/userguide/cli-configure-role.html)
- [OpenTofu plan command](https://opentofu.org/docs/cli/commands/plan/)
- [Ansible check and diff mode](https://docs.ansible.com/ansible/latest/playbook_guide/playbooks_checkmode.html)
