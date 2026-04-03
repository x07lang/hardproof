#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
URL="http://127.0.0.1:18080/mcp"
BASELINE="${ROOT}/conformance/pinned/conformance-baseline.yml"
OUT_DIR="${ROOT}/out/conformance"
SPAWN_TARGET=""
SPAWN_MODE="noauth"
URL_EXPLICIT=0
FULL_SUITE=0
SCENARIOS=()

while [[ $# -gt 0 ]]; do
  case "$1" in
    --url)
      URL="${2:?missing value for --url}"
      URL_EXPLICIT=1
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
    --scenario)
      SCENARIOS+=("${2:?missing value for --scenario}")
      shift 2
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

CONFORMANCE_VERSION="$(tr -d '\n' < "${ROOT}/conformance/pinned/official-package-version.txt")"
if [[ -z "${CONFORMANCE_VERSION}" ]]; then
  echo "ERROR: missing conformance pinned version" >&2
  exit 2
fi

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

if [[ "${FULL_SUITE}" == "1" && -n "${SPAWN_TARGET}" ]]; then
  start_spawn
fi

raw_root="${OUT_DIR}/raw"

if [[ "${FULL_SUITE}" == "1" ]]; then
  npx -y "@modelcontextprotocol/conformance@${CONFORMANCE_VERSION}" \
    server \
    --url "${URL}" \
    --expected-failures "${BASELINE}" \
    --output-dir "${raw_root}/full-suite"
else
  if [[ "${#SCENARIOS[@]}" -eq 0 ]]; then
    SCENARIOS=(
      server-initialize
      ping
      tools-list
      tools-call-with-progress
      resources-subscribe
      resources-unsubscribe
      server-sse-multiple-streams
      dns-rebinding-protection
    )
  fi
  for scenario in "${SCENARIOS[@]}"; do
    if [[ "${URL_EXPLICIT}" != "1" && -n "${SPAWN_TARGET}" ]]; then
      start_spawn
    fi
    npx -y "@modelcontextprotocol/conformance@${CONFORMANCE_VERSION}" \
      server \
      --url "${URL}" \
      --scenario "${scenario}" \
      --output-dir "${raw_root}/${scenario}" \
      --expected-failures "${BASELINE}"
    if [[ "${URL_EXPLICIT}" != "1" && -n "${SPAWN_TARGET}" ]]; then
      stop_spawn
    fi
  done
fi

stop_spawn
