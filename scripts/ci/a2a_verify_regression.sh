#!/usr/bin/env bash
# P2-16 regression (hermetic, no network): A2A Agent Card verification prototype.
#  (a) a valid signed card -> ok=true, all checks true, exit 0, and the verdict
#      validates against x07.mcp.a2a.verify@0.1.0,
#  (b) a card missing required fields -> ok=false, exit 1,
#  (c) an unsigned card with no provider -> ok=true (structurally valid) but
#      signed=false / provider_present=false.
set -uo pipefail
HP="${1:?usage: a2a_verify_regression.sh <hardproof-bin>}"
here="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
root="$(cd "${here}/../.." && pwd)"
export HARDPROOF_TOKENIZERS_DIR="${root}/tokenizers"
export HARDPROOF_HOME="${root}"
tmp="$(mktemp -d)"; trap 'rm -rf "$tmp"' EXIT
jbool(){ python3 -c "import json,sys;print(json.load(open(sys.argv[1])).get(sys.argv[2]))" "$1" "$2"; }
fail=0

# (a) valid signed card -> ok/all true, exit 0, verdict validates against schema
"$HP" a2a verify --machine json --card "${here}/fixtures/a2a_card_valid.json" >"$tmp/valid.json" 2>&1
rc=$?; ok=$(jbool "$tmp/valid.json" ok); sg=$(jbool "$tmp/valid.json" signed); pv=$(jbool "$tmp/valid.json" provider_present)
echo "  valid: exit=$rc ok=$ok signed=$sg provider=$pv (expect 0/True/True/True)"
{ [ "$rc" = 0 ] && [ "$ok" = "True" ] && [ "$sg" = "True" ] && [ "$pv" = "True" ]; } || fail=1
"$HP" ci validate-json --schema "${root}/schemas/x07.mcp.a2a.verify.schema.json" --input "$tmp/valid.json" >/dev/null 2>&1 || { echo "  verdict failed schema validation"; fail=1; }

# (b) missing required fields -> ok=false, exit 1
"$HP" a2a verify --machine json --card "${here}/fixtures/a2a_card_invalid.json" >"$tmp/bad.json" 2>&1
rc=$?; ok=$(jbool "$tmp/bad.json" ok); url=$(jbool "$tmp/bad.json" url); sk=$(jbool "$tmp/bad.json" skills_valid)
echo "  invalid: exit=$rc ok=$ok url=$url skills_valid=$sk (expect 1/False/False/False)"
{ [ "$rc" = 1 ] && [ "$ok" = "False" ] && [ "$url" = "False" ] && [ "$sk" = "False" ]; } || fail=1

# (c) unsigned, no provider -> ok=true, signed=false, provider_present=false
"$HP" a2a verify --machine json --card "${here}/fixtures/a2a_card_unsigned.json" >"$tmp/uns.json" 2>&1
rc=$?; ok=$(jbool "$tmp/uns.json" ok); sg=$(jbool "$tmp/uns.json" signed); pv=$(jbool "$tmp/uns.json" provider_present)
echo "  unsigned: exit=$rc ok=$ok signed=$sg provider=$pv (expect 0/True/False/False)"
{ [ "$rc" = 0 ] && [ "$ok" = "True" ] && [ "$sg" = "False" ] && [ "$pv" = "False" ]; } || fail=1

[ "$fail" = 0 ] && echo "a2a verify regression: PASS" || { echo "a2a verify regression: FAIL"; exit 1; }
