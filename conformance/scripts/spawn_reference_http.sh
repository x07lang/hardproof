#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
TARGET_ID="${1:?missing target id (good-http|auth-http|broken-http)}"
MODE="${2:-noauth}"

case "${TARGET_ID}" in
  good-http)
    export MCP_FIXTURE_PORT="${MCP_FIXTURE_PORT:-18080}"
    exec python3 "${ROOT}/scripts/ci/fixtures/mcp_http_fixture_server.py" \
      --fixture-id good-http \
      --port "${MCP_FIXTURE_PORT}"
    ;;
  auth-http)
    export MCP_FIXTURE_PORT="${MCP_FIXTURE_PORT:-18081}"
    exec python3 "${ROOT}/scripts/ci/fixtures/mcp_http_fixture_server.py" \
      --fixture-id auth-http \
      --port "${MCP_FIXTURE_PORT}"
    ;;
  broken-http)
    export MCP_FIXTURE_PORT="${MCP_FIXTURE_PORT:-18082}"
    exec python3 "${ROOT}/scripts/ci/fixtures/mcp_http_fixture_server.py" \
      --fixture-id broken-http \
      --port "${MCP_FIXTURE_PORT}"
    ;;
  *)
    echo "ERROR: unknown target id: ${TARGET_ID}" >&2
    exit 2
    ;;
esac
