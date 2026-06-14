#!/usr/bin/env bash
# P2-12 regression: rug-pull / per-tool definition drift monitor.
#  (a) same catalog vs its own pin -> NO SEC-TOOL-DEFINITION-DRIFT, security unchanged.
#  (b) different catalog vs a foreign pin -> SEC-TOOL-DEFINITION-DRIFT critical + security penalty.
# Requires a built hardproof binary (arg 1). Uses the deterministic HTTP fixtures.
set -uo pipefail
HP="${1:?usage: tool_pin_drift_regression.sh <hardproof-bin>}"
root="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
export HARDPROOF_TOKENIZERS_DIR="${root}/tokenizers"
tmp="$(mktemp -d)"; 
python3 "${root}/scripts/ci/fixtures/mcp_http_fixture_server.py" --fixture-id good-http --port 18080 >"$tmp/g.log" 2>&1 & GP=$!
python3 "${root}/scripts/ci/fixtures/mcp_http_fixture_server.py" --fixture-id meta-risk-http --port 18083 >"$tmp/m.log" 2>&1 & MP=$!
cleanup(){ kill $GP $MP >/dev/null 2>&1 || true; rm -rf "$tmp"; }
trap cleanup EXIT
sleep 2
crit(){ python3 -c "import json,sys;d=json.load(open(sys.argv[1]));print(len([f for f in d['findings'] if f['code']=='SEC-TOOL-DEFINITION-DRIFT']))" "$1"; }
fail=0
# baseline pin from good-http
"$HP" scan --url http://127.0.0.1:18080/mcp --allow-private-targets --transport http --out "$tmp/base" --format json >/dev/null 2>&1
test -s "$tmp/base/tools.pin.json" || { echo "FAIL: no tools.pin.json emitted"; fail=1; }
# (a) same catalog vs own pin -> no drift
"$HP" scan --url http://127.0.0.1:18080/mcp --allow-private-targets --transport http --tool-baseline "$tmp/base/tools.pin.json" --out "$tmp/same" --format json >/dev/null 2>&1
c=$(crit "$tmp/same/scan.json"); echo "  same-catalog drift criticals: $c (expect 0)"; [ "$c" = "0" ] || fail=1
# (b) foreign catalog -> drift
"$HP" scan --url http://127.0.0.1:18083/mcp --allow-private-targets --transport http --tool-baseline "$tmp/base/tools.pin.json" --out "$tmp/drift" --format json >/dev/null 2>&1
c=$(crit "$tmp/drift/scan.json"); echo "  foreign-catalog drift criticals: $c (expect >=1)"; [ "$c" -ge 1 ] || fail=1
[ "$fail" = 0 ] && echo "tool-pin drift regression: PASS" || { echo "tool-pin drift regression: FAIL"; exit 1; }
