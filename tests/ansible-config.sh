#!/usr/bin/env bash

set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
config_file="${repo_root}/ansible/ansible.cfg"
expected_config=$'[defaults]\ninventory = inventory/hosts.yml\nroles_path = roles\nhost_key_checking = True\ninterpreter_python = /usr/bin/python3\nretry_files_enabled = False'

if [[ "$(<"${config_file}")" != "${expected_config}" ]]; then
  echo "Unexpected Ansible configuration in ${config_file}" >&2
  exit 1
fi

resolved_config="$(
  env -u NO_COLOR -u PAGER \
    ANSIBLE_CONFIG="${config_file}" \
    ansible-config dump --only-changed
)"

for expected_value in \
  "${repo_root}/ansible/inventory/hosts.yml" \
  "${repo_root}/ansible/roles" \
  'HOST_KEY_CHECKING' \
  'INTERPRETER_PYTHON' \
  'RETRY_FILES_ENABLED'; do
  if ! grep -Fq "${expected_value}" <<<"${resolved_config}"; then
    echo "Ansible did not resolve ${expected_value} from ${config_file}" >&2
    exit 1
  fi
done

echo "Ansible configuration resolves the protected defaults."
