#!/usr/bin/env bash
# Generate the deterministic, fixture-based corpus dataset: a full five-dimension
# scan per target from the hermetic CI manifest (local good-http fixture, no
# network), plus the rendered index. Used by the scheduled corpus workflow and
# runnable locally. Output is reproducible (the example-refresh normalization is
# NOT applied here; raw timestamps/run_ids vary, so this output is an artifact,
# not a checked-in golden).
set -euo pipefail
BIN="${1:?usage: generate_corpus_sample.sh <hardproof-bin> [out-dir]}"
OUT="${2:-out/corpus-sample}"
here="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
root="$(cd "${here}/../.." && pwd)"
cd "${root}"
export HARDPROOF_TOKENIZERS_DIR="${root}/tokenizers"
export HARDPROOF_HOME="${root}"

rm -rf "${OUT}"; mkdir -p "${OUT}"
server_log="$(mktemp)"
conformance/scripts/spawn_reference_http.sh good-http noauth >"${server_log}" 2>&1 &
server_pid="$!"
trap 'kill "${server_pid}" >/dev/null 2>&1 || true; wait "${server_pid}" >/dev/null 2>&1 || true' EXIT
if ! conformance/scripts/wait_for_http.sh http://127.0.0.1:18080/mcp >/dev/null; then
  echo "ERROR: corpus fixture failed to start: good-http (http://127.0.0.1:18080/mcp)" >&2
  tail -n 100 "${server_log}" >&2
  exit 1
fi

"${BIN}" corpus run \
  --manifest corpus/manifests/quality-report-001.json \
  --out "${OUT}" --machine json >"${OUT}/corpus.run.json"
"${BIN}" corpus render --input "${OUT}/index.json" --out "${OUT}"
"${BIN}" ci validate-json \
  --schema schemas/x07.mcp.corpus.summary.schema.json \
  --input "${OUT}/index.json"

sv="$(python3 -c "import json,sys;print(json.load(open(sys.argv[1]))['schema_version'])" "${OUT}/index.json")"
echo "corpus sample generated at ${OUT} (index schema ${sv})"
[ "${sv}" = "x07.mcp.corpus.summary@0.2.0" ] || { echo "ERROR: unexpected index schema ${sv}" >&2; exit 1; }
