#!/usr/bin/env bash
# P0-1 regression (hermetic, no network): reliability dimension must
#  (a) NOT false-positive a server that survives malformed/invalid input
#      (no false REL-* criticals AND reliability score at the justified floor),
#  (b) STILL flag a server that crashes on malformed/invalid input
#      (REL-* criticals AND a penalized reliability score).
# The score-floor assertion (a) is stronger than the critical-count check:
# warning-severity REL findings lower the score without producing a critical,
# so a regression that re-introduces a false REL warning is caught here too.
# Floor justified: a fully-resilient server (correct error replies, survives
# bad input) has no legitimate reliability deduction, so it must score 100.
set -uo pipefail
HP="${1:?usage: reliability_stdio_regression.sh <hardproof-bin>}"
here="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
root="$(cd "${here}/../.." && pwd)"
export HARDPROOF_TOKENIZERS_DIR="${root}/tokenizers"
tmp="$(mktemp -d)"; trap 'rm -rf "$tmp"' EXIT
rel_crit(){ python3 -c "import json,sys;d=json.load(open(sys.argv[1]));print(len([f for f in d['findings'] if f['code'].startswith('REL-') and f['severity']=='critical']))" "$1"; }
rel_score(){ python3 -c "import json,sys;d=json.load(open(sys.argv[1]));r=next(x for x in d['dimensions'] if x['name']=='reliability');print(r.get('score'))" "$1"; }
fail=0
REL_FLOOR=100
# (a) resilient server -> NO false REL criticals AND reliability >= floor
"$HP" scan --cmd "python3 ${here}/fixtures/mcp_stdio_resilient_fixture.py" --format json --out "$tmp/resilient" >/dev/null 2>&1
c=$(rel_crit "$tmp/resilient/scan.json"); sc=$(rel_score "$tmp/resilient/scan.json")
echo "  resilient: reliability=$sc rel_criticals=$c (expect 0 criticals, score >= ${REL_FLOOR})"
[ "$c" = "0" ] || fail=1
{ [ -n "$sc" ] && [ "$sc" != "None" ] && [ "$sc" -ge "$REL_FLOOR" ]; } || fail=1
# (b) crash-on-bad-input server -> MUST flag REL criticals AND a penalized score
"$HP" scan --cmd "python3 ${here}/fixtures/mcp_stdio_crash_fixture.py" --format json --out "$tmp/crash" >/dev/null 2>&1
c=$(rel_crit "$tmp/crash/scan.json"); sc=$(rel_score "$tmp/crash/scan.json")
echo "  crash: reliability=$sc rel_criticals=$c (expect >=1 criticals, score < ${REL_FLOOR})"
[ "$c" -ge 1 ] || fail=1
{ [ -n "$sc" ] && [ "$sc" != "None" ] && [ "$sc" -lt "$REL_FLOOR" ]; } || fail=1
[ "$fail" = 0 ] && echo "reliability stdio regression: PASS" || { echo "reliability stdio regression: FAIL"; exit 1; }
