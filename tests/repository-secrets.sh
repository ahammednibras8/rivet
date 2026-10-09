#!/usr/bin/env bash

set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
prohibited_files=()

if ! command -v gitleaks >/dev/null 2>&1; then
  echo "Gitleaks is required for repository secret scanning" >&2
  exit 1
fi

while IFS= read -r path; do
  case "${path}" in
    .env | .env.* | */.env | */.env.* | \
      *.tfstate | *.tfstate.* | *.tfplan | *.plan | \
      *.pem | *.key | *.p12 | *.pfx | *.jks | \
      id_rsa | id_dsa | id_ecdsa | id_ed25519 | \
      */id_rsa | */id_dsa | */id_ecdsa | */id_ed25519 | \
      credentials | */credentials)
      prohibited_files+=("${path}")
      ;;
  esac
done < <(git -C "${repo_root}" ls-files --cached --others --exclude-standard)

if ((${#prohibited_files[@]} > 0)); then
  echo "Prohibited generated or credential-bearing files found:" >&2
  printf '  %s\n' "${prohibited_files[@]}" >&2
  exit 1
fi

gitleaks git --no-banner --no-color --redact "${repo_root}"
gitleaks dir --no-banner --no-color --redact "${repo_root}"

echo "Repository history, worktree, and prohibited filenames are clean."
