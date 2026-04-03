#!/usr/bin/env bash
set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
cd "${repo_root}"

tag="${HARDPROOF_TAG:-${GITHUB_REF_NAME:-}}"
if [[ -z "${tag}" ]]; then
  echo "ERROR: missing release tag; set HARDPROOF_TAG (example: v0.1.0-alpha.6)" >&2
  exit 2
fi

if [[ "${tag}" != v* ]]; then
  echo "ERROR: tag must start with 'v' (got: ${tag})" >&2
  exit 2
fi

platform="$(uname -s)"
arch="$(uname -m)"

artifact_suffix=""
case "${platform}-${arch}" in
  Linux-x86_64) artifact_suffix="linux_x86_64" ;;
  Darwin-arm64) artifact_suffix="macos_arm64" ;;
  Darwin-x86_64) artifact_suffix="macos_x86_64" ;;
  *)
    echo "ERROR: unsupported platform/arch for release packaging: ${platform}-${arch}" >&2
    echo "NOTE: on Windows, run inside WSL2 and use the linux_x86_64 artifact." >&2
    exit 2
    ;;
esac

dist_dir="${DIST_DIR:-dist}"
work_dir="${dist_dir}/work"
mkdir -p "${work_dir}"

bin_name="hardproof"
bin_path="${work_dir}/${bin_name}"
legacy_bin_name="x07-mcp-test"
legacy_bin_path="${work_dir}/${legacy_bin_name}"
readme_name="README-beta.txt"
readme_path="${work_dir}/${readme_name}"

if ! command -v cc >/dev/null 2>&1; then
  echo "ERROR: missing C compiler (cc) required for x07 bundle packaging." >&2
  echo "On Ubuntu: sudo apt-get install -y build-essential" >&2
  echo "On macOS: install Xcode Command Line Tools (xcode-select --install) or provide a cc shim." >&2
  exit 2
fi

echo "==> pkg lock (hydrate + check)"
lock_log="${work_dir}/pkg.lock.log"
if ! x07 pkg lock --project x07.json --check --json=off >"${lock_log}" 2>&1; then
  echo "ERROR: x07 pkg lock failed." >&2
  cat "${lock_log}" >&2 || true
  exit 1
fi

echo "==> bundle ${bin_name} (${artifact_platform})"
bundle_log="${work_dir}/bundle.log"
if ! x07 bundle --project x07.json --profile os --json=off --out "${bin_path}" >"${bundle_log}" 2>&1; then
  echo "ERROR: x07 bundle failed." >&2
  cat "${bundle_log}" >&2 || true
  exit 1
fi
chmod +x "${bin_path}"

cp "${bin_path}" "${legacy_bin_path}"
chmod +x "${legacy_bin_path}"

cat >"${readme_path}" <<'TXT'
Hardproof beta transition

Hardproof is the new public name for the private-alpha tool previously released as x07-mcp-test.

Included binaries:
- hardproof (primary)
- x07-mcp-test (legacy compatibility alias during beta)

Next:
  ./hardproof --help
  ./hardproof doctor
  ./hardproof scan --url "http://127.0.0.1:3000/mcp" --out out/conformance --machine json
TXT

version="${tag#v}"
archive_base="hardproof_${version}_${artifact_suffix}"
archive_path="${dist_dir}/${archive_base}.tar.gz"

echo "==> package ${archive_path}"
tar -C "${work_dir}" -czf "${archive_path}" "${bin_name}" "${legacy_bin_name}" "${readme_name}"

echo "${archive_path}"
