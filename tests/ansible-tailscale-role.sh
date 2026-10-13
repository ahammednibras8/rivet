#!/usr/bin/env bash

set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
config_file="${repo_root}/ansible/ansible.cfg"
tasks_file="${repo_root}/ansible/roles/tailscale_admin/tasks/main.yml"
fixture="${repo_root}/tests/fixtures/ansible/tailscale-admin.yml"

expected_tasks='---
- name: Install Tailscale repository signing key
  ansible.builtin.get_url:
    url: https://pkgs.tailscale.com/stable/ubuntu/noble.noarmor.gpg
    dest: /usr/share/keyrings/tailscale-archive-keyring.gpg
    checksum: sha256:3e03dacf222698c60b8e2f990b809ca1b3e104de127767864284e6c228f1fb39
    owner: root
    group: root
    mode: "0644"

- name: Install Debian repository support
  ansible.builtin.apt:
    name: python3-debian
    state: present

- name: Configure Tailscale stable repository
  ansible.builtin.deb822_repository:
    name: tailscale
    types:
      - deb
    uris:
      - https://pkgs.tailscale.com/stable/ubuntu
    suites:
      - noble
    components:
      - main
    signed_by: /usr/share/keyrings/tailscale-archive-keyring.gpg
    enabled: true
    mode: "0644"
    state: present
  register: tailscale_repository

- name: Install pinned Tailscale client
  ansible.builtin.apt:
    name: tailscale=1.104.1
    state: present
    update_cache: true
  when: not (ansible_check_mode and tailscale_repository.changed)

- name: Keep Tailscale daemon enabled
  ansible.builtin.systemd_service:
    name: tailscaled
    enabled: true
    state: started
  when: not (ansible_check_mode and tailscale_repository.changed)

- name: Read Tailscale enrollment state
  ansible.builtin.command:
    argv:
      - /usr/bin/tailscale
      - status
      - --json
  register: rivet_tailscale_status
  changed_when: false
  when: not ansible_check_mode

- name: Require private administrative connectivity
  ansible.builtin.assert:
    that:
      - (rivet_tailscale_status.stdout | from_json).BackendState == "Running"
    fail_msg: >-
      Tailscale must be enrolled and running before the host firewall is
      enabled. Follow the runbook interactive-enrollment checkpoint.
  when: not ansible_check_mode'

if [[ ! -f "$tasks_file" ]]; then
  printf 'Missing Tailscale role tasks: %s\n' "$tasks_file" >&2
  exit 1
fi

if [[ "$(<"$tasks_file")" != "$expected_tasks" ]]; then
  printf 'Unexpected Tailscale installation policy in %s\n' "$tasks_file" >&2
  exit 1
fi

if rg -n 'tailscale (up|login)|auth[-_]?key|--ssh' "$tasks_file"; then
  printf 'Tailscale enrollment or SSH authority must not be stored in the installation role\n' >&2
  exit 1
fi

ANSIBLE_CONFIG="$config_file" \
  ansible-playbook \
    --inventory 'localhost,' \
    --syntax-check \
    "$fixture"

printf 'The pinned Tailscale client requires enrollment before private-only firewall convergence.\n'
