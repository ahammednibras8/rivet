#!/usr/bin/env bash

set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
policy_file="${repo_root}/ansible/roles/ssh_hardening/files/00-rivet-hardening.conf"
expected_policy='PermitRootLogin no
PasswordAuthentication no
KbdInteractiveAuthentication no
PubkeyAuthentication yes
AuthenticationMethods publickey
PermitEmptyPasswords no
AllowUsers rivet-admin
DisableForwarding yes
MaxAuthTries 3
LoginGraceTime 30'

if [[ "$(<"${policy_file}")" != "${expected_policy}" ]]; then
  echo "Unexpected SSH hardening policy in ${policy_file}" >&2
  exit 1
fi

sshd_binary="$(command -v sshd)"
ssh_test_dir="$(mktemp -d "${TMPDIR:-/tmp}/rivet-sshd-test.XXXXXX")"

cleanup() {
  rm -f "${ssh_test_dir}/host_key" "${ssh_test_dir}/host_key.pub"
  rmdir "${ssh_test_dir}" 2>/dev/null || true
}
trap cleanup EXIT

ssh-keygen -q -t ed25519 -N '' -f "${ssh_test_dir}/host_key"
effective_policy="$(
  "${sshd_binary}" \
    -T \
    -h "${ssh_test_dir}/host_key" \
    -f "${policy_file}" \
    -C user=rivet-admin,host=localhost,addr=127.0.0.1
)"

for expected_setting in \
  'permitrootlogin no' \
  'passwordauthentication no' \
  'kbdinteractiveauthentication no' \
  'pubkeyauthentication yes' \
  'authenticationmethods publickey' \
  'permitemptypasswords no' \
  'allowusers rivet-admin' \
  'disableforwarding yes' \
  'maxauthtries 3' \
  'logingracetime 30'; do
  if ! grep -Fqx "${expected_setting}" <<<"${effective_policy}"; then
    echo "OpenSSH did not apply: ${expected_setting}" >&2
    exit 1
  fi
done

echo "OpenSSH accepts and applies the Rivet hardening policy."
