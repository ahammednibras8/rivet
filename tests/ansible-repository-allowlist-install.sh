#!/usr/bin/env bash

set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
config_file="${repo_root}/ansible/ansible.cfg"
playbook="${repo_root}/ansible/install-repository-allowlist.yml"

expected_playbook='---
- name: Install an approved repository allowlist
  hosts: rivet_workspace
  become: true
  gather_facts: false
  any_errors_fatal: true

  vars:
    repository_allowlist_destination: /home/rivet/.config/rivet/repositories.json

  pre_tasks:
    - name: Require a local approval manifest
      ansible.builtin.assert:
        that:
          - repository_allowlist_source is defined
          - repository_allowlist_source | length > 0
        fail_msg: Set repository_allowlist_source to the private local manifest path
      delegate_to: localhost
      become: false

    - name: Validate the local approval manifest
      ansible.builtin.command:
        argv:
          - "{{ playbook_dir }}/roles/repository_access/files/rivet-repository-allowlist"
          - validate-manifest
          - --manifest
          - "{{ repository_allowlist_source }}"
      changed_when: false
      delegate_to: localhost
      become: false
      no_log: true

  tasks:
    - name: Create private manifest staging file
      ansible.builtin.tempfile:
        path: /home/rivet/.config/rivet
        prefix: .repositories.
        state: file
      register: repository_allowlist_staging

    - name: Validate and install the approved manifest
      block:
        - name: Stage the approved manifest
          ansible.builtin.copy:
            src: "{{ repository_allowlist_source }}"
            dest: "{{ repository_allowlist_staging.path }}"
            owner: root
            group: rivet
            mode: "0640"
          no_log: true

        - name: Verify staged repository approvals against GitHub
          ansible.builtin.command:
            argv:
              - /usr/local/bin/rivet-repository-allowlist
              - verify
              - --manifest
              - "{{ repository_allowlist_staging.path }}"
          become_user: rivet
          environment:
            HOME: /home/rivet
          changed_when: false
          no_log: true

        - name: Activate the verified repository allowlist
          ansible.builtin.command:
            argv:
              - mv
              - --
              - "{{ repository_allowlist_staging.path }}"
              - "{{ repository_allowlist_destination }}"
          changed_when: true
      always:
        - name: Remove repository allowlist staging file
          ansible.builtin.file:
            path: "{{ repository_allowlist_staging.path }}"
            state: absent
          no_log: true'

if [[ ! -f "$playbook" ]] || [[ "$(<"$playbook")" != "$expected_playbook" ]]; then
  echo "Repository approvals must be validated, remotely verified, and atomically installed" >&2
  exit 1
fi

if find "$repo_root" \
  -path "${repo_root}/.git" -prune -o \
  -path "${repo_root}/.vscode" -prune -o \
  -type f -name 'repositories.json' -print -quit | grep -q .; then
  echo "A real repository approval manifest must never be committed" >&2
  exit 1
fi

ANSIBLE_CONFIG="$config_file" \
  ansible-playbook \
    --inventory 'localhost,' \
    --syntax-check \
    "$playbook"

echo "Repository approvals are installed privately and atomically."
