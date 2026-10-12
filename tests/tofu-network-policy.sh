#!/usr/bin/env bash

set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
tofu_dir="${repo_root}/infra/tofu"

if rg --quiet \
  'resource[[:space:]]+"aws_lightsail_instance_public_ports"' \
  "${tofu_dir}"; then
  echo "The workspace must not expose Lightsail public ports; administrative SSH uses Tailscale." >&2
  exit 1
fi

echo "The workspace exposes no Lightsail public ports."
