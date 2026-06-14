#!/usr/bin/env bash
# P1-11 regression (hermetic, no network): deepened security screening.
#  (a) a tool with destructiveHint+openWorldHint -> SEC-EXCESSIVE-AGENCY (scope creep),
#  (b) injection/command/secret findings carry an OWASP tag in evidence,
#  (c) a real ghp_ token is detected by the precise regex,
#  (d) the screening ruleset is versioned (security.metrics.ruleset_version),
#  (e) PRECISION: prose mentions of secret prefixes (no real tokens) do NOT
#      false-positive (literal substring matching would have).
set -uo pipefail
HP="${1:?usage: security_depth_regression.sh <hardproof-bin>}"
here="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
root="$(cd "${here}/../.." && pwd)"
export HARDPROOF_TOKENIZERS_DIR="${root}/tokenizers"
export HARDPROOF_HOME="${root}"
tmp="$(mktemp -d)"; trap 'rm -rf "$tmp"' EXIT
fail=0

"$HP" scan --cmd "python3 ${here}/fixtures/mcp_stdio_security_depth_fixture.py" \
  --format json --out "$tmp/depth" >/dev/null 2>&1
res=$(python3 - "$tmp/depth/scan.json" <<'PY'
import json, sys
d = json.load(open(sys.argv[1]))
sec = next(x for x in d["dimensions"] if x["name"] == "security")
codes = {f["code"]: f for f in d["findings"] if f["code"].startswith("SEC-")}
def owasp(code): return (codes.get(code, {}).get("evidence", {}) or {}).get("owasp")
checks = {
    "excessive_agency_finding": "SEC-EXCESSIVE-AGENCY" in codes,
    "excessive_agency_count_1": sec["metrics"].get("excessive_agency_tool_count") == 1,
    "ruleset_version": bool(sec["metrics"].get("ruleset_version")),
    "secret_detected": "SEC-SECRET-EXPOSURE" in codes,
    "injection_owasp": owasp("SEC-INJECTION-PATTERN") is not None,
    "excessive_agency_owasp": owasp("SEC-EXCESSIVE-AGENCY") is not None,
}
print(json.dumps(checks))
print("ruleset=" + str(sec["metrics"].get("ruleset_version")))
PY
)
echo "  depth fixture: ${res}"
echo "${res}" | python3 -c "import sys,json;d=json.loads(sys.stdin.readline());sys.exit(0 if all(d.values()) else 1)" || fail=1

# (e) precision: prose-only secret prefixes -> NO SEC-SECRET-EXPOSURE
"$HP" scan --cmd "python3 ${here}/fixtures/mcp_stdio_secret_prose_fixture.py" \
  --format json --out "$tmp/prose" >/dev/null 2>&1
n=$(python3 -c "import json,sys;d=json.load(open(sys.argv[1]));print(len([f for f in d['findings'] if f['code']=='SEC-SECRET-EXPOSURE']))" "$tmp/prose/scan.json")
echo "  prose precision: SEC-SECRET-EXPOSURE count=${n} (expect 0)"
[ "$n" = "0" ] || fail=1

[ "$fail" = 0 ] && echo "security depth regression: PASS" || { echo "security depth regression: FAIL"; exit 1; }
