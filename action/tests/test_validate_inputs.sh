#!/usr/bin/env bash
set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"

run_case() (
  local name="${1:?missing name}"
  local expect="${2:?missing exit}"
  shift 2

  local out
  set +e
  out="$(
    HARDPROOF_ACTION_URL="${HARDPROOF_ACTION_URL:-}" \
    HARDPROOF_ACTION_CMD="${HARDPROOF_ACTION_CMD:-}" \
    HARDPROOF_ACTION_FULL_SUITE="${HARDPROOF_ACTION_FULL_SUITE:-false}" \
    HARDPROOF_ACTION_SARIF="${HARDPROOF_ACTION_SARIF:-false}" \
    HARDPROOF_ACTION_ALLOW_PRIVATE_TARGETS="${HARDPROOF_ACTION_ALLOW_PRIVATE_TARGETS:-false}" \
    "$@" 2>&1
  )"
  local got="$?"
  set -e

  if [[ "${got}" != "${expect}" ]]; then
    echo "ERROR: ${name}: expected exit ${expect}, got ${got}" >&2
    echo "${out}" >&2
    exit 1
  fi
)

script="${repo_root}/action/validate_inputs.sh"

HARDPROOF_ACTION_URL="http://127.0.0.1:3000/mcp" \
  HARDPROOF_ACTION_CMD="" \
  run_case "url-only" 0 bash "${script}"

HARDPROOF_ACTION_URL="" \
  HARDPROOF_ACTION_CMD="./server" \
  run_case "cmd-only" 0 bash "${script}"

HARDPROOF_ACTION_URL="http://127.0.0.1:3000/mcp" \
  HARDPROOF_ACTION_CMD="./server" \
  run_case "url-and-cmd" 2 bash "${script}"

HARDPROOF_ACTION_URL="" \
  HARDPROOF_ACTION_CMD="" \
  run_case "neither-url-nor-cmd" 2 bash "${script}"

HARDPROOF_ACTION_URL="http://127.0.0.1:3000/mcp" \
  HARDPROOF_ACTION_SARIF="nope" \
  run_case "bad-sarif" 2 bash "${script}"

HARDPROOF_ACTION_URL="http://127.0.0.1:3000/mcp" \
  HARDPROOF_ACTION_ALLOW_PRIVATE_TARGETS="nope" \
  run_case "bad-allow-private-targets" 2 bash "${script}"
