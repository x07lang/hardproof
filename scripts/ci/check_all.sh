#!/usr/bin/env bash
set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
cd "${repo_root}"

echo "==> repo hygiene"
python3 scripts/ci/check_repo_hygiene.py >/dev/null

echo "==> action contract"
bash action/tests/test_validate_inputs.sh >/dev/null
test -s hardproof-scan/action.yml

echo "==> fmt"
while IFS= read -r path; do
  x07 fmt --input "${path}" --check --report-json >/dev/null
done < <(find cli/src score_core/src score_core/tests -name '*.x07.json' -print | LC_ALL=C sort)

echo "==> pkg lock"
x07 pkg lock --project x07.json --check --json=off >/dev/null

echo "==> arch check"
x07 arch check --manifest arch/manifest.x07arch.json >/dev/null

echo "==> score core: pkg lock"
x07 pkg lock --project score_core/x07.json --check --json=off >/dev/null

echo "==> score core: arch check"
(cd score_core && x07 arch check --manifest arch/manifest.x07arch.json >/dev/null)

echo "==> score core: trust profile check"
x07 trust profile check \
  --profile score_core/arch/trust/profiles/hardproof_score_core_pure_v1.json \
  --project score_core/x07.json \
  --entry scan.score.overall_score_n_or_neg1_v1 \
  --json=off >/dev/null

echo "==> score core: tests"
x07 test --all --manifest score_core/tests/tests.json --json=off >/dev/null

echo "==> score core: verify coverage"
x07 verify \
  --coverage \
  --project score_core/x07.json \
  --entry scan.score.overall_score_n_or_neg1_v1 \
  --json=off >/dev/null

mkdir -p out
tmp_dir="$(mktemp -d "out/ci-tmp.XXXXXX")"
trap 'rm -rf "${tmp_dir}"' EXIT

echo "==> score core: trust certify"
score_core_cert_dir="${tmp_dir}/score-core-cert"
rm -rf "${score_core_cert_dir}"
mkdir -p "${score_core_cert_dir}"
score_core_trust_certify_log="${tmp_dir}/score-core-trust-certify.log"
if ! x07 trust certify \
  --project score_core/x07.json \
  --profile score_core/arch/trust/profiles/hardproof_score_core_pure_v1.json \
  --entry scan.score.overall_score_n_or_neg1_v1 \
  --out-dir "${score_core_cert_dir}" \
  --json=pretty >"${score_core_trust_certify_log}" 2>&1; then
  echo "ERROR: x07 trust certify failed for score core." >&2
  cat "${score_core_trust_certify_log}" >&2 || true
  exit 1
fi

score_core_cert="${score_core_cert_dir}/certificate.json"
test -s "${score_core_cert}"
score_core_proof="$(
  python3 - "${score_core_cert}" "scan.score.overall_score_n_or_neg1_v1" <<'PY'
import json
import os
import sys

cert_path = sys.argv[1]
symbol = sys.argv[2]

with open(cert_path, "r", encoding="utf-8") as f:
    cert = json.load(f)

for entry in cert.get("proof_inventory", []):
    if entry.get("symbol") != symbol:
        continue
    proof = entry.get("proof_object") or {}
    proof_path = proof.get("path")
    if not proof_path:
        continue
    if not os.path.isabs(proof_path):
        proof_path = os.path.normpath(os.path.join(os.path.dirname(cert_path), proof_path))
    print(proof_path)
    raise SystemExit(0)

raise SystemExit(1)
PY
)"
test -s "${score_core_proof}"
(cd score_core && x07 prove check --proof "${score_core_proof}" --json=off >/dev/null)

echo "==> score core: trust report"
score_core_trust_report="${tmp_dir}/score-core-trust-report.json"
rm -f "${score_core_trust_report}"
x07 trust report \
  --project score_core/x07.json \
  --out "${score_core_trust_report}" \
  --json=off >/dev/null
test -s "${score_core_trust_report}"

bin_path="${tmp_dir}/hardproof"
bundle_log="${tmp_dir}/bundle.log"
if ! x07 bundle --project x07.json --profile os --json=off --out "${bin_path}" >"${bundle_log}" 2>&1; then
  echo "ERROR: x07 bundle failed." >&2
  cat "${bundle_log}" >&2 || true
  exit 1
fi
chmod +x "${bin_path}"

echo "==> release packaging smoke"
release_dist_dir="${tmp_dir}/release-dist"
rm -rf "${release_dist_dir}"
mkdir -p "${release_dist_dir}"
HARDPROOF_TAG="v0.0.0-alpha.0" DIST_DIR="${release_dist_dir}" ./scripts/ci/build_release_binaries.sh >/dev/null
release_archive="$(ls -1 "${release_dist_dir}"/hardproof_*.tar.gz | head -n 1)"
release_extract_dir="${tmp_dir}/release-extract"
rm -rf "${release_extract_dir}"
mkdir -p "${release_extract_dir}"
tar -xzf "${release_archive}" -C "${release_extract_dir}"
"${release_extract_dir}/hardproof" --help >/dev/null

echo "==> cli smoke"
"${bin_path}" --help >/dev/null
set +e
"${bin_path}" scan --help >/dev/null
scan_help_exit="$?"
set -e
if [[ "${scan_help_exit}" != "0" ]]; then
  echo "ERROR: hardproof scan --help failed (exit ${scan_help_exit})" >&2
  exit 1
fi

echo "==> schema fixtures"
"${bin_path}" ci validate-fixtures

echo "==> corpus smoke"

corpus_out="${tmp_dir}/corpus"
rm -rf "${corpus_out}"
mkdir -p "${corpus_out}"

run_corpus_smoke() (
  local server_log="${tmp_dir}/corpus.server.log"
  conformance/scripts/spawn_reference_http.sh good-http noauth >"${server_log}" 2>&1 &
  local server_pid="$!"

  cleanup() {
    kill "${server_pid}" >/dev/null 2>&1 || true
    wait "${server_pid}" >/dev/null 2>&1 || true
  }
  trap cleanup EXIT

  if ! conformance/scripts/wait_for_http.sh http://127.0.0.1:18080/mcp >/dev/null; then
    echo "ERROR: corpus fixture failed to start: good-http (http://127.0.0.1:18080/mcp)" >&2
    tail -n 200 "${server_log}" >&2 || true
    exit 1
  fi

  set +e
  "${bin_path}" corpus run \
    --manifest corpus/manifests/quality-report-001.json \
    --out "${corpus_out}" \
    --machine json >"${tmp_dir}/corpus.run.stdout.json"
  local corpus_exit="$?"
  set -e
  if [[ "${corpus_exit}" != "0" ]]; then
    echo "ERROR: corpus run exit code mismatch (expected 0, got ${corpus_exit})" >&2
    cat "${tmp_dir}/corpus.run.stdout.json" >&2 || true
    tail -n 200 "${server_log}" >&2 || true
    exit 1
  fi
)

run_corpus_smoke

test -s "${corpus_out}/index.json"
"${bin_path}" ci validate-json \
  --schema schemas/x07.mcp.corpus.summary.schema.json \
  --input "${corpus_out}/index.json"

test -s "${corpus_out}/good-http/result.json"
"${bin_path}" ci validate-json \
  --schema schemas/x07.mcp.corpus.result.schema.json \
  --input "${corpus_out}/good-http/result.json"

test -s "${corpus_out}/good-http/summary.json"
"${bin_path}" ci validate-json \
  --schema schemas/x07.mcp.conformance.summary.schema.json \
  --input "${corpus_out}/good-http/summary.json"
test -s "${corpus_out}/good-http/summary.junit.xml"
python3 scripts/ci/assert_junit_xml.py "${corpus_out}/good-http/summary.junit.xml"
test -s "${corpus_out}/good-http/summary.html"
test -s "${corpus_out}/good-http/summary.sarif.json"
"${bin_path}" ci validate-json \
  --schema schemas/x07.mcp.sarif.schema.json \
  --input "${corpus_out}/good-http/summary.sarif.json"

echo "==> doctor smoke"
ok_json="${tmp_dir}/doctor.ok.json"
"${bin_path}" doctor --machine json >"${ok_json}"
python3 scripts/ci/assert_doctor_json.py \
  "${ok_json}" true \
  os.uname=true \
  tmp.writable=true \
  shell.sh=true \
  url.reachable=true \
  cmd.present=true

bad_cmd="$(tr -d '\n' < fixtures/doctor/bad_cmd.txt)"
bad_cmd_json="${tmp_dir}/doctor.bad_cmd.json"
if "${bin_path}" doctor --machine json --cmd "${bad_cmd}" >"${bad_cmd_json}"; then
  echo "ERROR: expected doctor to fail for fixture cmd (got exit 0): ${bad_cmd}" >&2
  exit 1
fi
python3 scripts/ci/assert_doctor_json.py "${bad_cmd_json}" false cmd.present=false

bad_url="$(tr -d '\n' < fixtures/doctor/bad_url.txt)"
bad_url_json="${tmp_dir}/doctor.bad_url.json"
if "${bin_path}" doctor --machine json --url "${bad_url}" >"${bad_url_json}"; then
  echo "ERROR: expected doctor to fail for fixture url (got exit 0): ${bad_url}" >&2
  exit 1
fi
python3 scripts/ci/assert_doctor_json.py "${bad_url_json}" false url.reachable=false

echo "==> conformance fixtures"

run_conformance_fixture() (
  local fixture_id="${1:?missing fixture_id}"
  local fixture_mode="${2:?missing fixture_mode}"
  local fixture_url="${3:?missing fixture_url}"
  local expected_exit="${4:?missing expected_exit}"

  local fixture_out_dir="out/ci-conformance/${fixture_id}"
  rm -rf "${fixture_out_dir}"
  mkdir -p "${fixture_out_dir}"

  local server_log="${fixture_out_dir}/server.log"
  conformance/scripts/spawn_reference_http.sh "${fixture_id}" "${fixture_mode}" >"${server_log}" 2>&1 &
  local server_pid="$!"

  cleanup() {
    kill "${server_pid}" >/dev/null 2>&1 || true
    wait "${server_pid}" >/dev/null 2>&1 || true
  }
  trap cleanup EXIT

  if ! conformance/scripts/wait_for_http.sh "${fixture_url}" >/dev/null; then
    echo "ERROR: fixture failed to start: ${fixture_id} (${fixture_url})" >&2
    tail -n 200 "${server_log}" >&2 || true
    exit 1
  fi

  set +e
  "${bin_path}" scan \
    --url "${fixture_url}" \
    --baseline conformance/pinned/conformance-baseline.yml \
    --out "${fixture_out_dir}" \
    --machine json >"${fixture_out_dir}/summary.stdout.json"
  local exit_code="$?"
  set -e

  if [[ "${exit_code}" != "${expected_exit}" ]]; then
    echo "ERROR: scan exit code mismatch for ${fixture_id} (expected ${expected_exit}, got ${exit_code})" >&2
    if [[ -f "${fixture_out_dir}/summary.stdout.json" ]]; then
      echo "---- begin scan stdout ----" >&2
      cat "${fixture_out_dir}/summary.stdout.json" >&2 || true
      echo "---- end scan stdout ----" >&2
    fi
    tail -n 200 "${server_log}" >&2 || true
    exit 1
  fi

  "${bin_path}" ci validate-json \
    --schema schemas/x07.mcp.scan.report.schema.json \
    --input "${fixture_out_dir}/scan.json"

  "${bin_path}" ci validate-json \
    --schema schemas/x07.mcp.conformance.summary.schema.json \
    --input "${fixture_out_dir}/conformance.summary.json"

  test -s "${fixture_out_dir}/conformance.summary.junit.xml"
  python3 scripts/ci/assert_junit_xml.py "${fixture_out_dir}/conformance.summary.junit.xml"
  test -s "${fixture_out_dir}/conformance.summary.html"
  test -s "${fixture_out_dir}/conformance.summary.sarif.json"
  "${bin_path}" ci validate-json \
    --schema schemas/x07.mcp.sarif.schema.json \
    --input "${fixture_out_dir}/conformance.summary.sarif.json"

  if [[ "${fixture_id}" == "good-http" ]]; then
    echo "==> ci smoke (good-http)"
    local ci_out_dir="${fixture_out_dir}/ci"
    rm -rf "${ci_out_dir}"
    mkdir -p "${ci_out_dir}"

    set +e
    "${bin_path}" ci \
      --url "${fixture_url}" \
      --min-score 80 \
      --baseline conformance/pinned/conformance-baseline.yml \
      --out "${ci_out_dir}" \
      --machine json >"${ci_out_dir}/summary.stdout.json"
    local ci_exit="$?"
    set -e

    if [[ "${ci_exit}" != "0" ]]; then
      echo "ERROR: ci exit code mismatch for ${fixture_id} (expected 0, got ${ci_exit})" >&2
      cat "${ci_out_dir}/summary.stdout.json" >&2 || true
      exit 1
    fi

    "${bin_path}" ci validate-json \
      --schema schemas/x07.mcp.scan.report.schema.json \
      --input "${ci_out_dir}/scan.json"
  fi
)

fixture_pids=()
run_conformance_fixture good-http noauth http://127.0.0.1:18080/mcp 0 &
fixture_pids+=("$!")
run_conformance_fixture auth-http oauth http://127.0.0.1:18081/mcp 1 &
fixture_pids+=("$!")
run_conformance_fixture broken-http noauth http://127.0.0.1:18082/mcp 1 &
fixture_pids+=("$!")

fixture_failed=0
for pid in "${fixture_pids[@]}"; do
  if ! wait "${pid}"; then
    fixture_failed=1
  fi
done
if [[ "${fixture_failed}" == "1" ]]; then
  exit 1
fi

run_conformance_stdio_fixture() (
  local fixture_id="${1:?missing fixture_id}"
  local target_id="${2:?missing target_id}"
  local expected_exit="${3:?missing expected_exit}"

  local fixture_out_dir="out/ci-conformance/${fixture_id}"
  rm -rf "${fixture_out_dir}"
  mkdir -p "${fixture_out_dir}"

  set +e
  "${bin_path}" scan \
    --cmd "bash conformance/scripts/spawn_reference_stdio.sh ${target_id}" \
    --baseline conformance/pinned/conformance-baseline.yml \
    --out "${fixture_out_dir}" \
    --machine json >"${fixture_out_dir}/summary.stdout.json"
  local exit_code="$?"
  set -e

  if [[ "${exit_code}" != "${expected_exit}" ]]; then
    echo "ERROR: scan exit code mismatch for ${fixture_id} (expected ${expected_exit}, got ${exit_code})" >&2
    if [[ -f "${fixture_out_dir}/summary.stdout.json" ]]; then
      echo "---- begin scan stdout ----" >&2
      cat "${fixture_out_dir}/summary.stdout.json" >&2 || true
      echo "---- end scan stdout ----" >&2
    fi
    exit 1
  fi

  "${bin_path}" ci validate-json \
    --schema schemas/x07.mcp.scan.report.schema.json \
    --input "${fixture_out_dir}/scan.json"

  "${bin_path}" ci validate-json \
    --schema schemas/x07.mcp.conformance.summary.schema.json \
    --input "${fixture_out_dir}/conformance.summary.json"

  test -s "${fixture_out_dir}/conformance.summary.junit.xml"
  python3 scripts/ci/assert_junit_xml.py "${fixture_out_dir}/conformance.summary.junit.xml"
  test -s "${fixture_out_dir}/conformance.summary.html"
  test -s "${fixture_out_dir}/conformance.summary.sarif.json"
  "${bin_path}" ci validate-json \
    --schema schemas/x07.mcp.sarif.schema.json \
    --input "${fixture_out_dir}/conformance.summary.sarif.json"
)

stdio_pids=()
run_conformance_stdio_fixture good-stdio good-stdio 0 &
stdio_pids+=("$!")
run_conformance_stdio_fixture broken-stdio broken-stdio 1 &
stdio_pids+=("$!")

stdio_failed=0
for pid in "${stdio_pids[@]}"; do
  if ! wait "${pid}"; then
    stdio_failed=1
  fi
done
if [[ "${stdio_failed}" == "1" ]]; then
  exit 1
fi

echo "==> replay fixtures"

record_session="${tmp_dir}/replay.session.json"
rm -f "${record_session}"

run_replay_good() (
  local verify_out_dir="${tmp_dir}/replay-verify"
  rm -rf "${verify_out_dir}"
  mkdir -p "${verify_out_dir}"

  local good_log="${tmp_dir}/replay.good-http.server.log"
  conformance/scripts/spawn_reference_http.sh good-http noauth >"${good_log}" 2>&1 &
  local good_pid="$!"

  cleanup() {
    kill "${good_pid}" >/dev/null 2>&1 || true
    wait "${good_pid}" >/dev/null 2>&1 || true
  }
  trap cleanup EXIT

  if ! conformance/scripts/wait_for_http.sh http://127.0.0.1:18080/mcp >/dev/null; then
    echo "ERROR: good-http fixture failed to start for replay" >&2
    tail -n 200 "${good_log}" >&2 || true
    exit 1
  fi

  "${bin_path}" replay record \
    --url http://127.0.0.1:18080/mcp \
    --scenario smoke/basic \
    --sanitize auth,token \
    --auth-bearer test-token \
    --out "${record_session}" \
    --machine json >"${tmp_dir}/replay.record.stdout.json"

  test -s "${record_session}"
  "${bin_path}" ci validate-json \
    --schema schemas/x07.mcp.replay.session.schema.json \
    --input "${record_session}"

  "${bin_path}" replay verify \
    --session "${record_session}" \
    --url http://127.0.0.1:18080/mcp \
    --out "${verify_out_dir}" \
    --machine json >"${tmp_dir}/replay.verify.good.stdout.json"

  test -s "${verify_out_dir}/verify.json"
  "${bin_path}" ci validate-json \
    --schema schemas/x07.mcp.replay.verify.schema.json \
    --input "${verify_out_dir}/verify.json"
)

run_replay_broken() (
  local broken_log="${tmp_dir}/replay.broken-http.server.log"
  conformance/scripts/spawn_reference_http.sh broken-http noauth >"${broken_log}" 2>&1 &
  local broken_pid="$!"

  cleanup() {
    kill "${broken_pid}" >/dev/null 2>&1 || true
    wait "${broken_pid}" >/dev/null 2>&1 || true
  }
  trap cleanup EXIT

  if ! conformance/scripts/wait_for_http.sh http://127.0.0.1:18082/mcp >/dev/null; then
    echo "ERROR: broken-http fixture failed to start for replay" >&2
    tail -n 200 "${broken_log}" >&2 || true
    exit 1
  fi

  set +e
  "${bin_path}" replay verify \
    --session "${record_session}" \
    --url http://127.0.0.1:18082/mcp \
    --machine json >"${tmp_dir}/replay.verify.broken.stdout.json"
  local broken_exit="$?"
  set -e
  if [[ "${broken_exit}" != "1" ]]; then
    echo "ERROR: expected replay verify to fail against broken-http (exit 1), got ${broken_exit}" >&2
    cat "${tmp_dir}/replay.verify.broken.stdout.json" >&2 || true
    tail -n 200 "${broken_log}" >&2 || true
    exit 1
  fi

  test -s "${tmp_dir}/replay.verify.broken.stdout.json"
  "${bin_path}" ci validate-json \
    --schema schemas/x07.mcp.replay.verify.schema.json \
    --input "${tmp_dir}/replay.verify.broken.stdout.json"
)

run_replay_good
run_replay_broken

echo "==> replay fixtures (stdio)"

record_stdio_session="${tmp_dir}/replay.stdio.session.json"
rm -f "${record_stdio_session}"

run_replay_stdio_good() (
  local verify_out_dir="${tmp_dir}/replay-verify-stdio"
  rm -rf "${verify_out_dir}"
  mkdir -p "${verify_out_dir}"

  "${bin_path}" replay record \
    --cmd "bash conformance/scripts/spawn_reference_stdio.sh good-stdio" \
    --scenario smoke/basic \
    --sanitize auth,token \
    --out "${record_stdio_session}" \
    --machine json >"${tmp_dir}/replay.record.stdio.stdout.json"

  test -s "${record_stdio_session}"
  "${bin_path}" ci validate-json \
    --schema schemas/x07.mcp.replay.session.schema.json \
    --input "${record_stdio_session}"

  test -s "${record_stdio_session}.c2s.jsonl"
  test -s "${record_stdio_session}.s2c.jsonl"

  "${bin_path}" replay verify \
    --session "${record_stdio_session}" \
    --cmd "bash conformance/scripts/spawn_reference_stdio.sh good-stdio" \
    --out "${verify_out_dir}" \
    --machine json >"${tmp_dir}/replay.verify.stdio.good.stdout.json"

  test -s "${verify_out_dir}/verify.json"
  "${bin_path}" ci validate-json \
    --schema schemas/x07.mcp.replay.verify.schema.json \
    --input "${verify_out_dir}/verify.json"
)

run_replay_stdio_broken() (
  set +e
  "${bin_path}" replay verify \
    --session "${record_stdio_session}" \
    --cmd "bash conformance/scripts/spawn_reference_stdio.sh broken-stdio" \
    --machine json >"${tmp_dir}/replay.verify.stdio.broken.stdout.json"
  local broken_exit="$?"
  set -e
  if [[ "${broken_exit}" != "1" ]]; then
    echo "ERROR: expected replay verify to fail against broken-stdio (exit 1), got ${broken_exit}" >&2
    cat "${tmp_dir}/replay.verify.stdio.broken.stdout.json" >&2 || true
    exit 1
  fi

  test -s "${tmp_dir}/replay.verify.stdio.broken.stdout.json"
  "${bin_path}" ci validate-json \
    --schema schemas/x07.mcp.replay.verify.schema.json \
    --input "${tmp_dir}/replay.verify.stdio.broken.stdout.json"
)

run_replay_stdio_good
run_replay_stdio_broken

echo "==> trust fixtures"

trust_good_out="${tmp_dir}/trust.good.json"
"${bin_path}" trust verify \
  --server-json trust/fixtures/server-good.json \
  --out "${trust_good_out}" \
  --machine json >"${tmp_dir}/trust.good.stdout.json"

test -s "${trust_good_out}"
"${bin_path}" ci validate-json \
  --schema schemas/x07.mcp.trust.summary.schema.json \
  --input "${trust_good_out}"

trust_bad_out="${tmp_dir}/trust.bad.json"
set +e
"${bin_path}" trust verify \
  --server-json trust/fixtures/server-bad.json \
  --out "${trust_bad_out}" \
  --machine json >"${tmp_dir}/trust.bad.stdout.json"
trust_bad_exit="$?"
set -e
if [[ "${trust_bad_exit}" != "1" ]]; then
  echo "ERROR: expected trust verify to fail for degraded fixture (exit 1), got ${trust_bad_exit}" >&2
  cat "${tmp_dir}/trust.bad.stdout.json" >&2 || true
  exit 1
fi

test -s "${trust_bad_out}"
"${bin_path}" ci validate-json \
  --schema schemas/x07.mcp.trust.summary.schema.json \
  --input "${trust_bad_out}"

echo "==> bundle fixtures"

bundle_good_out="${tmp_dir}/bundle.good.json"
"${bin_path}" bundle verify \
  --server-json trust/fixtures/server-good.json \
  --mcpb trust/fixtures/bundle-good.mcpb \
  --out "${bundle_good_out}" \
  --machine json >"${tmp_dir}/bundle.good.stdout.json"

test -s "${bundle_good_out}"
"${bin_path}" ci validate-json \
  --schema schemas/x07.mcp.bundle.verify.schema.json \
  --input "${bundle_good_out}"

bundle_bad_out="${tmp_dir}/bundle.bad.json"
set +e
"${bin_path}" bundle verify \
  --server-json trust/fixtures/server-good.json \
  --mcpb trust/fixtures/bundle-bad.mcpb \
  --out "${bundle_bad_out}" \
  --machine json >"${tmp_dir}/bundle.bad.stdout.json"
bundle_bad_exit="$?"
set -e
if [[ "${bundle_bad_exit}" != "1" ]]; then
  echo "ERROR: expected bundle verify to fail for sha mismatch (exit 1), got ${bundle_bad_exit}" >&2
  cat "${tmp_dir}/bundle.bad.stdout.json" >&2 || true
  exit 1
fi

test -s "${bundle_bad_out}"
"${bin_path}" ci validate-json \
  --schema schemas/x07.mcp.bundle.verify.schema.json \
  --input "${bundle_bad_out}"

bundle_large_dir="${tmp_dir}/bundle.large"
mkdir -p "${bundle_large_dir}"

bundle_large_mcpb="${bundle_large_dir}/bundle-large.mcpb"
bundle_large_server_json="${bundle_large_dir}/server-large.json"

python3 - "${bundle_large_mcpb}" "${bundle_large_server_json}" <<'PY'
import hashlib
import json
import sys
from pathlib import Path

mcpb_path = Path(sys.argv[1])
server_json_path = Path(sys.argv[2])

size = 5_000_000
data = bytearray(size)
data[0] = ord("P")
data[1] = ord("K")
mcpb_path.write_bytes(data)

sha = hashlib.sha256(data).hexdigest()
server_doc = {
    "$schema": "https://static.modelcontextprotocol.io/schemas/2025-12-11/server.schema.json",
    "name": "io.x07/mcptest-bundle-large",
    "version": "0.1.0",
    "description": "Synthetic large mcpb fixture to smoke bundle verify fuel budget.",
    "packages": [
        {
            "registryType": "mcpb",
            "identifier": "io.x07/mcptest-bundle-large",
            "version": "0.1.0",
            "fileSha256": sha,
            "transport": {"type": "stdio"},
        }
    ],
}
server_json_path.write_text(json.dumps(server_doc, indent=2) + "\n", encoding="utf-8")
PY

bundle_large_out="${bundle_large_dir}/bundle.large.json"
"${bin_path}" bundle verify \
  --server-json "${bundle_large_server_json}" \
  --mcpb "${bundle_large_mcpb}" \
  --out "${bundle_large_out}" \
  --machine json >"${bundle_large_dir}/bundle.large.stdout.json"

test -s "${bundle_large_out}"
"${bin_path}" ci validate-json \
  --schema schemas/x07.mcp.bundle.verify.schema.json \
  --input "${bundle_large_out}"
