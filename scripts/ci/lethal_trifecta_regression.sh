#!/usr/bin/env bash
# P2-15 regression (hermetic, no network): config policy checker
# (lethal-trifecta / Rule-of-Two) over the scanned server's tool catalog.
#  (a) a server whose tools span all three legs (untrusted input + private
#      data + external comms) flags SEC-LETHAL-TRIFECTA (warning) and deducts
#      from the security score (lethal_trifecta metric = 1),
#  (b) a server with only two legs satisfies the Rule of Two -> no finding
#      (lethal_trifecta metric = 0).
set -uo pipefail
HP="${1:?usage: lethal_trifecta_regression.sh <hardproof-bin>}"
here="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
root="$(cd "${here}/../.." && pwd)"
export HARDPROOF_TOKENIZERS_DIR="${root}/tokenizers"
export HARDPROOF_HOME="${root}"
tmp="$(mktemp -d)"; trap 'rm -rf "$tmp"' EXIT
sec_metric(){ python3 -c "import json,sys;d=json.load(open(sys.argv[1]));print(next(x for x in d['dimensions'] if x['name']=='security')['metrics'].get(sys.argv[2]))" "$1" "$2"; }
n_finding(){ python3 -c "import json,sys;d=json.load(open(sys.argv[1]));print(len([f for f in d['findings'] if f['code']==sys.argv[2]]))" "$1" "$2"; }
fail=0

# (a) trifecta -> SEC-LETHAL-TRIFECTA + lethal_trifecta metric 1
"$HP" scan --cmd "python3 ${here}/fixtures/mcp_stdio_trifecta_fixture.py" \
  --format json --out "$tmp/tri" >/dev/null 2>&1
lt=$(sec_metric "$tmp/tri/scan.json" lethal_trifecta); nf=$(n_finding "$tmp/tri/scan.json" SEC-LETHAL-TRIFECTA)
echo "  trifecta: lethal_trifecta=$lt SEC-LETHAL-TRIFECTA=$nf (expect 1/1)"
{ [ "$lt" = "1" ] && [ "$nf" = "1" ]; } || fail=1

# (b) two legs only -> Rule of Two satisfied -> no finding
"$HP" scan --cmd "python3 ${here}/fixtures/mcp_stdio_two_leg_fixture.py" \
  --format json --out "$tmp/two" >/dev/null 2>&1
lt=$(sec_metric "$tmp/two/scan.json" lethal_trifecta); nf=$(n_finding "$tmp/two/scan.json" SEC-LETHAL-TRIFECTA)
echo "  two-leg: lethal_trifecta=$lt SEC-LETHAL-TRIFECTA=$nf (expect 0/0)"
{ [ "$lt" = "0" ] && [ "$nf" = "0" ]; } || fail=1

[ "$fail" = 0 ] && echo "lethal trifecta regression: PASS" || { echo "lethal trifecta regression: FAIL"; exit 1; }
