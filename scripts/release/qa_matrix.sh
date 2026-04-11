#!/usr/bin/env bash
set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
cd "${repo_root}"

export HARDPROOF_HOME="${repo_root}"
export HARDPROOF_TOKENIZERS_DIR="${repo_root}/tokenizers"

bin_path=""
out_dir=""

while [[ $# -gt 0 ]]; do
  case "$1" in
    --bin)
      if [[ $# -lt 2 ]]; then
        echo "ERROR: --bin requires a path" >&2
        exit 2
      fi
      bin_path="$2"
      shift 2
      ;;
    --out-dir)
      if [[ $# -lt 2 ]]; then
        echo "ERROR: --out-dir requires a path" >&2
        exit 2
      fi
      out_dir="$2"
      shift 2
      ;;
    *)
      echo "ERROR: unknown argument: $1" >&2
      exit 2
      ;;
  esac
done

if [[ -z "${out_dir}" ]]; then
  ts="$(date -u +%Y%m%d-%H%M%S)"
  out_dir="out/release-qa/${ts}"
fi
mkdir -p "${out_dir}"

if [[ -z "${bin_path}" ]]; then
  bin_path="${out_dir}/hardproof"
  x07 bundle --project x07.json --profile os --json=off --out "${bin_path}" >/dev/null
  chmod +x "${bin_path}"
fi

run_scan() (
  local label="${1:?missing label}"
  shift

  local case_out="${out_dir}/${label}"
  rm -rf "${case_out}"
  mkdir -p "${case_out}"

  set +e
  "${bin_path}" scan \
    --out "${case_out}" \
    --format json \
    --machine json \
    "$@" >"${case_out}/scan.stdout.json"
  local rc="$?"
  set -e

  if [[ "${rc}" != "0" ]]; then
    echo "ERROR: scan failed for ${label} (exit ${rc})" >&2
    cat "${case_out}/scan.stdout.json" >&2 || true
    exit "${rc}"
  fi

  test -s "${case_out}/scan.json"
  test -s "${case_out}/scan.events.jsonl"

  "${bin_path}" report summary --input "${case_out}/scan.json" --ui rich >"${case_out}/report.summary.txt"
  "${bin_path}" report html --input "${case_out}/scan.json" >"${case_out}/report.html"
  "${bin_path}" report sarif --input "${case_out}/scan.json" >"${case_out}/report.sarif.json"
)

echo "==> stdio filesystem"
run_scan "stdio-filesystem" --cmd "npx -y @modelcontextprotocol/server-filesystem /tmp"

echo "==> stdio github"
run_scan "stdio-github" --cmd "npx -y @modelcontextprotocol/server-github"

echo "==> http fixture"
server_log="${out_dir}/http-fixture.server.log"
conformance/scripts/spawn_reference_http.sh good-http noauth >"${server_log}" 2>&1 &
server_pid="$!"

cleanup_server() {
  kill "${server_pid}" >/dev/null 2>&1 || true
  wait "${server_pid}" >/dev/null 2>&1 || true
}
trap cleanup_server EXIT

if ! conformance/scripts/wait_for_http.sh http://127.0.0.1:18080/mcp >/dev/null; then
  echo "ERROR: failed to start good-http fixture" >&2
  tail -n 200 "${server_log}" >&2 || true
  exit 1
fi

run_scan "http-good" --url http://127.0.0.1:18080/mcp --transport http

echo "==> http trust-evaluable"
run_scan "http-trust-full" \
  --url http://127.0.0.1:18080/mcp \
  --transport http \
  --server-json trust/fixtures/server-good.json \
  --mcpb trust/fixtures/bundle-good.mcpb

echo "ok: wrote release QA artifacts to ${out_dir}"
