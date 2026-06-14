#!/usr/bin/env bash
# P2-14 regression (hermetic, no network): tamper-evident scan attestation.
#  A scan writes attestation.json binding scan.json + scan.events.jsonl by
#  SHA-256. `attest verify` must:
#   (a) PASS (exit 0) on an untouched output directory,
#   (b) FAIL (exit 1) when scan.json is modified,
#   (c) FAIL (exit 1) when scan.events.jsonl is modified,
#   (d) ERROR (exit 2) when the attestation file is missing,
#   (e) with --attest-key + --attest-ledger: signature_match + chain_match true
#       when intact, signature_match false under the wrong key.
set -uo pipefail
HP="${1:?usage: attest_tamper_regression.sh <hardproof-bin>}"
here="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
root="$(cd "${here}/../.." && pwd)"
export HARDPROOF_TOKENIZERS_DIR="${root}/tokenizers"
export HARDPROOF_HOME="${root}"
tmp="$(mktemp -d)"; trap 'rm -rf "$tmp"' EXIT
jbool(){ python3 -c "import json,sys;print(json.load(open(sys.argv[1])).get(sys.argv[2]))" "$1" "$2"; }
fail=0

# Produce a scan with an attestation (resilient stdio fixture; hermetic).
"$HP" scan --cmd "python3 ${here}/fixtures/mcp_stdio_resilient_fixture.py" \
  --format json --out "$tmp/s" >/dev/null 2>&1
if [ ! -f "$tmp/s/attestation.json" ]; then
  echo "attest tamper regression: FAIL (scan did not write attestation.json)"; exit 1
fi

# (a) intact -> exit 0, ok=True
"$HP" attest verify --machine json --attestation "$tmp/s/attestation.json" --out-dir "$tmp/s" >"$tmp/v_intact.json" 2>&1
rc=$?; ok=$(jbool "$tmp/v_intact.json" ok)
echo "  intact: exit=$rc ok=$ok (expect 0/True)"; { [ "$rc" = 0 ] && [ "$ok" = "True" ]; } || fail=1

# (b) tamper scan.json -> exit 1, scan_json_match=False
cp "$tmp/s/scan.json" "$tmp/scan.bak"
printf ' ' >> "$tmp/s/scan.json"
"$HP" attest verify --machine json --attestation "$tmp/s/attestation.json" --out-dir "$tmp/s" >"$tmp/v_scan.json" 2>&1
rc=$?; m=$(jbool "$tmp/v_scan.json" scan_json_match)
echo "  tamper scan.json: exit=$rc scan_json_match=$m (expect 1/False)"; { [ "$rc" = 1 ] && [ "$m" = "False" ]; } || fail=1
cp "$tmp/scan.bak" "$tmp/s/scan.json"

# (c) tamper events -> exit 1, events_match=False
cp "$tmp/s/scan.events.jsonl" "$tmp/ev.bak"
printf '{"injected":"evil"}\n' >> "$tmp/s/scan.events.jsonl"
"$HP" attest verify --machine json --attestation "$tmp/s/attestation.json" --out-dir "$tmp/s" >"$tmp/v_ev.json" 2>&1
rc=$?; m=$(jbool "$tmp/v_ev.json" events_match)
echo "  tamper events: exit=$rc events_match=$m (expect 1/False)"; { [ "$rc" = 1 ] && [ "$m" = "False" ]; } || fail=1
cp "$tmp/ev.bak" "$tmp/s/scan.events.jsonl"

# (d) restored -> exit 0 again (deterministic, reversible)
"$HP" attest verify --machine json --attestation "$tmp/s/attestation.json" --out-dir "$tmp/s" >/dev/null 2>&1
rc=$?; echo "  restored: exit=$rc (expect 0)"; [ "$rc" = 0 ] || fail=1

# (e) missing attestation -> exit 2
"$HP" attest verify --attestation "$tmp/does-not-exist.json" --out-dir "$tmp/s" >/dev/null 2>&1
rc=$?; echo "  missing attestation: exit=$rc (expect 2)"; [ "$rc" = 2 ] || fail=1

# (f) signed + hash-chained: intact verify is all-true; wrong key -> signature_match false
printf 'attest-regression-key-001' > "$tmp/key"
printf 'wrong-key' > "$tmp/wrongkey"
led="$tmp/att.ledger"
"$HP" scan --cmd "python3 ${here}/fixtures/mcp_stdio_resilient_fixture.py" \
  --format json --attest-key "$tmp/key" --attest-ledger "$led" --out "$tmp/sg" >/dev/null 2>&1
"$HP" attest verify --machine json --attestation "$tmp/sg/attestation.json" --out-dir "$tmp/sg" \
  --attest-key "$tmp/key" --attest-ledger "$led" >"$tmp/v_sg.json" 2>&1
rc=$?; rh=$(jbool "$tmp/v_sg.json" record_hash_match); sm=$(jbool "$tmp/v_sg.json" signature_match); cm=$(jbool "$tmp/v_sg.json" chain_match)
echo "  signed+chained intact: exit=$rc record=$rh signature=$sm chain=$cm (expect 0/True/True/True)"
{ [ "$rc" = 0 ] && [ "$rh" = "True" ] && [ "$sm" = "True" ] && [ "$cm" = "True" ]; } || fail=1
"$HP" attest verify --machine json --attestation "$tmp/sg/attestation.json" --out-dir "$tmp/sg" \
  --attest-key "$tmp/wrongkey" >"$tmp/v_wk.json" 2>&1
rc=$?; sm=$(jbool "$tmp/v_wk.json" signature_match)
echo "  wrong key: exit=$rc signature_match=$sm (expect 1/False)"; { [ "$rc" = 1 ] && [ "$sm" = "False" ]; } || fail=1

[ "$fail" = 0 ] && echo "attest tamper regression: PASS" || { echo "attest tamper regression: FAIL"; exit 1; }
