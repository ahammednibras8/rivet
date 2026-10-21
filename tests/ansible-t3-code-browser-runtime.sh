#!/usr/bin/env bash

set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
config_file="${repo_root}/ansible/ansible.cfg"
main_file="${repo_root}/ansible/roles/t3_code/tasks/main.yml"
browser_file="${repo_root}/ansible/roles/t3_code/tasks/browser.yml"
handlers_file="${repo_root}/ansible/roles/t3_code/handlers/main.yml"
profile_file="${repo_root}/ansible/roles/t3_code/files/t3-chrome-headless-shell"
users_file="${repo_root}/ansible/roles/system_baseline/tasks/users.yml"
evidence_file="${repo_root}/docs/evidence/issue-52-t3-browser-runtime.md"
playbook="${repo_root}/tests/fixtures/ansible/t3-code.yml"

expected_imports='- name: Install T3 Code runtime dependencies
  ansible.builtin.import_tasks: packages.yml

- name: Allow the T3 browser sandbox
  ansible.builtin.import_tasks: browser.yml

- name: Download the reviewed T3 Code release'
expected_browser='---
- name: Install the T3 browser AppArmor profile
  ansible.builtin.copy:
    src: t3-chrome-headless-shell
    dest: /etc/apparmor.d/t3-chrome-headless-shell
    owner: root
    group: root
    mode: "0644"
    validate: /usr/sbin/apparmor_parser --skip-kernel-load --skip-cache --quiet %s
  notify: Reload T3 browser AppArmor profile'
expected_handlers='---
- name: Reload the T3 browser AppArmor profile
  ansible.builtin.command:
    argv:
      - /usr/sbin/apparmor_parser
      - --replace
      - /etc/apparmor.d/t3-chrome-headless-shell
  changed_when: false
  listen: Reload T3 browser AppArmor profile'
expected_profile='# Managed by Ansible for T3 Code'"'"'s headless browser sandbox.
abi <abi/4.0>,
include <tunables/global>
profile t3-chrome-headless-shell /**/tools/chrome-headless-shell/*/*/chrome-headless-shell flags=(unconfined) {
  userns,
  include if exists <local/t3-chrome-headless-shell>
}'

for required_file in \
  "$main_file" \
  "$browser_file" \
  "$handlers_file" \
  "$profile_file" \
  "$evidence_file"; do
  if [[ ! -f "$required_file" ]]; then
    echo "Missing T3 browser runtime file: ${required_file}" >&2
    exit 1
  fi
done

if [[ "$(<"$main_file")" != *"$expected_imports"* ]]; then
  echo "T3 browser preparation must run after packages and before the release" >&2
  exit 1
fi

if [[ "$(<"$browser_file")" != "$expected_browser" ]] ||
  [[ "$(<"$handlers_file")" != "$expected_handlers" ]] ||
  [[ "$(<"$profile_file")" != "$expected_profile" ]]; then
  echo "The T3 browser profile must be validated, root-owned, and reloaded idempotently" >&2
  exit 1
fi

rivet_user_block="$(
  sed -n \
    '/^- name: Create Rivet service account$/,/^- name: Maintain Rivet administrative account$/p' \
    "$users_file"
)"
if [[ "$rivet_user_block" != *'    groups: ""'* ]] ||
  grep -Eiq -- 'sudo|docker' <<<"$rivet_user_block"; then
  echo "The browser runtime must not expand the rivet service-account boundary" >&2
  exit 1
fi

if grep -Eiq -- 'become_user:[[:space:]]*rivet|sudo|docker' \
  "$browser_file" "$handlers_file"; then
  echo "The browser runtime must remain under the administrative boundary" >&2
  exit 1
fi

/usr/sbin/apparmor_parser \
  --skip-kernel-load \
  --skip-cache \
  --quiet \
  "$profile_file"

required_evidence_text=(
  'Ubuntu 24.04 AMD64'
  'Chrome Headless Shell 154.0.8037.92'
  'libatk-1.0.so.0'
  'libatk1.0-0t64'
  'AppArmor user-namespace restriction is enabled'
  'No privileged convergence or successful browser launch is claimed yet.'
  'full cloud-foundation suite is not claimed as passing'
  'Human review and a privileged Ansible apply remain required.'
)

for expected in "${required_evidence_text[@]}"; do
  if ! grep -Fq -- "$expected" "$evidence_file"; then
    echo "Issue #52 evidence is missing: ${expected}" >&2
    exit 1
  fi
done

if grep -Eiq -- \
  'github_pat_|gh[pousr]_[[:alnum:]_]+|token[[:space:]]*[:=]|/home/|git@|github\.com/[^[:space:]]+/[^[:space:]]+' \
  "$evidence_file"; then
  echo "Issue #52 evidence contains prohibited private detail" >&2
  exit 1
fi

ANSIBLE_CONFIG="$config_file" \
  ansible-playbook \
    --inventory 'localhost,' \
    --syntax-check \
    "$playbook"

echo "T3 browser packages, sandbox, ownership, idempotency, and service boundary are enforced."
