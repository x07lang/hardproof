#!/usr/bin/env bash
set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
cd "${repo_root}"

project="${1:-x07.json}"

if [[ -d ".x07/deps" ]]; then
  exit 0
fi

mkdir -p ".x07/tmp"
tmp_project="$(mktemp "hardproof-x07.project.XXXXXX")"
tmp_lock="$(mktemp ".x07/tmp/hardproof-x07.lock.json.XXXXXX")"
rm -f "${tmp_lock}"

python3 - "${project}" "${tmp_lock}" "${tmp_project}" <<'PY'
import json
import sys
from pathlib import Path

project_path = Path(sys.argv[1])
lockfile_path = sys.argv[2]
out_path = Path(sys.argv[3])

project = json.loads(project_path.read_text(encoding="utf-8"))
project["lockfile"] = lockfile_path
out_path.write_text(json.dumps(project, indent=2) + "\n", encoding="utf-8")
PY

x07 pkg lock --project "${tmp_project}" --json=off

rm -f "${tmp_project}" "${tmp_lock}"

if [[ ! -d ".x07/deps" ]]; then
  echo "ERROR: dependency hydration did not produce .x07/deps" >&2
  exit 1
fi
