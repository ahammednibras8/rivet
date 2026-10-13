#!/usr/bin/env bash

set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
config_file="${repo_root}/ansible/ansible.cfg"
access_file="${repo_root}/ansible/roles/system_baseline/tasks/ssh_access.yml"
validation_file="${repo_root}/ansible/roles/system_baseline/tasks/validate_ssh_key.yml"
playbook="${repo_root}/tests/fixtures/ansible/ssh-key-validation.yml"
expected_access='---
- name: Validate the operator SSH public key
  ansible.builtin.import_tasks: validate_ssh_key.yml

- name: Maintain administrator SSH directory
  ansible.builtin.file:
    path: /home/rivet-admin/.ssh
    state: directory
    owner: rivet-admin
    group: rivet-admin
    mode: "0700"

- name: Maintain operator authorized key
  ansible.builtin.copy:
    content: "{{ rivet_operator_ssh_public_key }}\n"
    dest: /home/rivet-admin/.ssh/authorized_keys
    owner: rivet-admin
    group: rivet-admin
    mode: "0600"
    validate: /usr/bin/ssh-keygen -l -f %s'
expected_validation='---
- name: Validate the operator SSH public key value
  ansible.builtin.assert:
    that:
      - rivet_operator_ssh_public_key == (rivet_operator_ssh_public_key | trim)
      - >-
        rivet_operator_ssh_public_key is match(
          '"'"'^ssh-rsa [A-Za-z0-9+/]+={0,3}(?: [^\r\n]+)?$'"'"'
        )
    fail_msg: RIVET_OPERATOR_SSH_PUBLIC_KEY must contain exactly one OpenSSH RSA public key.'

if [[ "$(<"${access_file}")" != "${expected_access}" ]]; then
  echo "Unexpected administrative SSH access policy in ${access_file}" >&2
  exit 1
fi

if [[ "$(<"${validation_file}")" != "${expected_validation}" ]]; then
  echo "Unexpected public-key validation policy in ${validation_file}" >&2
  exit 1
fi

ANSIBLE_CONFIG="${config_file}" \
  ansible-playbook \
    --inventory 'localhost,' \
    "${playbook}" \
    --extra-vars '{"rivet_operator_ssh_public_key":"ssh-rsa AAAAB3NzaC1yc2EAAAADAQABAAABAQCTestKey rivet-test"}'

for invalid_key_json in \
  '{"rivet_operator_ssh_public_key":"not-a-key"}' \
  '{"rivet_operator_ssh_public_key":"ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAITestKey rivet-test"}' \
  '{"rivet_operator_ssh_public_key":"ssh-rsa AAAAB3NzaTestKey first\nssh-rsa AAAAB3NzaSecondKey second"}'; do
  if invalid_output="$(
    ANSIBLE_CONFIG="${config_file}" \
      ansible-playbook \
        --inventory 'localhost,' \
        "${playbook}" \
        --extra-vars "${invalid_key_json}" 2>&1
  )"; then
    echo "The SSH access policy accepted an invalid public key" >&2
    exit 1
  fi

  if ! grep -Fq 'RIVET_OPERATOR_SSH_PUBLIC_KEY must contain exactly one OpenSSH RSA public key.' \
    <<<"${invalid_output}"; then
    echo "The SSH access policy did not explain the invalid public key" >&2
    exit 1
  fi
done

echo "The administrative SSH access policy accepts exactly one RSA public key."
