#!/usr/bin/env bash

set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
config_file="${repo_root}/ansible/ansible.cfg"
role_dir="${repo_root}/ansible/roles/validation_tools"
playbook="${repo_root}/tests/fixtures/ansible/validation-tools.yml"

expected_main='---
- name: Install validation tool archive prerequisites
  ansible.builtin.import_tasks: packages.yml

- name: Prepare the validation tool filesystem
  ansible.builtin.import_tasks: layout.yml

- name: Install reviewed validation tool releases
  ansible.builtin.import_tasks: install.yml'

expected_packages='---
- name: Install validation tool archive prerequisites
  ansible.builtin.apt:
    name:
      - unzip
      - xz-utils
    state: present
    update_cache: true
    cache_valid_time: 3600'

expected_layout='---
- name: Maintain validation tool directories
  ansible.builtin.file:
    path: "{{ item }}"
    state: directory
    owner: root
    group: root
    mode: "0755"
  loop:
    - /var/cache/rivet/validation-tools
    - /opt/rivet
    - /opt/rivet/validation-tools
    - /opt/rivet/validation-tools/tofu
    - "/opt/rivet/validation-tools/tofu/{{ validation_tools_tofu_version }}"
    - /opt/rivet/validation-tools/shellcheck
    - "/opt/rivet/validation-tools/shellcheck/{{ validation_tools_shellcheck_version }}"
    - /opt/rivet/validation-tools/gitleaks
    - "/opt/rivet/validation-tools/gitleaks/{{ validation_tools_gitleaks_version }}"'

if [[ "$(<"${role_dir}/tasks/main.yml")" != "$expected_main" ]]; then
  echo "Validation tools must import the reviewed package, layout, and installation policies" >&2
  exit 1
fi

if [[ "$(<"${role_dir}/tasks/packages.yml")" != "$expected_packages" ]]; then
  echo "Validation tools must install only the required ZIP and XZ archive prerequisites" >&2
  exit 1
fi

if [[ "$(<"${role_dir}/tasks/layout.yml")" != "$expected_layout" ]]; then
  echo "Validation tool caches and versioned installations must be root-owned and non-writable by rivet" >&2
  exit 1
fi

required_install_fragments=(
  'checksum: "sha256:{{ validation_tools_tofu_sha256 }}"'
  'checksum: "sha256:{{ validation_tools_shellcheck_sha256 }}"'
  'checksum: "sha256:{{ validation_tools_gitleaks_sha256 }}"'
  'include:'
  '      - tofu'
  '      - "shellcheck-v{{ validation_tools_shellcheck_version }}/shellcheck"'
  '      - --strip-components=1'
  '      - gitleaks'
  '    state: file'
  '    mode: "0755"'
  '    state: link'
  '      dest: /usr/local/bin/tofu'
  '      dest: /usr/local/bin/shellcheck'
  '      dest: /usr/local/bin/gitleaks'
  '- name: Read installed OpenTofu version as rivet'
  '- name: Read installed ShellCheck version as rivet'
  '- name: Read installed Gitleaks version as rivet'
  '  become_user: rivet'
  '      - validation_tools_tofu_version in validation_tools_tofu_installed_version.stdout'
  '      - validation_tools_shellcheck_version in validation_tools_shellcheck_installed_version.stdout'
  '      - validation_tools_gitleaks_version in validation_tools_gitleaks_installed_version.stdout'
)

for fragment in "${required_install_fragments[@]}"; do
  if ! grep -Fq -- "$fragment" "${role_dir}/tasks/install.yml"; then
    echo "Missing validation tool installation policy fragment: ${fragment}" >&2
    exit 1
  fi
done

if [[ "$(grep -Fc -- '  ansible.builtin.get_url:' "${role_dir}/tasks/install.yml")" -ne 3 ]] ||
  [[ "$(grep -Fc -- '  ansible.builtin.unarchive:' "${role_dir}/tasks/install.yml")" -ne 3 ]] ||
  [[ "$(grep -Fc -- '  become_user: rivet' "${role_dir}/tasks/install.yml")" -ne 3 ]]; then
  echo "Each reviewed tool must have one checksum-protected download, extraction, and rivet-account version execution" >&2
  exit 1
fi

if [[ "$(grep -Fc -- '  when: not ansible_check_mode' "${role_dir}/tasks/install.yml")" -ne 14 ]]; then
  echo "Every source-dependent install, link, and version task must be skipped in check mode" >&2
  exit 1
fi

if grep -ERiq -- '(sudoers|docker[^[:space:]]*group|password|credential|/home/rivet/\.ssh)' "$role_dir"; then
  echo "The validation tool role must not broaden the rivet service-account boundary" >&2
  exit 1
fi

ANSIBLE_CONFIG="$config_file" \
  ansible-playbook \
    --inventory 'localhost,' \
    --syntax-check \
    "$playbook"

echo "The validation tool installation and service-account policies are valid."
