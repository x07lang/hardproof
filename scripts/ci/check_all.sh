#!/usr/bin/env bash
set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
cd "${repo_root}"

echo "==> fmt"
while IFS= read -r path; do
  x07 fmt --input "${path}" --check --report-json >/dev/null
done < <(find cli/src -name '*.x07.json' -print | LC_ALL=C sort)

echo "==> pkg lock"
x07 pkg lock --project x07.json --check --json=off >/dev/null

echo "==> arch check"
x07 arch check --manifest arch/manifest.x07arch.json >/dev/null

echo "==> cli smoke"
x07 run --project . --profile os --json=off -- x07-mcp-test --help >/dev/null
