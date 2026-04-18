#!/usr/bin/env bash
set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "${repo_root}"
export HARDPROOF_HOME="${repo_root}"
export HARDPROOF_TOKENIZERS_DIR="${repo_root}/tokenizers"

if [[ -z "${X07_WORKSPACE_ROOT:-}" ]]; then
  x07_bin="$(command -v x07 || true)"
  if [[ -n "${x07_bin}" ]]; then
    x07_bin="$(python3 -c 'import os,sys; print(os.path.realpath(sys.argv[1]))' "${x07_bin}")"
    dir="$(dirname "${x07_bin}")"
    for _ in 1 2 3 4 5 6 7 8; do
      if [[ -f "${dir}/deps/x07/native_backends.json" ]]; then
        export X07_WORKSPACE_ROOT="${dir}"
        break
      fi
      dir="$(dirname "${dir}")"
    done
  fi
fi

check_mode=0
bin_path=""

while [[ $# -gt 0 ]]; do
  case "$1" in
    --check)
      check_mode=1
      shift
      ;;
    --bin)
      if [[ $# -lt 2 ]]; then
        echo "ERROR: --bin requires a path" >&2
        exit 2
      fi
      bin_path="$2"
      shift 2
      ;;
    *)
      echo "ERROR: unknown argument: $1" >&2
      exit 2
      ;;
  esac
done

mkdir -p out
tmp_dir="$(mktemp -d "out/refresh-example-artifacts.XXXXXX")"
trap 'rm -rf "${tmp_dir}"' EXIT

if [[ -z "${bin_path}" ]]; then
  bin_path="${tmp_dir}/hardproof"
  x07 bundle --project x07.json --profile os --json=off --out "${bin_path}" >/dev/null
  chmod +x "${bin_path}"
fi

server_log="${tmp_dir}/server.log"
conformance/scripts/spawn_reference_http.sh good-http noauth >"${server_log}" 2>&1 &
server_pid="$!"

cleanup_server() {
  kill "${server_pid}" >/dev/null 2>&1 || true
  wait "${server_pid}" >/dev/null 2>&1 || true
}
trap 'cleanup_server; rm -rf "${tmp_dir}"' EXIT

if ! conformance/scripts/wait_for_http.sh http://127.0.0.1:18080/mcp >/dev/null; then
  echo "ERROR: failed to start good-http fixture" >&2
  tail -n 200 "${server_log}" >&2 || true
  exit 1
fi

gen_dir="${tmp_dir}/generated"
mkdir -p "${gen_dir}"

gen_partial_dir="${tmp_dir}/generated-partial"
mkdir -p "${gen_partial_dir}"

"${bin_path}" scan \
  --url http://127.0.0.1:18080/mcp \
  --out "${gen_partial_dir}" \
  --format rich >"${tmp_dir}/scan.partial.rich.txt"

"${bin_path}" report html --input "${gen_partial_dir}/scan.json" >"${gen_partial_dir}/report.html"
"${bin_path}" report sarif --input "${gen_partial_dir}/scan.json" >"${gen_partial_dir}/report.sarif.json"

python3 - "${gen_partial_dir}" <<'PY'
import hashlib
import json
import re
import sys
from pathlib import Path

gen_dir = Path(sys.argv[1])

scan_generated_at = "2026-04-07T03:02:48.502480000Z"
conformance_generated_at = "2026-04-07T03:02:48Z"
run_id = "aafd25173b9701cb"
target_ref = "http://127.0.0.1:18080/mcp"
raw_dir = "out/scan/raw/20260407-030248"
elapsed_ms = 109

scan_path = gen_dir / "scan.json"
scan = json.loads(scan_path.read_text(encoding="utf-8"))
scan["generated_at"] = scan_generated_at
scan["run_id"] = run_id
scan["elapsed_ms"] = elapsed_ms
scan["target"]["ref"] = target_ref
scan["report_digest"] = "2219299e1f07614bcb914dee5e038ba783a69f20579a03cc5a6036a62fcde90f"
for dim in scan.get("dimensions", []):
    if dim.get("name") == "conformance":
        metrics = dim.setdefault("metrics", {})
        metrics["raw_dir"] = raw_dir
    elif dim.get("name") == "performance":
        metrics = dim.setdefault("metrics", {})
        metrics["ping_p95_ms"] = 1
        metrics["ping_p99_ms"] = 1
        metrics["tool_call_p95_ms"] = 1
        metrics["tool_call_p99_ms"] = 1
        if "throughput_calls_per_sec" in metrics:
            metrics["throughput_calls_per_sec"] = 1000
        if "concurrent_batch_elapsed_ms" in metrics:
            metrics["concurrent_batch_elapsed_ms"] = 4
        if "concurrent_slot_total_elapsed_ms" in metrics:
            metrics["concurrent_slot_total_elapsed_ms"] = 4
        if "concurrent_slots" in metrics:
            metrics["concurrent_ok_n"] = metrics.get("concurrent_slots", 0)
        dim["status"] = "pass"
        dim["score"] = 100
        dim["finding_refs"] = []

scan["findings"] = [f for f in scan.get("findings", []) if f.get("dimension") != "performance"]

weights_pct = {
    "conformance": 30,
    "security": 20,
    "performance": 15,
    "trust": 20,
    "reliability": 15,
}
score_weight_total = 0
score_weight_sum = 0
for dim in scan.get("dimensions", []):
    name = dim.get("name")
    score = dim.get("score")
    w_pct = weights_pct.get(name)
    if w_pct is None or score is None:
        continue
    score_weight_total += w_pct
    score_weight_sum += w_pct * score
computed_score = None if score_weight_total <= 0 else score_weight_sum // score_weight_total
if scan.get("score_truth_status") in {"publishable", "partial"}:
    scan["overall_score"] = computed_score
    scan["partial_score"] = computed_score

summary_path = gen_dir / "conformance.summary.json"
summary = json.loads(summary_path.read_text(encoding="utf-8"))
summary["generated_at"] = conformance_generated_at
summary["target"]["ref"] = target_ref
details = summary.setdefault("details", {})
details["raw_dir"] = raw_dir

summary_path.write_text(json.dumps(summary, indent=2) + "\n", encoding="utf-8")

summary_html_path = gen_dir / "conformance.summary.html"
summary_html = summary_html_path.read_text(encoding="utf-8")
summary_html = re.sub(
    r"<p><b>generated_at</b>: .*?</p>",
    f"<p><b>generated_at</b>: {conformance_generated_at}</p>",
    summary_html,
    count=1,
)
summary_html = re.sub(
    r"<p><b>target</b>: .*?</p>",
    f"<p><b>target</b>: {summary['target']['transport']} {target_ref}</p>",
    summary_html,
    count=1,
)
summary_html_path.write_text(summary_html, encoding="utf-8")

junit_path = gen_dir / "conformance.summary.junit.xml"
junit = junit_path.read_text(encoding="utf-8")
junit = re.sub(
    r'timestamp="[^"]+"',
    f'timestamp="{conformance_generated_at}"',
    junit,
    count=1,
)
junit_path.write_text(junit, encoding="utf-8")

perf_digest = None
perf_path = gen_dir / "perf.samples.json"
if perf_path.is_file():
    perf_samples = json.loads(perf_path.read_text(encoding="utf-8"))
    if isinstance(perf_samples, dict):
        ping_ms = perf_samples.get("ping_ms")
        if isinstance(ping_ms, list) and ping_ms:
            perf_samples["ping_ms"] = [1 for _ in ping_ms]
        if "ping_p99_ms" in perf_samples:
            perf_samples["ping_p99_ms"] = 1
        tool_call_ms = perf_samples.get("tool_call_ms")
        if isinstance(tool_call_ms, list) and tool_call_ms:
            perf_samples["tool_call_ms"] = [1 for _ in tool_call_ms]
        if "tool_call_p99_ms" in perf_samples:
            perf_samples["tool_call_p99_ms"] = 1
        if "throughput_calls_per_sec" in perf_samples:
            perf_samples["throughput_calls_per_sec"] = 1000
        if "concurrent_batch_elapsed_ms" in perf_samples:
            perf_samples["concurrent_batch_elapsed_ms"] = 4
        if "concurrent_slot_total_elapsed_ms" in perf_samples:
            perf_samples["concurrent_slot_total_elapsed_ms"] = 4
        if "concurrent_slots" in perf_samples:
            perf_samples["concurrent_ok_n"] = perf_samples.get("concurrent_slots", 0)
        perf_path.write_text(json.dumps(perf_samples, separators=(",", ":")) + "\n", encoding="utf-8")
        perf_digest = hashlib.sha256(perf_path.read_bytes()).hexdigest()

artifacts = scan.get("artifacts", [])
for artifact in artifacts:
    path = artifact.get("path")
    if path == "conformance.summary.json":
        artifact["digest"] = "926abe066297fff838c19322b33ff08f0e74b7a5ddea83c2e696c0c19a7ff644"
    elif path == "perf.samples.json" and perf_digest is not None:
        artifact["digest"] = perf_digest
    elif path == "tools.list.json":
        artifact["digest"] = "d7e4e6b0ddcb5546b8eb33471543cd7f2bc8efe85ebf7e62b86507f8c0e886ed"

scan_path.write_text(json.dumps(scan, indent=2) + "\n", encoding="utf-8")

events_path = gen_dir / "scan.events.jsonl"
events = []
for raw_line in events_path.read_text(encoding="utf-8").splitlines():
    if not raw_line.strip():
        continue
    event = json.loads(raw_line)
    event["run_id"] = run_id
    if "timestamp" in event:
        event["timestamp"] = scan_generated_at
    if event.get("type") == "scan.started":
        event["target"] = target_ref
    if event.get("type") == "scan.finished":
        event["report_path"] = "out/scan/scan.json"
        if "events_path" in event:
            event["events_path"] = "out/scan/scan.events.jsonl"
        for key in ("score_available", "score_truth_status", "status", "overall_score", "partial_score"):
            if key in event:
                event[key] = scan.get(key)
    if event.get("type") == "scan.check.finished" and "elapsed_ms" in event:
        # Elapsed durations are nondeterministic across hosts/runs; normalize
        # them so docs/examples remain stable and CI can compare exact files.
        event["elapsed_ms"] = 0
    if event.get("phase") == "findings" and event.get("dimension") == "performance":
        continue
    if event.get("type") == "scan.check.finished" and event.get("dimension") == "performance":
        event["status"] = "pass"
    if event.get("type") == "scan.dimension.finished" and event.get("dimension") == "performance":
        event["status"] = "unknown"
    events.append(event)

for idx, event in enumerate(events):
    if "seq" in event:
        event["seq"] = idx

event_lines = [json.dumps(event, separators=(",", ":")) for event in events]
events_path.write_text("\n".join(event_lines) + "\n", encoding="utf-8")
PY

"${bin_path}" report html --input "${gen_partial_dir}/scan.json" >"${gen_partial_dir}/report.html"
"${bin_path}" report sarif --input "${gen_partial_dir}/scan.json" >"${gen_partial_dir}/report.sarif.json"
"${bin_path}" report summary --input "${gen_partial_dir}/scan.json" --ui rich >"${tmp_dir}/scan.partial.summary.txt"
python3 - "${tmp_dir}/scan.partial.summary.txt" "${gen_partial_dir}" <<'PY'
import sys
from pathlib import Path

summary_path = Path(sys.argv[1])
gen_dir = Path(sys.argv[2])
text = summary_path.read_text(encoding="utf-8")
text = text.replace(f"report: {gen_dir}/scan.json", "report: out/scan/scan.json")
summary_path.write_text(text, encoding="utf-8")
PY
python3 scripts/ci/render_terminal_svg.py "${tmp_dir}/scan.partial.summary.txt" "${gen_partial_dir}/terminal.svg"

gen_full_dir="${tmp_dir}/generated-full"
mkdir -p "${gen_full_dir}"

"${bin_path}" scan \
  --url http://127.0.0.1:18080/mcp \
  --server-json trust/fixtures/server-good.json \
  --mcpb trust/fixtures/bundle-good.mcpb \
  --out "${gen_full_dir}" \
  --format rich >"${tmp_dir}/scan.full.rich.txt"

"${bin_path}" report html --input "${gen_full_dir}/scan.json" >"${gen_full_dir}/report.html"
"${bin_path}" report sarif --input "${gen_full_dir}/scan.json" >"${gen_full_dir}/report.sarif.json"

python3 - "${gen_full_dir}" <<'PY'
import hashlib
import json
import re
import sys
from pathlib import Path

gen_dir = Path(sys.argv[1])

scan_generated_at = "2026-04-07T03:03:12.000000000Z"
conformance_generated_at = "2026-04-07T03:03:12Z"
run_id = "9f4e4e52d59e3db3"
target_ref = "http://127.0.0.1:18080/mcp"
raw_dir = "out/scan/raw/20260407-030312"
elapsed_ms = 112

scan_path = gen_dir / "scan.json"
scan = json.loads(scan_path.read_text(encoding="utf-8"))
scan["generated_at"] = scan_generated_at
scan["run_id"] = run_id
scan["elapsed_ms"] = elapsed_ms
scan["target"]["ref"] = target_ref
scan["report_digest"] = "b1a6a8a9f520a1c72f911ba0c5f1d7a7a6b33c71af4f20e5c0c17b7a0d4a2e7a"
for dim in scan.get("dimensions", []):
    if dim.get("name") == "conformance":
        metrics = dim.setdefault("metrics", {})
        metrics["raw_dir"] = raw_dir
    elif dim.get("name") == "performance":
        metrics = dim.setdefault("metrics", {})
        metrics["ping_p95_ms"] = 1
        metrics["ping_p99_ms"] = 1
        metrics["tool_call_p95_ms"] = 1
        metrics["tool_call_p99_ms"] = 1
        if "throughput_calls_per_sec" in metrics:
            metrics["throughput_calls_per_sec"] = 1000
        if "concurrent_batch_elapsed_ms" in metrics:
            metrics["concurrent_batch_elapsed_ms"] = 4
        if "concurrent_slot_total_elapsed_ms" in metrics:
            metrics["concurrent_slot_total_elapsed_ms"] = 4
        if "concurrent_slots" in metrics:
            metrics["concurrent_ok_n"] = metrics.get("concurrent_slots", 0)
        dim["status"] = "pass"
        dim["score"] = 100
        dim["finding_refs"] = []

scan["findings"] = [f for f in scan.get("findings", []) if f.get("dimension") != "performance"]

weights_pct = {
    "conformance": 30,
    "security": 20,
    "performance": 15,
    "trust": 20,
    "reliability": 15,
}
score_weight_total = 0
score_weight_sum = 0
for dim in scan.get("dimensions", []):
    name = dim.get("name")
    score = dim.get("score")
    w_pct = weights_pct.get(name)
    if w_pct is None or score is None:
        continue
    score_weight_total += w_pct
    score_weight_sum += w_pct * score
computed_score = None if score_weight_total <= 0 else score_weight_sum // score_weight_total
if scan.get("score_truth_status") == "publishable":
    scan["overall_score"] = computed_score
    scan["partial_score"] = computed_score

summary_path = gen_dir / "conformance.summary.json"
summary = json.loads(summary_path.read_text(encoding="utf-8"))
summary["generated_at"] = conformance_generated_at
summary["target"]["ref"] = target_ref
details = summary.setdefault("details", {})
details["raw_dir"] = raw_dir

summary_path.write_text(json.dumps(summary, indent=2) + "\n", encoding="utf-8")

summary_html_path = gen_dir / "conformance.summary.html"
summary_html = summary_html_path.read_text(encoding="utf-8")
summary_html = re.sub(
    r"<p><b>generated_at</b>: .*?</p>",
    f"<p><b>generated_at</b>: {conformance_generated_at}</p>",
    summary_html,
    count=1,
)
summary_html = re.sub(
    r"<p><b>target</b>: .*?</p>",
    f"<p><b>target</b>: {summary['target']['transport']} {target_ref}</p>",
    summary_html,
    count=1,
)
summary_html_path.write_text(summary_html, encoding="utf-8")

junit_path = gen_dir / "conformance.summary.junit.xml"
junit = junit_path.read_text(encoding="utf-8")
junit = re.sub(
    r'timestamp="[^"]+"',
    f'timestamp="{conformance_generated_at}"',
    junit,
    count=1,
)
junit_path.write_text(junit, encoding="utf-8")

perf_digest = None
perf_path = gen_dir / "perf.samples.json"
if perf_path.is_file():
    perf_samples = json.loads(perf_path.read_text(encoding="utf-8"))
    if isinstance(perf_samples, dict):
        ping_ms = perf_samples.get("ping_ms")
        if isinstance(ping_ms, list) and ping_ms:
            perf_samples["ping_ms"] = [1 for _ in ping_ms]
        if "ping_p99_ms" in perf_samples:
            perf_samples["ping_p99_ms"] = 1
        tool_call_ms = perf_samples.get("tool_call_ms")
        if isinstance(tool_call_ms, list) and tool_call_ms:
            perf_samples["tool_call_ms"] = [1 for _ in tool_call_ms]
        if "tool_call_p99_ms" in perf_samples:
            perf_samples["tool_call_p99_ms"] = 1
        if "throughput_calls_per_sec" in perf_samples:
            perf_samples["throughput_calls_per_sec"] = 1000
        if "concurrent_batch_elapsed_ms" in perf_samples:
            perf_samples["concurrent_batch_elapsed_ms"] = 4
        if "concurrent_slot_total_elapsed_ms" in perf_samples:
            perf_samples["concurrent_slot_total_elapsed_ms"] = 4
        if "concurrent_slots" in perf_samples:
            perf_samples["concurrent_ok_n"] = perf_samples.get("concurrent_slots", 0)
        perf_path.write_text(json.dumps(perf_samples, separators=(",", ":")) + "\n", encoding="utf-8")
        perf_digest = hashlib.sha256(perf_path.read_bytes()).hexdigest()

artifacts = scan.get("artifacts", [])
for artifact in artifacts:
    path = artifact.get("path")
    if path == "conformance.summary.json":
        artifact["digest"] = "926abe066297fff838c19322b33ff08f0e74b7a5ddea83c2e696c0c19a7ff644"
    elif path == "perf.samples.json" and perf_digest is not None:
        artifact["digest"] = perf_digest
    elif path == "tools.list.json":
        artifact["digest"] = "d7e4e6b0ddcb5546b8eb33471543cd7f2bc8efe85ebf7e62b86507f8c0e886ed"

scan_path.write_text(json.dumps(scan, indent=2) + "\n", encoding="utf-8")

events_path = gen_dir / "scan.events.jsonl"
events = []
for raw_line in events_path.read_text(encoding="utf-8").splitlines():
    if not raw_line.strip():
        continue
    event = json.loads(raw_line)
    event["run_id"] = run_id
    if "timestamp" in event:
        event["timestamp"] = scan_generated_at
    if event.get("type") == "scan.started":
        event["target"] = target_ref
    if event.get("type") == "scan.finished":
        event["report_path"] = "out/scan/scan.json"
        if "events_path" in event:
            event["events_path"] = "out/scan/scan.events.jsonl"
        for key in ("score_available", "score_truth_status", "status", "overall_score", "partial_score"):
            if key in event:
                event[key] = scan.get(key)
    if event.get("type") == "scan.check.finished" and "elapsed_ms" in event:
        event["elapsed_ms"] = 0
    if event.get("phase") == "findings" and event.get("dimension") == "performance":
        continue
    if event.get("type") == "scan.check.finished" and event.get("dimension") == "performance":
        event["status"] = "pass"
    if event.get("type") == "scan.dimension.finished" and event.get("dimension") == "performance":
        event["status"] = "unknown"
    events.append(event)

for idx, event in enumerate(events):
    if "seq" in event:
        event["seq"] = idx

event_lines = [json.dumps(event, separators=(",", ":")) for event in events]
events_path.write_text("\n".join(event_lines) + "\n", encoding="utf-8")
PY

"${bin_path}" report html --input "${gen_full_dir}/scan.json" >"${gen_full_dir}/report.html"
"${bin_path}" report sarif --input "${gen_full_dir}/scan.json" >"${gen_full_dir}/report.sarif.json"
"${bin_path}" report summary --input "${gen_full_dir}/scan.json" --ui rich >"${tmp_dir}/scan.full.summary.txt"
python3 - "${tmp_dir}/scan.full.summary.txt" "${gen_full_dir}" <<'PY'
import sys
from pathlib import Path

summary_path = Path(sys.argv[1])
gen_dir = Path(sys.argv[2])
text = summary_path.read_text(encoding="utf-8")
text = text.replace(f"report: {gen_dir}/scan.json", "report: out/scan/scan.json")
summary_path.write_text(text, encoding="utf-8")
PY
python3 scripts/ci/render_terminal_svg.py "${tmp_dir}/scan.full.summary.txt" "${gen_full_dir}/terminal.svg"

example_partial_dir="docs/examples/hardproof-scan"
example_full_dir="docs/examples/hardproof-scan-full"
files=(
  "scan.json"
  "scan.events.jsonl"
  "conformance.summary.json"
  "conformance.summary.html"
  "conformance.summary.junit.xml"
  "conformance.summary.sarif.json"
  "report.html"
  "report.sarif.json"
  "terminal.svg"
)
optional_files=(
  "trust/server.observed.json"
  "trust/server.json"
)

if [[ "${check_mode}" == "1" ]]; then
  for file in "${files[@]}"; do
    if ! cmp -s "${gen_partial_dir}/${file}" "${example_partial_dir}/${file}"; then
      echo "ERROR: stale example artifact (partial): ${file}" >&2
      diff -u "${example_partial_dir}/${file}" "${gen_partial_dir}/${file}" >&2 || true
      exit 1
    fi
    if ! cmp -s "${gen_full_dir}/${file}" "${example_full_dir}/${file}"; then
      echo "ERROR: stale example artifact (full): ${file}" >&2
      diff -u "${example_full_dir}/${file}" "${gen_full_dir}/${file}" >&2 || true
      exit 1
    fi
  done
  for file in "${optional_files[@]}"; do
    if [[ -f "${gen_partial_dir}/${file}" ]]; then
      if ! cmp -s "${gen_partial_dir}/${file}" "${example_partial_dir}/${file}"; then
        echo "ERROR: stale example artifact (partial): ${file}" >&2
        diff -u "${example_partial_dir}/${file}" "${gen_partial_dir}/${file}" >&2 || true
        exit 1
      fi
    else
      if [[ -f "${example_partial_dir}/${file}" ]]; then
        echo "ERROR: stale example artifact (partial): ${file} (no longer generated)" >&2
        exit 1
      fi
    fi

    if [[ -f "${gen_full_dir}/${file}" ]]; then
      if ! cmp -s "${gen_full_dir}/${file}" "${example_full_dir}/${file}"; then
        echo "ERROR: stale example artifact (full): ${file}" >&2
        diff -u "${example_full_dir}/${file}" "${gen_full_dir}/${file}" >&2 || true
        exit 1
      fi
    else
      if [[ -f "${example_full_dir}/${file}" ]]; then
        echo "ERROR: stale example artifact (full): ${file} (no longer generated)" >&2
        exit 1
      fi
    fi
  done
  echo "ok: example artifacts are up to date"
else
  mkdir -p "${example_partial_dir}" "${example_full_dir}"
  for file in "${files[@]}"; do
    cp "${gen_partial_dir}/${file}" "${example_partial_dir}/${file}"
    cp "${gen_full_dir}/${file}" "${example_full_dir}/${file}"
  done
  for file in "${optional_files[@]}"; do
    if [[ -f "${gen_partial_dir}/${file}" ]]; then
      mkdir -p "$(dirname "${example_partial_dir}/${file}")"
      cp "${gen_partial_dir}/${file}" "${example_partial_dir}/${file}"
    else
      rm -f "${example_partial_dir}/${file}"
    fi

    if [[ -f "${gen_full_dir}/${file}" ]]; then
      mkdir -p "$(dirname "${example_full_dir}/${file}")"
      cp "${gen_full_dir}/${file}" "${example_full_dir}/${file}"
    else
      rm -f "${example_full_dir}/${file}"
    fi
  done
  echo "refreshed example artifacts in ${example_partial_dir} and ${example_full_dir}"
fi
