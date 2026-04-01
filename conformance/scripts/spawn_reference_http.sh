#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
TARGET_ID="${1:?missing target id (good-http|auth-http|broken-http)}"
MODE="${2:-noauth}"

cd "${ROOT}/fixtures/servers"

if [[ ! -d node_modules ]]; then
  npm ci >/dev/null
fi

case "${TARGET_ID}" in
  good-http)
    export MCP_FIXTURE_PORT="${MCP_FIXTURE_PORT:-18080}"
    exec node http-hello/server.mjs
    ;;
  auth-http)
    export MCP_FIXTURE_PORT="${MCP_FIXTURE_PORT:-18081}"
    exec node auth-required/server.mjs
    ;;
  broken-http)
    export MCP_FIXTURE_PORT="${MCP_FIXTURE_PORT:-18082}"
    exec node broken-protocol/server.mjs
    ;;
  *)
    echo "ERROR: unknown target id: ${TARGET_ID}" >&2
    exit 2
    ;;
esac

