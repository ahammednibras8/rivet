#!/usr/bin/env bash

set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
config_file="${repo_root}/ansible/ansible.cfg"
install_file="${repo_root}/ansible/roles/t3_code/tasks/install.yml"
playbook="${repo_root}/tests/fixtures/ansible/t3-code.yml"
expected_extraction='- name: Extract reviewed T3 Code release
  ansible.builtin.unarchive:
    src: "/var/cache/rivet/t3-code/{{ t3_code_release_archive }}"
    dest: "/home/rivet/.t3/runtime/versions/{{ t3_code_version }}"
    remote_src: true
    owner: rivet
    group: rivet
    extra_opts:
      - --strip-components=1
    creates: "/home/rivet/.t3/runtime/versions/{{ t3_code_version }}/.install-complete"
  when: not ansible_check_mode

- name: Read installed T3 Code version
  ansible.builtin.command:
    argv:
      - "/home/rivet/.t3/runtime/versions/{{ t3_code_version }}/t3"
      - --version
  become: true
  become_user: rivet
  environment:
    HOME: /home/rivet
  register: t3_code_installed_version
  changed_when: false
  when: not ansible_check_mode

- name: Verify installed T3 Code version
  ansible.builtin.assert:
    that:
      - t3_code_version in t3_code_installed_version.stdout
    fail_msg: "Installed T3 Code does not match reviewed version {{ t3_code_version }}"
  when: not ansible_check_mode

- name: Mark T3 Code release installed
  ansible.builtin.copy:
    content: "{{ t3_code_version }}\n"
    dest: "/home/rivet/.t3/runtime/versions/{{ t3_code_version }}/.install-complete"
    owner: rivet
    group: rivet
    mode: "0640"
  when: not ansible_check_mode'

if [[ ! -f "$install_file" ]] || [[ "$(<"$install_file")" != *"$expected_extraction"* ]]; then
  echo "T3 Code must be extracted, version-verified as rivet, and marked complete only after verification" >&2
  exit 1
fi

ANSIBLE_CONFIG="$config_file" \
  ansible-playbook \
    --inventory 'localhost,' \
    --syntax-check \
    "$playbook"

echo "The reviewed T3 Code release is extracted and verified before completion."
