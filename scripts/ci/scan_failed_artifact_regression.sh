#!/usr/bin/env bash
# P0-3 regression (hermetic, no network): every invocation that reaches target
# resolution must leave an artifact.
#  (a) a failure BEFORE scan.json is written (e.g. conflicting target flags)
#      must emit a structured scan.failed.json,
#  (b) a healthy scan must write scan.json and NOT scan.failed.json,
#  (c) a hung/probe-fail server (writes scan.json status:fail) must NOT also
#      emit scan.failed.json (no redundant artifact).
set -uo pipefail
HP="${1:?usage: scan_failed_artifact_regression.sh <hardproof-bin>}"
here="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
root="$(cd "${here}/../.." && pwd)"
export HARDPROOF_TOKENIZERS_DIR="${root}/tokenizers"
export HARDPROOF_HOME="${root}"
tmp="$(mktemp -d)"; trap 'rm -rf "$tmp"' EXIT
field(){ python3 -c "import json,sys;print(json.load(open(sys.argv[1])).get(sys.argv[2]))" "$1" "$2"; }
fail=0

# (a) conflicting target flags (--url + --cmd) -> scan.failed.json, no scan.json
"$HP" scan --url http://127.0.0.1:9/mcp --allow-private-targets --cmd "echo x" --out "$tmp/conflict" >/dev/null 2>&1
if [ -f "$tmp/conflict/scan.failed.json" ] && [ ! -f "$tmp/conflict/scan.json" ]; then
  sv=$(field "$tmp/conflict/scan.failed.json" schema_version); st=$(field "$tmp/conflict/scan.failed.json" status)
  echo "  conflict: scan.failed.json present (schema=$sv status=$st), no scan.json"
  { [ "$sv" = "hardproof.scan.failed@0.1.0" ] && [ "$st" = "failed" ]; } || fail=1
else
  echo "  conflict: FAIL (expected scan.failed.json and no scan.json)"; fail=1
fi

# (b) healthy stdio scan -> scan.json, NO scan.failed.json
"$HP" scan --cmd "python3 ${here}/fixtures/mcp_stdio_resilient_fixture.py" --out "$tmp/ok" >/dev/null 2>&1
if [ -f "$tmp/ok/scan.json" ] && [ ! -f "$tmp/ok/scan.failed.json" ]; then
  echo "  healthy: scan.json present, no scan.failed.json"
else
  echo "  healthy: FAIL (scan.json missing or scan.failed.json unexpectedly present)"; fail=1
fi

# (c) hung server -> scan.json(status:fail), NO scan.failed.json
"$HP" scan --cmd "python3 ${here}/fixtures/mcp_stdio_hang_fixture.py" --out "$tmp/hang" >/dev/null 2>&1
if [ -f "$tmp/hang/scan.json" ] && [ ! -f "$tmp/hang/scan.failed.json" ]; then
  echo "  hang: scan.json present, no scan.failed.json"
else
  echo "  hang: FAIL (expected scan.json and no scan.failed.json)"; fail=1
fi

[ "$fail" = 0 ] && echo "scan failed-artifact regression: PASS" || { echo "scan failed-artifact regression: FAIL"; exit 1; }
