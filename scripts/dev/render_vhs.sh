#!/usr/bin/env bash
set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
cd "${repo_root}"

rebuild=0
if [[ "${1:-}" == "--rebuild" ]]; then
  rebuild=1
  shift
fi
if [[ $# -gt 0 ]]; then
  echo "usage: $0 [--rebuild]" >&2
  exit 2
fi

require_bin() {
  local bin="${1:?missing bin}"
  if ! command -v "${bin}" >/dev/null 2>&1; then
    echo "ERROR: missing '${bin}' on PATH" >&2
    exit 2
  fi
}

require_bin ffmpeg
require_bin ttyd
require_bin vhs

out_dir="${repo_root}/out/vhs"
mkdir -p "${out_dir}"

if [[ -n "${X07_BIN:-}" ]]; then
  x07_bin="${X07_BIN}"
elif [[ -x "${repo_root}/../x07/target/debug/x07" ]]; then
  x07_bin="${repo_root}/../x07/target/debug/x07"
else
  x07_bin="x07"
fi

if ! command -v "${x07_bin}" >/dev/null 2>&1; then
  echo "ERROR: x07 not found (set X07_BIN=/path/to/x07 or ensure x07 is on PATH)" >&2
  exit 2
fi

hardproof_bin="${out_dir}/hardproof"
if [[ "${rebuild}" == "1" || ! -x "${hardproof_bin}" ]]; then
  echo "==> bundle hardproof (${x07_bin})"
  "${x07_bin}" bundle --project x07.json --profile os --json=off --out "${hardproof_bin}" >/dev/null
  chmod +x "${hardproof_bin}"
else
  echo "==> reuse bundled hardproof (${hardproof_bin})"
fi

echo "==> render tapes"
vhs docs/vhs/scan_partial_rich.tape
vhs docs/vhs/scan_partial_tui.tape
vhs docs/vhs/scan_full_rich.tape
vhs docs/vhs/scan_full_tui.tape

website_root="${repo_root}/../x07-website"
if [[ -d "${website_root}/site/static/hardproof/sample-reports" ]]; then
  echo "==> sync videos to x07-website"
  cp "${out_dir}/scan_partial_rich.webm" "${website_root}/site/static/hardproof/sample-reports/partial/live-rich.webm"
  cp "${out_dir}/scan_partial_tui.webm" "${website_root}/site/static/hardproof/sample-reports/partial/live-tui.webm"
  cp "${out_dir}/scan_full_rich.webm" "${website_root}/site/static/hardproof/sample-reports/full/live-rich.webm"
  cp "${out_dir}/scan_full_tui.webm" "${website_root}/site/static/hardproof/sample-reports/full/live-tui.webm"
fi

echo "ok: wrote videos under ${out_dir}"
