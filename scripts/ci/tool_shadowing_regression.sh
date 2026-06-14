#!/usr/bin/env bash
# P1-11 (cross-server) regression (hermetic, no network): the corpus runner
# detects tool-name SHADOWING across targets. Two stdio servers that both
# expose "shared_tool" (plus unique tools) must produce, in index.json,
# details.tool_shadowing = { collision_count: 1, tools: ["shared_tool"] };
# the unique tool names must NOT be flagged. The index must validate against
# the corpus.summary@0.3.0 schema.
set -uo pipefail
HP="${1:?usage: tool_shadowing_regression.sh <hardproof-bin>}"
here="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
root="$(cd "${here}/../.." && pwd)"
export HARDPROOF_TOKENIZERS_DIR="${root}/tokenizers"
export HARDPROOF_HOME="${root}"
tmp="$(mktemp -d)"; trap 'rm -rf "$tmp"' EXIT
fail=0

cat > "$tmp/manifest.json" <<JSON
{"schema_version":"x07.mcp.report.manifest@0.1.0","report_id":"shadow-test","targets":[
{"id":"srv-a","source":{"repo":"x","version":"t"},"target":{"kind":"mcp_server","transport":"stdio","ref":"python3 ${here}/fixtures/mcp_stdio_shadow_a_fixture.py","meta":{}},"assumptions":{"auth_mode":"none"},"exclusions":{"skip_scenarios":[]}},
{"id":"srv-b","source":{"repo":"x","version":"t"},"target":{"kind":"mcp_server","transport":"stdio","ref":"python3 ${here}/fixtures/mcp_stdio_shadow_b_fixture.py","meta":{}},"assumptions":{"auth_mode":"none"},"exclusions":{"skip_scenarios":[]}}
]}
JSON

"$HP" corpus run --manifest "$tmp/manifest.json" --out "$tmp/corpus" >/dev/null 2>&1
if [ ! -s "$tmp/corpus/index.json" ]; then
  echo "tool shadowing regression: FAIL (no index.json)"; exit 1
fi

res=$(python3 - "$tmp/corpus/index.json" <<'PY'
import json, sys
d = json.load(open(sys.argv[1]))
ts = d["details"]["tool_shadowing"]
checks = {
    "collision_count_1": ts.get("collision_count") == 1,
    "shared_tool_flagged": "shared_tool" in ts.get("tools", []),
    "unique_not_flagged": ("alpha_only" not in ts.get("tools", [])) and ("beta_only" not in ts.get("tools", [])),
}
print(json.dumps(checks)); print("tool_shadowing=" + json.dumps(ts))
PY
)
echo "  ${res}"
echo "${res}" | head -1 | python3 -c "import sys,json;sys.exit(0 if all(json.loads(sys.stdin.readline()).values()) else 1)" || fail=1

"$HP" ci validate-json --schema "${root}/schemas/x07.mcp.corpus.summary.schema.json" --input "$tmp/corpus/index.json" >/dev/null 2>&1 || { echo "  index.json failed @0.3.0 schema validation"; fail=1; }

[ "$fail" = 0 ] && echo "tool shadowing regression: PASS" || { echo "tool shadowing regression: FAIL"; exit 1; }
