#!/usr/bin/env bash

set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

tofu -chdir="${repo_root}/infra/tofu" fmt -check -diff
tofu -chdir="${repo_root}/infra/tofu" validate
tofu -chdir="${repo_root}/infra/tofu" test -no-color

tofu -chdir="${repo_root}/tests/fixtures/tofu-cloud-init" fmt -check -diff
tofu -chdir="${repo_root}/tests/fixtures/tofu-cloud-init" validate
tofu -chdir="${repo_root}/tests/fixtures/tofu-cloud-init" test -no-color

git -C "${repo_root}" ls-files -z \
  '*.sh' \
  'tests/fixtures/bin/aws' \
  'tests/fixtures/bin/tofu' |
  xargs -0 shellcheck -x

"${repo_root}/tests/tofu-backend-init.sh"
"${repo_root}/tests/tofu-network-policy.sh"
"${repo_root}/tests/state-backend-preflight.sh"
"${repo_root}/tests/aws-session.sh"
"${repo_root}/tests/operator-role-policy.sh"
"${repo_root}/tests/operator-role-bootstrap.sh"
"${repo_root}/tests/ansible-version-pin.sh"
"${repo_root}/tests/ansible-github-cli-version-pin.sh"
"${repo_root}/tests/ansible-github-cli-install.sh"
"${repo_root}/tests/ansible-t3-code-version-pin.sh"
"${repo_root}/tests/ansible-t3-code-layout.sh"
"${repo_root}/tests/ansible-t3-code-packages.sh"
"${repo_root}/tests/ansible-t3-code-download.sh"
"${repo_root}/tests/ansible-t3-code-extraction.sh"
"${repo_root}/tests/ansible-t3-code-link.sh"
"${repo_root}/tests/ansible-t3-code-linger.sh"
"${repo_root}/tests/ansible-t3-code-service-install.sh"
"${repo_root}/tests/ansible-t3-code-loopback.sh"
"${repo_root}/tests/ansible-t3-code-service-state.sh"
"${repo_root}/tests/ansible-collection-pin.sh"
"${repo_root}/tests/ansible-config.sh"
"${repo_root}/tests/ansible-inventory.sh"
"${repo_root}/tests/ansible-platform-guard.sh"
"${repo_root}/tests/ansible-package-policy.sh"
"${repo_root}/tests/ansible-update-policy.sh"
"${repo_root}/tests/ansible-user-policy.sh"
"${repo_root}/tests/ansible-ssh-key-policy.sh"
"${repo_root}/tests/ssh-hardening-policy.sh"
"${repo_root}/tests/ansible-ssh-role.sh"
"${repo_root}/tests/ansible-tailscale-role.sh"
"${repo_root}/tests/ansible-firewall-policy.sh"
"${repo_root}/tests/ansible-site.sh"
"${repo_root}/tests/github-codex-onboarding-docs.sh"
"${repo_root}/tests/laptop-independent-baseline-policy.sh"
"${repo_root}/tests/laptop-independent-operation-docs.sh"
"${repo_root}/tests/mobile-thread-continuation-policy.sh"
"${repo_root}/tests/mobile-thread-continuation-docs.sh"
"${repo_root}/tests/issue-9-command-state.sh"
"${repo_root}/tests/isolated-worktree-state-policy.sh"
"${repo_root}/tests/isolated-work-survival-docs.sh"
"${repo_root}/tests/reboot-recovery-policy.sh"
"${repo_root}/tests/reboot-recovery-docs.sh"
"${repo_root}/tests/evidence-backed-pr-policy.sh"
"${repo_root}/tests/evidence-backed-pr-docs.sh"
"${repo_root}/tests/human-merge-boundary-policy.sh"
"${repo_root}/tests/human-merge-boundary-docs.sh"
"${repo_root}/tests/repository-secrets.sh"

git -C "${repo_root}" diff --check

echo "Cloud foundation static verification passed."
