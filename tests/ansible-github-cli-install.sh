#!/usr/bin/env bash

set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
config_file="${repo_root}/ansible/ansible.cfg"
tasks_file="${repo_root}/ansible/roles/github_cli/tasks/main.yml"
playbook="${repo_root}/tests/fixtures/ansible/github-cli.yml"
expected_tasks='---
- name: Maintain GitHub CLI package cache
  ansible.builtin.file:
    path: /var/cache/rivet/github-cli
    state: directory
    owner: root
    group: root
    mode: "0755"

- name: Maintain private GitHub CLI configuration directory
  ansible.builtin.file:
    path: /home/rivet/.config/gh
    state: directory
    owner: rivet
    group: rivet
    mode: "0700"

- name: Download reviewed GitHub CLI package
  ansible.builtin.get_url:
    url: "{{ github_cli_download_url }}"
    dest: "/var/cache/rivet/github-cli/{{ github_cli_package }}"
    checksum: "sha256:{{ github_cli_sha256 }}"
    owner: root
    group: root
    mode: "0644"
  when: not ansible_check_mode

- name: Install reviewed GitHub CLI package
  ansible.builtin.apt:
    deb: "/var/cache/rivet/github-cli/{{ github_cli_package }}"
    state: present
  when: not ansible_check_mode

- name: Read installed GitHub CLI version
  ansible.builtin.command:
    argv:
      - gh
      - --version
  register: github_cli_installed_version
  changed_when: false
  when: not ansible_check_mode

- name: Verify installed GitHub CLI version
  ansible.builtin.assert:
    that:
      - github_cli_version in github_cli_installed_version.stdout
    fail_msg: "Installed GitHub CLI does not match reviewed version {{ github_cli_version }}"
  when: not ansible_check_mode'

if [[ ! -f "$tasks_file" ]] || [[ "$(<"$tasks_file")" != "$expected_tasks" ]]; then
  echo "GitHub CLI must keep private configuration and use a verified, check-mode-safe package" >&2
  exit 1
fi

ANSIBLE_CONFIG="$config_file" \
  ansible-playbook \
    --inventory 'localhost,' \
    --syntax-check \
    "$playbook"

echo "The reviewed GitHub CLI package installation policy is valid."
