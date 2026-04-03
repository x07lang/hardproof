#!/usr/bin/env bash
set -euo pipefail

url="${HARDPROOF_ACTION_URL:-}"
cmd="${HARDPROOF_ACTION_CMD:-}"
full_suite="${HARDPROOF_ACTION_FULL_SUITE:-false}"
sarif="${HARDPROOF_ACTION_SARIF:-false}"

if [[ -n "${url}" && -n "${cmd}" ]]; then
  echo "ERROR: set exactly one of 'url' or 'cmd'." >&2
  exit 2
fi
if [[ -z "${url}" && -z "${cmd}" ]]; then
  echo "ERROR: missing required input: set 'url' or 'cmd'." >&2
  exit 2
fi

case "${full_suite}" in
  true|false) ;;
  *)
    echo "ERROR: invalid 'full-suite' value (expected 'true' or 'false'): ${full_suite}" >&2
    exit 2
    ;;
esac

case "${sarif}" in
  true|false) ;;
  *)
    echo "ERROR: invalid 'sarif' value (expected 'true' or 'false'): ${sarif}" >&2
    exit 2
    ;;
esac
