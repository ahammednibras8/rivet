#!/usr/bin/env bash

set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
tofu_dir="${repo_root}/infra/tofu"

if rg --quiet \
  --glob '*.tf' \
  --glob '*.tftest.hcl' \
  'operator_ipv4_cidr' \
  "${tofu_dir}"; then
  echo "OpenTofu still requires the retired public-address input." >&2
  exit 1
fi

echo "The workspace replaces Lightsail defaults with scoped bootstrap SSH; routine administration uses Tailscale."
