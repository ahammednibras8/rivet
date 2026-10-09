#!/usr/bin/env bash

set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
config_file="${repo_root}/ansible/ansible.cfg"
rules_file="${repo_root}/ansible/roles/host_firewall/tasks/rules.yml"
fixtures_dir="${repo_root}/tests/fixtures/ansible"
expected_rules='---
- name: Allow SSH from the approved operator address
  community.general.ufw:
    rule: allow
    direction: in
    proto: tcp
    from_ip: "{{ rivet_operator_ipv4_cidr }}"
    to_port: "22"
    comment: Rivet administrative SSH

- name: Remove unrestricted SSH access
  community.general.ufw:
    rule: allow
    direction: in
    proto: tcp
    to_port: "22"
    delete: true

- name: Deny other incoming traffic by default
  community.general.ufw:
    default: deny
    direction: incoming

- name: Allow outgoing traffic by default
  community.general.ufw:
    default: allow
    direction: outgoing

- name: Enable low-volume firewall logging
  community.general.ufw:
    logging: low

- name: Enable the host firewall
  community.general.ufw:
    state: enabled'

if [[ "$(<"${rules_file}")" != "${expected_rules}" ]]; then
  echo "Unexpected host firewall policy or task order in ${rules_file}" >&2
  exit 1
fi

ANSIBLE_CONFIG="${config_file}" \
  ansible-playbook \
    --inventory 'localhost,' \
    --syntax-check \
    "${fixtures_dir}/host-firewall.yml"

ANSIBLE_CONFIG="${config_file}" \
  ansible-playbook \
    --inventory 'localhost,' \
    "${fixtures_dir}/firewall-cidr-valid.yml"

if invalid_output="$(
  ANSIBLE_CONFIG="${config_file}" \
    ansible-playbook \
      --inventory 'localhost,' \
      "${fixtures_dir}/firewall-cidr-invalid.yml" 2>&1
)"; then
  echo "The host firewall accepted a CIDR wider than /32" >&2
  exit 1
fi

if ! grep -Fq 'RIVET_OPERATOR_IPV4_CIDR must be one IPv4 address with a /32 prefix.' \
  <<<"${invalid_output}"; then
  echo "The host firewall did not explain the invalid operator CIDR" >&2
  exit 1
fi

echo "The host firewall permits only operator-scoped SSH before enabling UFW."
