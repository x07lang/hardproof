#!/usr/bin/env bash
# P1-5 regression (hermetic, no network): the upper-bound score clamp must
#  (a) be PRESENT as a guard at every dimension aggregation site in
#      cli/src/scan/core.x07.json (a regressed sub-scorer cannot leak >100), and
#  (b) hold BEHAVIOURALLY: every dimension score and the overall score in a real
#      scan stay within [-1, 100].
# (a) is a structural guard against the clamp being deleted; (b) confirms the
# end-to-end invariant on actual output.
set -uo pipefail
HP="${1:?usage: score_clamp_regression.sh <hardproof-bin>}"
here="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
root="$(cd "${here}/../.." && pwd)"
export HARDPROOF_TOKENIZERS_DIR="${root}/tokenizers"
tmp="$(mktemp -d)"; trap 'rm -rf "$tmp"' EXIT
fail=0

# (a) structural: count clamp guards ["if",[">",VAR,100],["set",VAR,100],0] in core AST.
clamps=$(python3 - "${root}/cli/src/scan/core.x07.json" <<'PY'
import json, sys
doc = json.load(open(sys.argv[1]))
found = []
def is_clamp(n):
    # ["if", [">", VAR, 100], ["set", VAR, 100], 0]
    if not (isinstance(n, list) and len(n) == 4 and n[0] == "if" and n[3] == 0):
        return None
    cond, then = n[1], n[2]
    if not (isinstance(cond, list) and len(cond) == 3 and cond[0] == ">" and cond[2] == 100):
        return None
    if not (isinstance(then, list) and len(then) == 3 and then[0] == "set" and then[2] == 100):
        return None
    if isinstance(cond[1], str) and cond[1] == then[1]:
        return cond[1]
    return None
def walk(n):
    if isinstance(n, list):
        v = is_clamp(n)
        if v: found.append(v)
        for x in n: walk(x)
    elif isinstance(n, dict):
        for x in n.values(): walk(x)
walk(doc)
print(",".join(sorted(found)))
PY
)
n_clamps=$(printf '%s' "$clamps" | awk -F, '{print ($1=="")?0:NF}')
echo "  clamp guards in core.x07.json: ${n_clamps} -> [${clamps}]"
[ "$n_clamps" -ge 5 ] || { echo "    expected >= 5 dimension clamps"; fail=1; }

# (b) behavioural: a real scan keeps every dimension + overall score in [-1, 100].
"$HP" scan --cmd "python3 ${here}/fixtures/mcp_stdio_resilient_fixture.py" --format json --out "$tmp/s" >/dev/null 2>&1
bad=$(python3 - "$tmp/s/scan.json" <<'PY'
import json, sys
d = json.load(open(sys.argv[1]))
bad = []
ov = d.get("overall_score")
if isinstance(ov, int) and not (-1 <= ov <= 100): bad.append(f"overall={ov}")
for dim in d.get("dimensions", []):
    sc = dim.get("score")
    if isinstance(sc, int) and not (-1 <= sc <= 100): bad.append(f"{dim.get('name')}={sc}")
print(";".join(bad))
PY
)
echo "  scores out of [-1,100]: [${bad:-none}]"
[ -z "$bad" ] || fail=1

[ "$fail" = 0 ] && echo "score clamp regression: PASS" || { echo "score clamp regression: FAIL"; exit 1; }
