#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
URL="http://127.0.0.1:18080/mcp"
BASELINE="${ROOT}/conformance/pinned/conformance-baseline.yml"
OUT_DIR="${ROOT}/out/conformance"
SPAWN_TARGET=""
SPAWN_MODE="noauth"
FULL_SUITE=0

while [[ $# -gt 0 ]]; do
  case "$1" in
    --url)
      URL="${2:?missing value for --url}"
      shift 2
      ;;
    --baseline)
      BASELINE="${2:?missing value for --baseline}"
      shift 2
      ;;
    --out)
      OUT_DIR="${2:?missing value for --out}"
      shift 2
      ;;
    --spawn)
      SPAWN_TARGET="${2:?missing value for --spawn}"
      shift 2
      ;;
    --mode)
      SPAWN_MODE="${2:?missing value for --mode}"
      shift 2
      ;;
    --full-suite)
      FULL_SUITE=1
      shift
      ;;
    *)
      echo "unknown argument: $1" >&2
      exit 2
      ;;
  esac
done

if [[ "${BASELINE}" != /* ]]; then
  BASELINE="${ROOT}/${BASELINE#./}"
fi
if [[ "${OUT_DIR}" != /* ]]; then
  OUT_DIR="${ROOT}/${OUT_DIR#./}"
fi

mkdir -p "${OUT_DIR}/raw"

bg_pid=""
start_spawn() {
  if [[ -n "${bg_pid}" ]]; then
    return 0
  fi
  local server_log="/tmp/hardproof-conformance-server.log"
  "${ROOT}/conformance/scripts/spawn_reference_http.sh" "${SPAWN_TARGET}" "${SPAWN_MODE}" >"${server_log}" 2>&1 &
  bg_pid="$!"
  if ! "${ROOT}/conformance/scripts/wait_for_http.sh" "${URL}" >/dev/null; then
    echo "ERROR: spawned server did not become ready at ${URL}" >&2
    if [[ -f "${server_log}" ]]; then
      echo "---- begin spawned server log ----" >&2
      tail -n 200 "${server_log}" >&2 || true
      echo "---- end spawned server log ----" >&2
    fi
    return 1
  fi
}

stop_spawn() {
  if [[ -n "${bg_pid}" ]]; then
    kill "${bg_pid}" >/dev/null 2>&1 || true
    wait "${bg_pid}" >/dev/null 2>&1 || true
    bg_pid=""
  fi
}

trap 'stop_spawn' EXIT

if [[ -n "${SPAWN_TARGET}" ]]; then
  start_spawn
fi

hardproof_bin="${HARDPROOF_BIN:-hardproof}"
if ! command -v "${hardproof_bin}" >/dev/null 2>&1; then
  echo "ERROR: hardproof binary not found on PATH (set HARDPROOF_BIN to override)" >&2
  exit 2
fi

args=(scan --url "${URL}" --baseline "${BASELINE}" --out "${OUT_DIR}" --machine json)
if [[ "${FULL_SUITE}" == "1" ]]; then
  args+=(--full-suite)
fi
"${hardproof_bin}" "${args[@]}"

stop_spawn
