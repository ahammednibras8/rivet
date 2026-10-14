#!/usr/bin/env bash
set -euo pipefail

mode="${1:-success}"

printf 'issue-9 stdout mode=%s\n' "$mode"
printf 'issue-9 stderr mode=%s\n' "$mode" >&2

case "$mode" in
  success) exit 0 ;;
  failure) exit 23 ;;
  *) exit 64 ;;
esac
