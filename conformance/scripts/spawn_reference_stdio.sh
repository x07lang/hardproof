#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
TARGET_ID="${1:?missing target id (good-stdio|broken-stdio)}"

case "${TARGET_ID}" in
  good-stdio)
    exec python3 "${ROOT}/scripts/ci/fixtures/mcp_stdio_fixture_server.py" --fixture-id good-stdio
    ;;
  broken-stdio)
    exec python3 "${ROOT}/scripts/ci/fixtures/mcp_stdio_fixture_server.py" --fixture-id broken-stdio
    ;;
  *)
    echo "ERROR: unknown target id: ${TARGET_ID}" >&2
    exit 2
    ;;
esac
