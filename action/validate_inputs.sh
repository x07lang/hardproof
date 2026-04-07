#!/usr/bin/env bash
set -euo pipefail

url="${HARDPROOF_ACTION_URL:-}"
cmd="${HARDPROOF_ACTION_CMD:-}"
full_suite="${HARDPROOF_ACTION_FULL_SUITE:-false}"
sarif="${HARDPROOF_ACTION_SARIF:-false}"
allow_partial_score="${HARDPROOF_ACTION_ALLOW_PARTIAL_SCORE:-false}"
threshold="${HARDPROOF_ACTION_THRESHOLD:-80}"
require_trust_for_full_score="${HARDPROOF_ACTION_REQUIRE_TRUST_FOR_FULL_SCORE:-false}"

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

case "${allow_partial_score}" in
  true|false) ;;
  *)
    echo "ERROR: invalid 'allow-partial-score' value (expected 'true' or 'false'): ${allow_partial_score}" >&2
    exit 2
    ;;
esac

case "${require_trust_for_full_score}" in
  true|false) ;;
  *)
    echo "ERROR: invalid 'require-trust-for-full-score' value (expected 'true' or 'false'): ${require_trust_for_full_score}" >&2
    exit 2
    ;;
esac

if ! [[ "${threshold}" =~ ^[0-9]+$ ]]; then
  echo "ERROR: invalid 'threshold' value (expected integer 0-100): ${threshold}" >&2
  exit 2
fi
if (( threshold > 100 )); then
  echo "ERROR: invalid 'threshold' value (expected integer 0-100): ${threshold}" >&2
  exit 2
fi
