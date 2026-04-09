#!/usr/bin/env bash
set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
cd "${repo_root}"

export HARDPROOF_TOKENIZERS_DIR="${repo_root}/tokenizers"

echo "==> repo hygiene"
python3 scripts/ci/check_repo_hygiene.py >/dev/null

echo "==> action contract"
bash action/tests/test_validate_inputs.sh >/dev/null
test -s hardproof-scan/action.yml

echo "==> fmt"
while IFS= read -r path; do
  x07 fmt --input "${path}" --check --report-json >/dev/null
done < <(find cli/src score_core/src score_core/tests -name '*.x07.json' -print | LC_ALL=C sort)

echo "==> version consistency"
python3 scripts/ci/check_version_consistency.py >/dev/null

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

echo "==> hardproof helper tests"
x07 test --all --manifest tests/tests.json --json=off >/dev/null

echo "==> generated SM tests"
x07 test --all --manifest cli/src/gen/sm/tests.manifest.json --json=off >/dev/null

echo "==> score core: verify coverage"
x07 verify \
  --coverage \
  --project score_core/x07.json \
  --entry scan.score.overall_score_n_or_neg1_v1 \
  --json=off >/dev/null

x07 verify \
  --coverage \
  --project score_core/x07.json \
  --entry scan.score.partial_score_n_or_neg1_v1 \
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

bin_path="${repo_root}/${tmp_dir}/hardproof"
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
test -s "${release_extract_dir}/tokenizers/cl100k_base.table.bin"
test -s "${release_extract_dir}/tokenizers/o200k_base.table.bin"

echo "==> cli smoke"
"${bin_path}" --help >/dev/null

run_help_smoke() (
  local label="${1:?missing label}"
  shift

  set +e
  "${bin_path}" "$@" >/dev/null
  local help_exit="$?"
  set -e

  if [[ "${help_exit}" != "0" ]]; then
    echo "ERROR: hardproof ${label} failed (exit ${help_exit})" >&2
    exit 1
  fi
)

run_help_smoke "scan --help" scan --help
run_help_smoke "ci --help" ci --help
run_help_smoke "ci validate-fixtures --help" ci validate-fixtures --help
run_help_smoke "ci validate-json --help" ci validate-json --help
run_help_smoke "doctor --help" doctor --help
run_help_smoke "report summary --help" report summary --help
run_help_smoke "report html --help" report html --help
run_help_smoke "report sarif --help" report sarif --help
run_help_smoke "conformance run --help" conformance run --help
run_help_smoke "replay record --help" replay record --help
run_help_smoke "replay verify --help" replay verify --help
run_help_smoke "corpus run --help" corpus run --help
run_help_smoke "corpus render --help" corpus render --help
run_help_smoke "trust verify --help" trust verify --help
run_help_smoke "bundle verify --help" bundle verify --help

scan_help_out="${tmp_dir}/scan.help.txt"
"${bin_path}" scan --help >"${scan_help_out}"
grep -q -- '--baseline' "${scan_help_out}"
grep -q -- '--env-file' "${scan_help_out}"
grep -q -- '--full-suite' "${scan_help_out}"
grep -q -- '--metrics' "${scan_help_out}"
grep -q -- '--score-preview' "${scan_help_out}"
grep -q -- '--max-avg-tool-description-tokens' "${scan_help_out}"
grep -q -- '--max-tool-count' "${scan_help_out}"
grep -q -- '--perf-profile' "${scan_help_out}"
grep -q -- '--no-live' "${scan_help_out}"
grep -q -- '--event-log' "${scan_help_out}"
grep -q -- '--render-interval-ms' "${scan_help_out}"
grep -q -- '--require-trust-for-full-score' "${scan_help_out}"
grep -q -- '--transport' "${scan_help_out}"
grep -q -- '--tokenizer' "${scan_help_out}"
grep -q -- '--usage-mode' "${scan_help_out}"
grep -q -- '--token-trace' "${scan_help_out}"

ci_help_out="${tmp_dir}/ci.help.txt"
"${bin_path}" ci --help >"${ci_help_out}"
grep -q -- '--allow-partial-score' "${ci_help_out}"
grep -q -- '--max-input-schema-tokens' "${ci_help_out}"
grep -q -- '--max-metadata-to-payload-ratio-pct' "${ci_help_out}"
grep -q -- '--max-avg-tool-description-tokens' "${ci_help_out}"
grep -q -- '--max-response-p95-tokens' "${ci_help_out}"
grep -q -- '--max-tool-catalog-tokens' "${ci_help_out}"
grep -q -- '--max-tool-count' "${ci_help_out}"
grep -q -- '--min-dimension' "${ci_help_out}"
grep -q -- '--policy' "${ci_help_out}"
grep -q -- '--perf-profile' "${ci_help_out}"
grep -q -- '--tokenizer' "${ci_help_out}"
grep -q -- '--usage-mode' "${ci_help_out}"
grep -q -- '--token-trace' "${ci_help_out}"

set +e
"${bin_path}" explain PERF-TOOLS-CALL-FAILED >/dev/null
explain_perf_exit="$?"
set -e
if [[ "${explain_perf_exit}" != "0" ]]; then
  echo "ERROR: hardproof explain PERF-TOOLS-CALL-FAILED failed (exit ${explain_perf_exit})" >&2
  exit 1
fi

set +e
"${bin_path}" explain USAGE-INSTRUCTION-DUPLICATION >/dev/null
explain_usage_dup_exit="$?"
set -e
if [[ "${explain_usage_dup_exit}" != "0" ]]; then
  echo "ERROR: hardproof explain USAGE-INSTRUCTION-DUPLICATION failed (exit ${explain_usage_dup_exit})" >&2
  exit 1
fi

set +e
"${bin_path}" explain TRUST-NOT-EVALUABLE >/dev/null
explain_trust_not_evaluable_exit="$?"
set -e
if [[ "${explain_trust_not_evaluable_exit}" != "0" ]]; then
  echo "ERROR: hardproof explain TRUST-NOT-EVALUABLE failed (exit ${explain_trust_not_evaluable_exit})" >&2
  exit 1
fi

set +e
"${bin_path}" explain BUNDLE-MISSING >/dev/null
explain_bundle_missing_exit="$?"
set -e
if [[ "${explain_bundle_missing_exit}" != "0" ]]; then
  echo "ERROR: hardproof explain BUNDLE-MISSING failed (exit ${explain_bundle_missing_exit})" >&2
  exit 1
fi

set +e
"${bin_path}" explain SIGNATURE-NOT-PRESENT >/dev/null
explain_signature_not_present_exit="$?"
set -e
if [[ "${explain_signature_not_present_exit}" != "0" ]]; then
  echo "ERROR: hardproof explain SIGNATURE-NOT-PRESENT failed (exit ${explain_signature_not_present_exit})" >&2
  exit 1
fi

set +e
"${bin_path}" explain TLOG-NOT-PRESENT >/dev/null
explain_tlog_not_present_exit="$?"
set -e
if [[ "${explain_tlog_not_present_exit}" != "0" ]]; then
  echo "ERROR: hardproof explain TLOG-NOT-PRESENT failed (exit ${explain_tlog_not_present_exit})" >&2
  exit 1
fi

set +e
"${bin_path}" explain CONFORMANCE.FAIL >/dev/null
explain_conformance_fail_exit="$?"
set -e
if [[ "${explain_conformance_fail_exit}" != "0" ]]; then
  echo "ERROR: hardproof explain CONFORMANCE.FAIL failed (exit ${explain_conformance_fail_exit})" >&2
  exit 1
fi

set +e
"${bin_path}" explain CONFORMANCE.sample-check >/dev/null
explain_conformance_dynamic_exit="$?"
set -e
if [[ "${explain_conformance_dynamic_exit}" != "0" ]]; then
  echo "ERROR: hardproof explain CONFORMANCE.<check-id> failed (exit ${explain_conformance_dynamic_exit})" >&2
  exit 1
fi

set +e
"${bin_path}" explain DOES-NOT-EXIST >/dev/null 2>&1
explain_unknown_exit="$?"
set -e
if [[ "${explain_unknown_exit}" != "2" ]]; then
  echo "ERROR: hardproof explain unknown-code regression (expected 2, got ${explain_unknown_exit})" >&2
  exit 1
fi

echo "==> cli regression smoke"

run_cli_regression_smoke() (
  local server_log="${tmp_dir}/cli-regression.server.log"
  conformance/scripts/spawn_reference_http.sh good-http noauth >"${server_log}" 2>&1 &
  local server_pid="$!"

  cleanup() {
    kill "${server_pid}" >/dev/null 2>&1 || true
    wait "${server_pid}" >/dev/null 2>&1 || true
  }
  trap cleanup EXIT

  if ! conformance/scripts/wait_for_http.sh http://127.0.0.1:18080/mcp >/dev/null; then
    echo "ERROR: regression fixture failed to start: good-http (http://127.0.0.1:18080/mcp)" >&2
    tail -n 200 "${server_log}" >&2 || true
    exit 1
  fi

  local abs_root
  abs_root="$(mktemp -d "${tmp_dir}/cli-abs.XXXXXX")"
  abs_root="$(cd "${abs_root}" && pwd)"

  local abs_scan_out="${abs_root}/scan"
  set +e
  "${bin_path}" scan \
    --url http://127.0.0.1:18080/mcp \
    --transport http \
    --out "${abs_scan_out}" \
    --format json >"${tmp_dir}/scan.abs.stdout.json"
  local scan_abs_exit="$?"
  set -e
  if [[ "${scan_abs_exit}" != "0" ]]; then
    echo "ERROR: hardproof scan absolute --out regression (expected 0, got ${scan_abs_exit})" >&2
    cat "${tmp_dir}/scan.abs.stdout.json" >&2 || true
    tail -n 200 "${server_log}" >&2 || true
    exit 1
  fi
  test -s "${abs_scan_out}/scan.json"
  test -s "${abs_scan_out}/scan.events.jsonl"

  local abs_exact_usage_out="${abs_root}/scan-usage-exact"
  set +e
  "${bin_path}" scan \
    --url http://127.0.0.1:18080/mcp \
    --transport http \
    --out "${abs_exact_usage_out}" \
    --usage-mode exact \
    --tokenizer openai:o200k_base \
    --machine json >"${tmp_dir}/scan.usage_exact.stdout.json"
  local scan_exact_usage_exit="$?"
  set -e
  if [[ "${scan_exact_usage_exit}" != "0" ]]; then
    echo "ERROR: hardproof scan exact usage regression (expected 0, got ${scan_exact_usage_exit})" >&2
    cat "${tmp_dir}/scan.usage_exact.stdout.json" >&2 || true
    tail -n 200 "${server_log}" >&2 || true
    exit 1
  fi
  test -s "${abs_exact_usage_out}/scan.json"

  python3 - "${abs_exact_usage_out}/scan.json" <<'PY'
import json
import sys

with open(sys.argv[1], "r", encoding="utf-8") as f:
    report = json.load(f)

usage = report["usage_metrics"]
assert usage["usage_mode"] == "tokenizer_exact", usage
assert usage["usage_confidence"] == "high", usage
assert usage["tokenizer_id"] == "openai:o200k_base", usage
assert isinstance(usage["tool_catalog_tokens_exact"], int), usage
assert usage["tool_catalog_tokens_exact"] >= 0, usage
PY

  local abs_xdg_data_home="${abs_root}/xdg-data-home"
  mkdir -p "${abs_xdg_data_home}/hardproof/tokenizers"
  cp "${repo_root}/tokenizers/"*.table.bin "${abs_xdg_data_home}/hardproof/tokenizers/"

  local abs_xdg_usage_out="${abs_root}/scan-usage-xdg"
  local abs_isolated_cwd="${abs_root}/isolated-cwd"
  mkdir -p "${abs_isolated_cwd}"
  set +e
  (
    cd "${abs_isolated_cwd}"
    HARDPROOF_TOKENIZERS_DIR="" XDG_DATA_HOME="${abs_xdg_data_home}" "${bin_path}" scan \
      --url http://127.0.0.1:18080/mcp \
      --transport http \
      --out "${abs_xdg_usage_out}" \
      --usage-mode exact \
      --tokenizer openai:o200k_base \
      --machine json
  ) >"${tmp_dir}/scan.usage_xdg.stdout.json"
  local scan_xdg_usage_exit="$?"
  set -e
  if [[ "${scan_xdg_usage_exit}" != "0" ]]; then
    echo "ERROR: hardproof scan exact usage via XDG_DATA_HOME regression (expected 0, got ${scan_xdg_usage_exit})" >&2
    cat "${tmp_dir}/scan.usage_xdg.stdout.json" >&2 || true
    tail -n 200 "${server_log}" >&2 || true
    exit 1
  fi
  test -s "${abs_xdg_usage_out}/scan.json"

  python3 - "${abs_xdg_usage_out}/scan.json" <<'PY'
import json
import sys

with open(sys.argv[1], "r", encoding="utf-8") as f:
    report = json.load(f)

usage = report["usage_metrics"]
assert usage["usage_mode"] == "tokenizer_exact", usage
assert usage["usage_confidence"] == "high", usage
assert usage["tokenizer_id"] == "openai:o200k_base", usage
assert isinstance(usage["tool_catalog_tokens_exact"], int), usage
assert usage["tool_catalog_tokens_exact"] >= 0, usage
PY

  local abs_full_suite_out="${abs_root}/scan-full-suite"
  set +e
  "${bin_path}" scan \
    --url http://127.0.0.1:18080/mcp \
    --transport http \
    --full-suite \
    --out "${abs_full_suite_out}" \
    --machine json >"${tmp_dir}/scan.full_suite.stdout.json"
  local scan_full_suite_exit="$?"
  set -e
  if [[ "${scan_full_suite_exit}" != "0" ]]; then
    echo "ERROR: hardproof scan --full-suite regression (expected 0, got ${scan_full_suite_exit})" >&2
    cat "${tmp_dir}/scan.full_suite.stdout.json" >&2 || true
    tail -n 200 "${server_log}" >&2 || true
    exit 1
  fi
  test -s "${abs_full_suite_out}/scan.json"
  python3 - "${abs_full_suite_out}/scan.json" <<'PY'
import json
import sys

with open(sys.argv[1], "r", encoding="utf-8") as f:
    report = json.load(f)

conformance = next(dim for dim in report["dimensions"] if dim["name"] == "conformance")
metrics = conformance["metrics"]
assert metrics["full_suite"] is True, metrics
PY

  local abs_conformance_out="${abs_root}/conformance"
  set +e
  "${bin_path}" conformance run \
    --url http://127.0.0.1:18080/mcp \
    --out "${abs_conformance_out}" \
    --machine json >"${tmp_dir}/conformance.abs.stdout.json"
  local conformance_abs_exit="$?"
  set -e
  if [[ "${conformance_abs_exit}" != "0" ]]; then
    echo "ERROR: hardproof conformance absolute --out regression (expected 0, got ${conformance_abs_exit})" >&2
    cat "${tmp_dir}/conformance.abs.stdout.json" >&2 || true
    tail -n 200 "${server_log}" >&2 || true
    exit 1
  fi
  test -s "${abs_conformance_out}/summary.json"
  test -s "${abs_conformance_out}/summary.junit.xml"

  set +e
  "${bin_path}" ci \
    --url http://127.0.0.1:18080/mcp \
    --out "${tmp_dir}/ci-thresholds" \
    --min-score 50 \
    --max-critical 0 \
    --max-warning 10 \
    --machine json >"${tmp_dir}/ci.thresholds.stdout.json"
  local ci_threshold_exit="$?"
  set -e
  if [[ "${ci_threshold_exit}" != "1" ]]; then
    echo "ERROR: hardproof ci partial-default regression (expected 1, got ${ci_threshold_exit})" >&2
    cat "${tmp_dir}/ci.thresholds.stdout.json" >&2 || true
    tail -n 200 "${server_log}" >&2 || true
    exit 1
  fi

  python3 - "${tmp_dir}/ci-thresholds/scan.json" <<'PY'
import json
import sys

with open(sys.argv[1], "r", encoding="utf-8") as f:
    report = json.load(f)

assert report["score_mode"] == "partial", report
assert report["score_truth_status"] == "partial", report
PY

  set +e
  "${bin_path}" ci \
    --url http://127.0.0.1:18080/mcp \
    --out "${tmp_dir}/ci-allow-partial" \
    --min-score 50 \
    --max-critical 0 \
    --max-warning 10 \
    --allow-partial-score \
    --machine json >"${tmp_dir}/ci.allow_partial.stdout.json"
  local ci_allow_partial_exit="$?"
  set -e
  if [[ "${ci_allow_partial_exit}" != "0" ]]; then
    echo "ERROR: hardproof ci --allow-partial-score regression (expected 0, got ${ci_allow_partial_exit})" >&2
    cat "${tmp_dir}/ci.allow_partial.stdout.json" >&2 || true
    tail -n 200 "${server_log}" >&2 || true
    exit 1
  fi

  local ci_policy_path="${tmp_dir}/ci.policy.json"
  cat >"${ci_policy_path}" <<'JSON'
{
  "min_score": 50,
  "max_critical": 0,
  "max_warning": 10,
  "allow_partial_score": true
}
JSON

  set +e
  "${bin_path}" ci \
    --url http://127.0.0.1:18080/mcp \
    --out "${tmp_dir}/ci-policy" \
    --policy "${ci_policy_path}" \
    --machine json >"${tmp_dir}/ci.policy.stdout.json"
  local ci_policy_exit="$?"
  set -e
  if [[ "${ci_policy_exit}" != "0" ]]; then
    echo "ERROR: hardproof ci --policy regression (expected 0, got ${ci_policy_exit})" >&2
    cat "${tmp_dir}/ci.policy.stdout.json" >&2 || true
    tail -n 200 "${server_log}" >&2 || true
    exit 1
  fi
  test -s "${tmp_dir}/ci-policy/scan.json"

  set +e
  "${bin_path}" ci \
    --url http://127.0.0.1:18080/mcp \
    --out "${tmp_dir}/ci-min-dimension-pass" \
    --min-score 0 \
    --max-critical 100 \
    --max-warning 100 \
    --allow-partial-score \
    --min-dimension conformance=0,security=0 \
    --machine json >"${tmp_dir}/ci.min_dimension.pass.stdout.json"
  local ci_min_dimension_pass_exit="$?"
  set -e
  if [[ "${ci_min_dimension_pass_exit}" != "0" ]]; then
    echo "ERROR: hardproof ci --min-dimension pass regression (expected 0, got ${ci_min_dimension_pass_exit})" >&2
    cat "${tmp_dir}/ci.min_dimension.pass.stdout.json" >&2 || true
    tail -n 200 "${server_log}" >&2 || true
    exit 1
  fi

  set +e
  "${bin_path}" ci \
    --url http://127.0.0.1:18080/mcp \
    --out "${tmp_dir}/ci-min-dimension-fail" \
    --min-score 0 \
    --max-critical 100 \
    --max-warning 100 \
    --allow-partial-score \
    --min-dimension trust=0 \
    >"${tmp_dir}/ci.min_dimension.fail.stdout.txt"
  local ci_min_dimension_fail_exit="$?"
  set -e
  if [[ "${ci_min_dimension_fail_exit}" != "1" ]]; then
    echo "ERROR: hardproof ci --min-dimension fail regression (expected 1, got ${ci_min_dimension_fail_exit})" >&2
    cat "${tmp_dir}/ci.min_dimension.fail.stdout.txt" >&2 || true
    tail -n 200 "${server_log}" >&2 || true
    exit 1
  fi
  grep -q -- 'error: hardproof ci policy failed' "${tmp_dir}/ci.min_dimension.fail.stdout.txt"
  grep -q -- 'min_dimension: trust=0' "${tmp_dir}/ci.min_dimension.fail.stdout.txt"

  local scan_require_trust_out="${tmp_dir}/scan-require-trust"
  set +e
  "${bin_path}" scan \
    --url http://127.0.0.1:18080/mcp \
    --out "${scan_require_trust_out}" \
    --require-trust-for-full-score \
    --machine json >"${tmp_dir}/scan.require_trust.stdout.json"
  local scan_require_trust_exit="$?"
  set -e
  if [[ "${scan_require_trust_exit}" != "0" ]]; then
    echo "ERROR: hardproof scan --require-trust-for-full-score regression (expected 0, got ${scan_require_trust_exit})" >&2
    cat "${tmp_dir}/scan.require_trust.stdout.json" >&2 || true
    tail -n 200 "${server_log}" >&2 || true
    exit 1
  fi

  python3 - "${scan_require_trust_out}/scan.json" <<'PY'
import json
import sys

with open(sys.argv[1], "r", encoding="utf-8") as f:
    report = json.load(f)

assert report["score_truth_status"] == "partial", report
assert report["score_mode"] == "partial", report
assert report["score_available"] is True, report
assert report["overall_score"] is None, report
assert isinstance(report["partial_score"], int), report
assert 0 <= report["partial_score"] <= 100, report
assert "TRUST-NOT-EVALUABLE" in report["gating_reasons"], report
assert "TRUST-NOT-EVALUABLE" in report["partial_reasons"], report
assert "SERVER-JSON-MISSING" in report["gating_reasons"], report
assert "SERVER-JSON-MISSING" in report["partial_reasons"], report
assert report["unknown_dimensions"] == ["trust"], report
assert report["dimension_coverage"]["trust"] is False, report
assert report["score_weight_present"] == 80, report
PY

  local scan_full_score_out="${tmp_dir}/scan-full-score"
  set +e
  "${bin_path}" scan \
    --url http://127.0.0.1:18080/mcp \
    --server-json trust/fixtures/server-good.json \
    --mcpb trust/fixtures/bundle-good.mcpb \
    --out "${scan_full_score_out}" \
    --machine json >"${tmp_dir}/scan.full_score.stdout.json"
  local scan_full_score_exit="$?"
  set -e
  if [[ "${scan_full_score_exit}" != "0" ]]; then
    echo "ERROR: hardproof scan trust-aware full-score regression (expected 0, got ${scan_full_score_exit})" >&2
    cat "${tmp_dir}/scan.full_score.stdout.json" >&2 || true
    tail -n 200 "${server_log}" >&2 || true
    exit 1
  fi

  python3 - "${scan_full_score_out}/scan.json" <<'PY'
import json
import sys

with open(sys.argv[1], "r", encoding="utf-8") as f:
    report = json.load(f)

assert report["score_truth_status"] == "publishable", report
assert report["score_mode"] == "full", report
assert isinstance(report["overall_score"], int), report
assert report["dimension_coverage"]["trust"] is True, report
assert report["score_weight_present"] == 100, report
assert report["usage_metrics"]["estimator_version"] == "v1", report
PY

  local scan_perf_profile_out="${tmp_dir}/scan-perf-profile-smoke"
  set +e
  "${bin_path}" scan \
    --url http://127.0.0.1:18080/mcp \
    --out "${scan_perf_profile_out}" \
    --perf-profile smoke \
    --machine json >"${tmp_dir}/scan.perf_profile.stdout.json"
  local scan_perf_profile_exit="$?"
  set -e
  if [[ "${scan_perf_profile_exit}" != "0" ]]; then
    echo "ERROR: hardproof scan --perf-profile smoke regression (expected 0, got ${scan_perf_profile_exit})" >&2
    cat "${tmp_dir}/scan.perf_profile.stdout.json" >&2 || true
    tail -n 200 "${server_log}" >&2 || true
    exit 1
  fi

  python3 - "${scan_perf_profile_out}/scan.json" <<'PY'
import json
import sys

with open(sys.argv[1], "r", encoding="utf-8") as f:
    report = json.load(f)

performance = next(dim for dim in report["dimensions"] if dim["name"] == "performance")
metrics = performance["metrics"]
assert metrics["workload_profile"] == "smoke", metrics
assert metrics["ping_sample_count"] == 6, metrics
assert metrics["tool_call_sample_count"] == 4, metrics
assert metrics["concurrent_slots"] == 2, metrics
assert metrics["tool_call_confidence"] == "low", metrics
PY

  set +e
  "${bin_path}" ci \
    --url http://127.0.0.1:18080/mcp \
    --out "${tmp_dir}/ci-new-usage-thresholds" \
    --min-score 50 \
    --max-critical 0 \
    --max-warning 10 \
    --allow-partial-score \
    --max-avg-tool-description-tokens 500 \
    --max-tool-count 50 \
    --max-metadata-to-payload-ratio-pct 500 \
    --max-tool-catalog-tokens 5000 \
    --max-response-p95-tokens 500 \
    --max-input-schema-tokens 5000 \
    --machine json >"${tmp_dir}/ci.new_usage_thresholds.stdout.json"
  local ci_new_usage_thresholds_exit="$?"
  set -e
  if [[ "${ci_new_usage_thresholds_exit}" != "0" ]]; then
    echo "ERROR: hardproof ci new usage threshold regression (expected 0, got ${ci_new_usage_thresholds_exit})" >&2
    cat "${tmp_dir}/ci.new_usage_thresholds.stdout.json" >&2 || true
    tail -n 200 "${server_log}" >&2 || true
    exit 1
  fi

  python3 - "${tmp_dir}/ci-new-usage-thresholds/scan.json" <<'PY'
import json
import sys

with open(sys.argv[1], "r", encoding="utf-8") as f:
    report = json.load(f)

usage = report["usage_metrics"]
assert usage["avg_tool_description_tokens"] == 3, usage
assert usage["tool_count"] == 1, usage
assert usage["metadata_to_payload_ratio_pct"] == 391, usage
PY

  set +e
  "${bin_path}" ci \
    --url http://127.0.0.1:18080/mcp \
    --out "${tmp_dir}/ci-require-pass" \
    --min-score 50 \
    --max-critical 0 \
    --max-warning 10 \
    --require-pass \
    --machine json >"${tmp_dir}/ci.require_pass.stdout.json"
  local ci_require_pass_exit="$?"
  set -e
  if [[ "${ci_require_pass_exit}" != "1" ]]; then
    echo "ERROR: hardproof ci --require-pass regression (expected 1, got ${ci_require_pass_exit})" >&2
    cat "${tmp_dir}/ci.require_pass.stdout.json" >&2 || true
    tail -n 200 "${server_log}" >&2 || true
    exit 1
  fi

  set +e
  "${bin_path}" ci \
    --url http://127.0.0.1:18080/mcp \
    --out "${tmp_dir}/ci-require-full-score" \
    --min-score 50 \
    --max-critical 0 \
    --max-warning 10 \
    --require-trust-for-full-score \
    --machine json >"${tmp_dir}/ci.require_full_score.stdout.json"
  local ci_require_full_score_exit="$?"
  set -e
  if [[ "${ci_require_full_score_exit}" != "1" ]]; then
    echo "ERROR: hardproof ci --require-trust-for-full-score regression (expected 1, got ${ci_require_full_score_exit})" >&2
    cat "${tmp_dir}/ci.require_full_score.stdout.json" >&2 || true
    tail -n 200 "${server_log}" >&2 || true
    exit 1
  fi
)

run_cli_regression_smoke

echo "==> schema fixtures"
"${bin_path}" ci validate-fixtures

echo "==> scan report fixtures"
python3 scripts/ci/check_scan_report_fixtures.py >/dev/null

echo "==> example artifacts"
./scripts/refresh_example_artifacts.sh --check --bin "${bin_path}" >/dev/null
python3 scripts/ci/check_example_artifacts.py "${bin_path}"
python3 scripts/ci/assert_scan_report_consistency.py docs/examples/hardproof-scan/scan.json
python3 scripts/ci/assert_scan_report_consistency.py docs/examples/hardproof-scan-full/scan.json

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

echo "==> corpus render smoke"
corpus_render_out="${corpus_out}/report.html"
rm -f "${corpus_render_out}"

set +e
"${bin_path}" corpus render \
  --input "${corpus_out}/index.json" \
  --out "${corpus_out}" \
  --machine json >"${tmp_dir}/corpus.render.stdout.json"
corpus_render_exit="$?"
set -e
if [[ "${corpus_render_exit}" != "0" ]]; then
  echo "ERROR: corpus render exit code mismatch (expected 0, got ${corpus_render_exit})" >&2
  cat "${tmp_dir}/corpus.render.stdout.json" >&2 || true
  exit 1
fi

test -s "${corpus_render_out}"
grep -q '<h1>Hardproof corpus report</h1>' "${corpus_render_out}"

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
  python3 scripts/ci/assert_scan_report_consistency.py "${fixture_out_dir}/scan.json"

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

  if [[ "${fixture_id}" == "auth-http" ]]; then
    python3 - "${fixture_out_dir}/scan.json" <<'PY'
import json
import sys

with open(sys.argv[1], "r", encoding="utf-8") as f:
    report = json.load(f)

security = next(dim for dim in report["dimensions"] if dim["name"] == "security")
metrics = security["metrics"]
assert metrics["auth_protection_status"] == "required", metrics
assert metrics["auth_challenge_status_code"] == 401, metrics
codes = {finding["code"] for finding in report["findings"]}
assert "SEC-AUTH-MISCONFIG" not in codes, codes
PY
  fi

  if [[ "${fixture_id}" == "good-http" ]]; then
    echo "==> ci smoke (good-http)"
    local ci_out_dir="${fixture_out_dir}/ci"
    rm -rf "${ci_out_dir}"
    mkdir -p "${ci_out_dir}"

    set +e
    "${bin_path}" ci \
      --url "${fixture_url}" \
      --min-score 80 \
      --allow-partial-score \
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
    python3 scripts/ci/assert_scan_report_consistency.py "${ci_out_dir}/scan.json"

    echo "==> scan overlays smoke (good-http)"
    local overlay_out_dir="${fixture_out_dir}/scan-overlays"
    rm -rf "${overlay_out_dir}"
    mkdir -p "${overlay_out_dir}"

    set +e
    "${bin_path}" scan \
      --url "${fixture_url}" \
      --baseline conformance/pinned/conformance-baseline.yml \
      --out "${overlay_out_dir}" \
      --machine json \
      --score-preview \
      --metrics all >"${overlay_out_dir}/summary.stdout.json"
    local overlay_exit="$?"
    set -e
    if [[ "${overlay_exit}" != "0" ]]; then
      echo "ERROR: scan overlays exit code mismatch for ${fixture_id} (expected 0, got ${overlay_exit})" >&2
      cat "${overlay_out_dir}/summary.stdout.json" >&2 || true
      exit 1
    fi

    "${bin_path}" ci validate-json \
      --schema schemas/x07.mcp.scan.report.schema.json \
      --input "${overlay_out_dir}/scan.json"
    python3 scripts/ci/assert_scan_report_consistency.py "${overlay_out_dir}/scan.json"

    test -s "${overlay_out_dir}/scan.events.jsonl"
    grep -q '"type":"scan.score.preview"' "${overlay_out_dir}/scan.events.jsonl"
    grep -q '"type":"scan.metrics.dimension"' "${overlay_out_dir}/scan.events.jsonl"
    grep -q '"type":"scan.metrics.usage"' "${overlay_out_dir}/scan.events.jsonl"
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

echo "==> security fixtures"

run_security_fixture() (
  local fixture_id="${1:?missing fixture_id}"
  local fixture_url="${2:?missing fixture_url}"
  local expected_exit="${3:?missing expected_exit}"

  local fixture_out_dir="out/ci-security/${fixture_id}"
  rm -rf "${fixture_out_dir}"
  mkdir -p "${fixture_out_dir}"

  local server_log="${fixture_out_dir}/server.log"
  conformance/scripts/spawn_reference_http.sh "${fixture_id}" noauth >"${server_log}" 2>&1 &
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
    cat "${fixture_out_dir}/summary.stdout.json" >&2 || true
    tail -n 200 "${server_log}" >&2 || true
    exit 1
  fi

  "${bin_path}" ci validate-json \
    --schema schemas/x07.mcp.scan.report.schema.json \
    --input "${fixture_out_dir}/scan.json"
  python3 scripts/ci/assert_scan_report_consistency.py "${fixture_out_dir}/scan.json"

  test -s "${fixture_out_dir}/perf.samples.json"

  if [[ "${fixture_id}" == "meta-risk-http" ]]; then
    python3 - "${fixture_out_dir}/scan.json" <<'PY'
import json
import sys

with open(sys.argv[1], "r", encoding="utf-8") as f:
    report = json.load(f)

codes = {finding["code"] for finding in report["findings"]}
for code in ("SEC-INJECTION-PATTERN", "SEC-COMMAND-RISK-PATTERN", "SEC-DESCRIPTOR-BLOAT"):
    assert code in codes, codes
PY
  fi

  if [[ "${fixture_id}" == "drift-http" ]]; then
    python3 - "${fixture_out_dir}/scan.json" <<'PY'
import json
import sys

with open(sys.argv[1], "r", encoding="utf-8") as f:
    report = json.load(f)

codes = {finding["code"] for finding in report["findings"]}
assert "SEC-TOOLS-LIST-DRIFT" in codes, codes
PY
  fi

  if [[ "${fixture_id}" == "remote-loose-http" ]]; then
    python3 - "${fixture_out_dir}/scan.json" <<'PY'
import json
import sys

with open(sys.argv[1], "r", encoding="utf-8") as f:
    report = json.load(f)

codes = {finding["code"] for finding in report["findings"]}
for code in ("SEC-INSECURE-TRANSPORT", "SEC-AUTH-MISCONFIG", "SEC-HOST-ORIGIN-MISMATCH"):
    assert code in codes, codes
PY
  fi
)

run_security_fixture meta-risk-http http://127.0.0.1:18083/mcp 1
run_security_fixture drift-http http://127.0.0.1:18084/mcp 1
run_security_fixture remote-loose-http http://2130706433:18085/mcp 0

run_conformance_stdio_fixture() (
  local fixture_id="${1:?missing fixture_id}"
  local target_id="${2:?missing target_id}"
  local expected_exit="${3:?missing expected_exit}"

  local fixture_out_dir="out/ci-conformance/${fixture_id}"
  rm -rf "${fixture_out_dir}"
  mkdir -p "${fixture_out_dir}"

  local env_file="${fixture_out_dir}/server.env"
  cat >"${env_file}" <<'EOF'
HARDPROOF_TEST_ENV=1
EOF

  set +e
  "${bin_path}" scan \
    --cmd "bash conformance/scripts/spawn_reference_stdio.sh ${target_id}" \
    --transport stdio \
    --cwd "${repo_root}" \
    --env-file "${env_file}" \
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

echo "==> x07lang-mcp dist smoke (optional)"

x07lang_mcp_src_server_json="../x07-mcp/servers/x07lang-mcp/dist/server.json"
x07lang_mcp_src_mcpb="../x07-mcp/servers/x07lang-mcp/dist/x07lang-mcp.mcpb"
if [[ -f "${x07lang_mcp_src_server_json}" && -f "${x07lang_mcp_src_mcpb}" ]]; then
  x07lang_mcp_out="${tmp_dir}/x07lang-mcp"
  rm -rf "${x07lang_mcp_out}"
  mkdir -p "${x07lang_mcp_out}"

  x07lang_mcp_server_json="${x07lang_mcp_out}/server.json"
  x07lang_mcp_mcpb="${x07lang_mcp_out}/x07lang-mcp.mcpb"
  cp "${x07lang_mcp_src_server_json}" "${x07lang_mcp_server_json}"
  cp "${x07lang_mcp_src_mcpb}" "${x07lang_mcp_mcpb}"

  x07lang_mcp_trust_out="${x07lang_mcp_out}/trust.json"
  "${bin_path}" trust verify \
    --server-json "${x07lang_mcp_server_json}" \
    --out "${x07lang_mcp_trust_out}" \
    --machine json >"${x07lang_mcp_out}/trust.stdout.json"

  test -s "${x07lang_mcp_trust_out}"
  "${bin_path}" ci validate-json \
    --schema schemas/x07.mcp.trust.summary.schema.json \
    --input "${x07lang_mcp_trust_out}"

  x07lang_mcp_bundle_out="${x07lang_mcp_out}/bundle.json"
  "${bin_path}" bundle verify \
    --server-json "${x07lang_mcp_server_json}" \
    --mcpb "${x07lang_mcp_mcpb}" \
    --out "${x07lang_mcp_bundle_out}" \
    --machine json >"${x07lang_mcp_out}/bundle.stdout.json"

  test -s "${x07lang_mcp_bundle_out}"
  "${bin_path}" ci validate-json \
    --schema schemas/x07.mcp.bundle.verify.schema.json \
    --input "${x07lang_mcp_bundle_out}"
else
  echo "(skip) missing ${x07lang_mcp_src_server_json} or ${x07lang_mcp_src_mcpb}"
fi

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
    "name": "io.x07/hardproof-bundle-large",
    "version": "0.1.0",
    "description": "Synthetic large mcpb fixture to smoke bundle verify fuel budget.",
    "packages": [
        {
            "registryType": "mcpb",
            "identifier": "io.x07/hardproof-bundle-large",
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
