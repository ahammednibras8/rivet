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
      tfplan* | */tfplan* | \
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

worktree_scan_directory="$(
  mktemp -d "${TMPDIR:-/tmp}/rivet-gitleaks-worktree.XXXXXX"
)"
readonly worktree_scan_directory

cleanup_worktree_scan() {
  case "${worktree_scan_directory}" in
    "${TMPDIR:-/tmp}"/rivet-gitleaks-worktree.*)
      rm -rf -- "${worktree_scan_directory}"
      ;;
    *)
      echo "Refusing to remove an unexpected worktree scan directory" >&2
      return 1
      ;;
  esac
}
trap cleanup_worktree_scan EXIT

while IFS= read -r -d '' path; do
  if [[ ! -f "${repo_root}/${path}" && ! -L "${repo_root}/${path}" ]]; then
    continue
  fi

  install -d "${worktree_scan_directory}/$(dirname "${path}")"
  cp -P "${repo_root}/${path}" "${worktree_scan_directory}/${path}"
done < <(git -C "${repo_root}" ls-files --cached --others --exclude-standard -z)

gitleaks dir --no-banner --no-color --redact "${worktree_scan_directory}"

echo "Repository history, worktree, and prohibited filenames are clean."
