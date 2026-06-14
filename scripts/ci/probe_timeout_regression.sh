#!/usr/bin/env bash
# P1-7 (pivot) regression (hermetic, no network): the HARDPROOF_PROBE_TIMEOUT_MS
# knob must (a) bound the total cost of a server that passes discovery then
# hangs on later probes (per-process timeouts would otherwise STACK across
# dimensions), and (b) NOT change results for a healthy server (the timeout
# governs only how long a hang waits, never the scores).
set -uo pipefail
HP="${1:?usage: probe_timeout_regression.sh <hardproof-bin>}"
here="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
root="$(cd "${here}/../.." && pwd)"
export HARDPROOF_TOKENIZERS_DIR="${root}/tokenizers"
tmp="$(mktemp -d)"; trap 'rm -rf "$tmp"' EXIT
overall(){ python3 -c "import json,sys;print(json.load(open(sys.argv[1])).get('overall_score'))" "$1"; }
fail=0

# (a) bounded runtime: late-hang server with a tight 2s probe timeout must
#     finish well under the un-bounded stacked cost (~120s at the 20s default).
start=$(date +%s)
HARDPROOF_PROBE_TIMEOUT_MS=2000 "$HP" scan \
  --cmd "python3 ${here}/fixtures/mcp_stdio_late_hang_fixture.py" \
  --format json --out "$tmp/lh" >/dev/null 2>&1
rc=$?; elapsed=$(( $(date +%s) - start ))
echo "  late-hang @2s timeout: elapsed=${elapsed}s rc=${rc} (expect <60s; ~120s when unbounded)"
{ [ "$elapsed" -lt 60 ] && [ -f "$tmp/lh/scan.json" ]; } || fail=1

# (b) determinism: a healthy server's scores are identical with and without the knob.
"$HP" scan --cmd "python3 ${here}/fixtures/mcp_stdio_resilient_fixture.py" \
  --format json --out "$tmp/h_def" >/dev/null 2>&1
HARDPROOF_PROBE_TIMEOUT_MS=5000 "$HP" scan \
  --cmd "python3 ${here}/fixtures/mcp_stdio_resilient_fixture.py" \
  --format json --out "$tmp/h_knob" >/dev/null 2>&1
a=$(overall "$tmp/h_def/scan.json"); b=$(overall "$tmp/h_knob/scan.json")
echo "  healthy overall: default=${a} knob=${b} (expect identical)"
[ "$a" = "$b" ] || fail=1

[ "$fail" = 0 ] && echo "probe timeout regression: PASS" || { echo "probe timeout regression: FAIL"; exit 1; }
