#!/usr/bin/env bash
set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
cd "${repo_root}"

x07_mcp_root="${X07_MCP_ROOT:-${repo_root}/../x07-mcp}"

if [[ ! -d "${x07_mcp_root}" ]]; then
  echo "error: missing x07-mcp checkout at ${x07_mcp_root}" >&2
  echo "hint: set X07_MCP_ROOT=/path/to/x07-mcp" >&2
  exit 2
fi

hardproof_bin="${HARDPROOF_BIN:-}"
mkdir -p out
tmp_dir="$(mktemp -d "out/release-qa.XXXXXX")"
cleanup_tmp() {
  if [[ -n "${tmp_dir}" ]]; then
    rm -rf "${tmp_dir}" >/dev/null 2>&1 || true
  fi
}
trap cleanup_tmp EXIT

if [[ -z "${hardproof_bin}" ]]; then
  hardproof_bin="${tmp_dir}/hardproof"
  x07 pkg lock --project x07.json --json=off >/dev/null
  x07 bundle --project x07.json --profile os --json=off --out "${hardproof_bin}" >/dev/null
  chmod +x "${hardproof_bin}"
fi

hardproof_bin_abs="$(cd "$(dirname "${hardproof_bin}")" && pwd)/$(basename "${hardproof_bin}")"

hardproof_version="$("${hardproof_bin}" --version | awk '{print $2}' | tr -d '\r' || true)"
if [[ -z "${hardproof_version}" ]]; then
  echo "error: failed to resolve hardproof version from: ${hardproof_bin}" >&2
  exit 2
fi

evidence_root="release_qa/external_smoke_matrix/${hardproof_version}"
rm -rf "${evidence_root}"
mkdir -p "${evidence_root}"

command_log="${evidence_root}/command.log"
rm -f "${command_log}"

run_logged() {
  printf '$' >>"${command_log}"
  for arg in "$@"; do
    printf ' %q' "${arg}" >>"${command_log}"
  done
  printf '\n' >>"${command_log}"
  "$@" 2>&1 | tee -a "${command_log}"
}

run_logged_allow_fail() {
  local label="${1:?missing label}"
  shift

  printf '$' >>"${command_log}"
  for arg in "$@"; do
    printf ' %q' "${arg}" >>"${command_log}"
  done
  printf '\n' >>"${command_log}"

  set +e
  "$@" 2>&1 | tee -a "${command_log}"
  local exit_code="${PIPESTATUS[0]}"
  set -e

  printf 'exit_code[%s]=%s\n' "${label}" "${exit_code}" >>"${command_log}"
  if [[ "${exit_code}" == "2" ]]; then
    echo "error: ${label} failed with exit 2 (invocation/config/runtime precondition)" >&2
    exit 2
  fi
  return 0
}

note() {
  printf '%s\n' "$@" | tee -a "${command_log}"
}

note "== External smoke matrix =="
note "hardproof_bin=${hardproof_bin}"
note "hardproof_version=${hardproof_version}"
note "x07_version=$(x07 --version | tr -d '\\r')"
note "x07_mcp_root=${x07_mcp_root}"
note "generated_at_utc=$(date -u +%Y-%m-%dT%H:%M:%SZ)"
note ""

meta_json="${evidence_root}/meta.json"
python3 - "${meta_json}" "${hardproof_version}" "${x07_mcp_root}" <<'PY'
import json
import subprocess
import sys
from pathlib import Path

out_path = Path(sys.argv[1])
hardproof_version = sys.argv[2]
x07_mcp_root = Path(sys.argv[3])

def cmd_out(argv, cwd=None):
    proc = subprocess.run(argv, cwd=cwd, stdout=subprocess.PIPE, stderr=subprocess.PIPE, text=True, check=False)
    return proc.returncode, proc.stdout.strip(), proc.stderr.strip()

_, x07_version, _ = cmd_out(["x07", "--version"])

hardproof_commit = ""
if (Path.cwd() / ".git").exists():
    code, out, _ = cmd_out(["git", "rev-parse", "HEAD"])
    if code == 0:
        hardproof_commit = out

x07_mcp_commit = ""
code, out, _ = cmd_out(["git", "rev-parse", "HEAD"], cwd=x07_mcp_root)
if code == 0:
    x07_mcp_commit = out

out_path.write_text(
    json.dumps(
        {
            "hardproof": {"version": hardproof_version, "commit": hardproof_commit},
            "x07": {"version": x07_version},
            "x07_mcp": {"commit": x07_mcp_commit, "root": str(x07_mcp_root)},
        },
        indent=2,
    )
    + "\n",
    encoding="utf-8",
)
PY

note "== STDIO smoke: x07lang-mcp =="
stdio_out="${evidence_root}/stdio-x07lang-mcp"
rm -rf "${stdio_out}"
mkdir -p "${stdio_out}"

bundle_tmp="${tmp_dir:-${stdio_out}/.tmp}/x07lang-mcp.bundle"
rm -rf "${bundle_tmp}"
mkdir -p "${bundle_tmp}"
run_logged unzip -q "${x07_mcp_root}/servers/x07lang-mcp/dist/x07lang-mcp.mcpb" -d "${bundle_tmp}"

stdio_env="${stdio_out}/x07lang-mcp.env"
cat >"${stdio_env}" <<EOF
X07_MCP_CFG_PATH=config/mcp.server.json
X07_MCP_X07_EXE=$(command -v x07)
EOF

run_logged_allow_fail "stdio.scan" "${hardproof_bin}" scan \
  --cmd "server/x07lang-mcp" \
  --cwd "${bundle_tmp}" \
  --env-file "${stdio_env}" \
  --out "${stdio_out}/scan" \
  --machine json

note ""
note "== HTTP smoke: postgres-mcp demo (partial scan) =="
demo_root="${x07_mcp_root}/demos/postgres-public-beta"
run_logged bash "${demo_root}/scripts/run_demo.sh" --deps-only

server_log="${evidence_root}/postgres.server.log"
rm -f "${server_log}"

(
  bash "${demo_root}/scripts/run_demo.sh" --server >"${server_log}" 2>&1 &
  server_pid="$!"

  cleanup_server() {
    kill "${server_pid}" >/dev/null 2>&1 || true
    wait "${server_pid}" >/dev/null 2>&1 || true
  }
  trap cleanup_server EXIT

  ready=0
  for _ in $(seq 1 120); do
    if curl -sS --max-time 1 "http://127.0.0.1:8403/mcp" >/dev/null 2>&1; then
      ready=1
      break
    fi
    sleep 1
  done
  if [[ "${ready}" != "1" ]]; then
    echo "error: postgres-mcp demo server did not become reachable at http://127.0.0.1:8403/mcp" >&2
    tail -n 200 "${server_log}" >&2 || true
    exit 1
  fi

  http_partial_out="${evidence_root}/http-postgres-mcp-partial"
  rm -rf "${http_partial_out}"
  mkdir -p "${http_partial_out}"

  run_logged_allow_fail "http.postgres.partial.scan" "${hardproof_bin}" scan \
    --url "http://127.0.0.1:8403/mcp" \
    --out "${http_partial_out}/scan" \
    --machine json

  note ""
  note "== Trust-evaluable smoke: postgres-mcp demo (full scan + trust + bundle + replay) =="
  rm -rf "${demo_root}/out"
  mkdir -p "${demo_root}/out"
  HARDPROOF_BIN="${hardproof_bin_abs}" run_logged_allow_fail "http.postgres.full.verify_demo" bash "${demo_root}/scripts/verify_demo.sh"

  http_full_out="${evidence_root}/http-postgres-mcp-full"
  rm -rf "${http_full_out}"
  mkdir -p "${http_full_out}"

  copy_if_exists() {
    local src="${1}"
    local dst="${2}"
    if [[ -e "${src}" ]]; then
      cp -R "${src}" "${dst}"
    fi
  }

  copy_if_exists "${demo_root}/out/command.log" "${http_full_out}/command.log"
  copy_if_exists "${demo_root}/out/scan" "${http_full_out}/scan"
  copy_if_exists "${demo_root}/out/replay.session.json" "${http_full_out}/replay.session.json"
  copy_if_exists "${demo_root}/out/replay-verify" "${http_full_out}/replay-verify"
  copy_if_exists "${demo_root}/out/trust.summary.json" "${http_full_out}/trust.summary.json"
  copy_if_exists "${demo_root}/out/bundle.verify.json" "${http_full_out}/bundle.verify.json"

  note ""
  note "== Corpus smoke (external manifest) =="
  corpus_out="${evidence_root}/corpus"
  rm -rf "${corpus_out}"
  mkdir -p "${corpus_out}"

  manifest_path="${repo_root}/release_qa/external_smoke_matrix/external-smoke-001.json"
  run_logged_allow_fail "corpus.run" "${hardproof_bin}" corpus run --manifest "${manifest_path}" --out "${corpus_out}" --machine json
  run_logged_allow_fail "corpus.render" "${hardproof_bin}" corpus render --input "${corpus_out}/index.json" --out "${corpus_out}" --machine json
)

note ""
note "ok: wrote external smoke evidence under ${evidence_root}"

summary_path="${evidence_root}/SUMMARY.md"
python3 - "${evidence_root}" "${summary_path}" <<'PY'
import json
import sys
from pathlib import Path

root = Path(sys.argv[1])
out_path = Path(sys.argv[2])

meta = {}
meta_path = root / "meta.json"
if meta_path.exists():
    meta = json.loads(meta_path.read_text(encoding="utf-8"))

def scan_summary(path: Path):
    if not path.exists():
        return None
    report = json.loads(path.read_text(encoding="utf-8"))
    return {
        "status": report.get("status"),
        "score_mode": report.get("score_mode"),
        "score_truth_status": report.get("score_truth_status"),
        "overall_score": report.get("overall_score"),
        "partial_score": report.get("partial_score"),
        "unknown_dimensions": report.get("unknown_dimensions"),
        "target": report.get("target", {}),
        "tool_version": report.get("tool_version"),
    }

def corpus_summary(path: Path):
    if not path.exists():
        return None
    doc = json.loads(path.read_text(encoding="utf-8"))
    details = doc.get("details", {})
    counts = (details.get("counts") or {}) if isinstance(details, dict) else {}
    return {
        "ok": doc.get("ok"),
        "counts": counts,
        "tool_version": doc.get("tool_version"),
    }

stdio = scan_summary(root / "stdio-x07lang-mcp" / "scan" / "scan.json")
http_partial = scan_summary(root / "http-postgres-mcp-partial" / "scan" / "scan.json")
http_full = scan_summary(root / "http-postgres-mcp-full" / "scan" / "scan.json")
corpus = corpus_summary(root / "corpus" / "index.json")

lines = []
lines.append("# External smoke matrix summary")
lines.append("")
if meta:
    lines.append("## Tool versions")
    lines.append("")
    lines.append(f"- hardproof: {meta.get('hardproof', {}).get('version', '')} ({meta.get('hardproof', {}).get('commit', '')})")
    lines.append(f"- x07: {meta.get('x07', {}).get('version', '')}")
    lines.append(f"- x07-mcp: {meta.get('x07_mcp', {}).get('commit', '')}")
    lines.append("")

def add_block(title: str, data):
    lines.append(f"## {title}")
    lines.append("")
    if data is None:
        lines.append("- missing evidence (command failed before producing scan.json)")
        lines.append("")
        return
    lines.append(f"- status: {data.get('status')}")
    lines.append(f"- score_truth_status: {data.get('score_truth_status')}")
    lines.append(f"- score_mode: {data.get('score_mode')}")
    lines.append(f"- overall_score: {data.get('overall_score')}")
    lines.append(f"- partial_score: {data.get('partial_score')}")
    lines.append(f"- unknown_dimensions: {data.get('unknown_dimensions')}")
    target = data.get('target') or {}
    lines.append(f"- target: {target.get('transport')} {target.get('ref')}")
    lines.append("")

add_block("STDIO: x07lang-mcp", stdio)
add_block("HTTP: postgres-mcp demo (partial)", http_partial)
add_block("Trust-evaluable: postgres-mcp demo (full)", http_full)

lines.append("## Corpus")
lines.append("")
if corpus is None:
    lines.append("- missing evidence (corpus did not produce index.json)")
else:
    lines.append(f"- ok: {corpus.get('ok')}")
    counts = corpus.get("counts") or {}
    if counts:
        lines.append(f"- counts: total={counts.get('total')} ok={counts.get('ok')} failed={counts.get('failed')}")
lines.append("")

out_path.write_text("\n".join(lines) + "\n", encoding="utf-8")
PY

note ""
note "== cleanup: postgres demo deps =="
run_logged bash -c "cd \"${demo_root}\" && docker compose down"
