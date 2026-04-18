#!/usr/bin/env bash
set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
cd "${repo_root}"

if [[ -z "${X07_WORKSPACE_ROOT:-}" ]]; then
  x07_bin="$(command -v x07 || true)"
  if [[ -n "${x07_bin}" ]]; then
    x07_bin="$(python3 -c 'import os,sys; print(os.path.realpath(sys.argv[1]))' "${x07_bin}")"
    dir="$(dirname "${x07_bin}")"
    for _ in 1 2 3 4 5 6 7 8; do
      if [[ -f "${dir}/deps/x07/native_backends.json" ]]; then
        export X07_WORKSPACE_ROOT="${dir}"
        break
      fi
      dir="$(dirname "${dir}")"
    done
  fi
fi

tag="${HARDPROOF_TAG:-${GITHUB_REF_NAME:-}}"
if [[ -z "${tag}" ]]; then
  echo "ERROR: missing release tag; set HARDPROOF_TAG (example: v0.4.0-beta.7)" >&2
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
readme_name="README-beta.txt"
readme_path="${work_dir}/${readme_name}"
tokenizers_name="tokenizers"
tokenizers_src_dir="${repo_root}/${tokenizers_name}"
arch_name="arch"
arch_src_dir="${repo_root}/${arch_name}"

if ! command -v cc >/dev/null 2>&1; then
  echo "ERROR: missing C compiler (cc) required for x07 bundle packaging." >&2
  echo "On Ubuntu: sudo apt-get install -y build-essential" >&2
  echo "On macOS: install Xcode Command Line Tools (xcode-select --install) or provide a cc shim." >&2
  exit 2
fi

echo "==> pkg lock (hydrate deps)"
hydrate_log="${work_dir}/pkg.lock.hydrate.log"
if ! bash scripts/ci/hydrate_x07_deps.sh x07.json >"${hydrate_log}" 2>&1; then
  echo "ERROR: x07 dependency hydration failed." >&2
  cat "${hydrate_log}" >&2 || true
  exit 1
fi

echo "==> pkg lock (patch deps)"
patch_log="${work_dir}/pkg.lock.patch.log"
if ! python3 scripts/ci/patch_ext_cli_ux_profile.py >"${patch_log}" 2>&1; then
  echo "ERROR: x07 dependency patching failed." >&2
  cat "${patch_log}" >&2 || true
  exit 1
fi

echo "==> pkg lock (check)"
lock_log="${work_dir}/pkg.lock.log"
if ! x07 pkg lock --project x07.json --check --offline --json=off >"${lock_log}" 2>&1; then
  echo "ERROR: x07 pkg lock failed." >&2
  cat "${lock_log}" >&2 || true
  exit 1
fi

if [[ "${platform}-${arch}" == "Linux-x86_64" ]]; then
  # Avoid generating binaries that require newer CPU instructions.
  # This keeps release artifacts runnable on conservative x86_64 baselines.
  export X07_CC_ARGS="${X07_CC_ARGS:-} -march=x86-64 -mtune=generic"
fi

echo "==> bundle ${bin_name} (${artifact_suffix})"
bundle_log="${work_dir}/bundle.log"
if ! x07 bundle --project x07.json --profile os --json=off --out "${bin_path}" >"${bundle_log}" 2>&1; then
  echo "ERROR: x07 bundle failed." >&2
  cat "${bundle_log}" >&2 || true
  exit 1
fi
chmod +x "${bin_path}"

cat >"${readme_path}" <<'TXT'
Hardproof beta

Next:
  ./hardproof --help
  ./hardproof doctor
  ./hardproof scan --url "http://127.0.0.1:3000/mcp" --out out/scan --machine json

Tokenizer tables:
  Exact usage-mode requires tokenizer tables. This archive includes them under ./tokenizers/.

CLI assets:
  Rich/compact/tui output requires CLI profile assets. This archive includes them under ./arch/cli/.
TXT

version="${tag#v}"
archive_base="hardproof_${version}_${artifact_suffix}"
archive_path="${dist_dir}/${archive_base}.tar.gz"

if [[ -d "${arch_src_dir}" ]]; then
  echo "==> stage arch assets"
  rm -rf "${work_dir}/${arch_name}"
  cp -r "${arch_src_dir}" "${work_dir}/${arch_name}"
fi

if [[ -d "${tokenizers_src_dir}" ]]; then
  echo "==> stage tokenizer tables"
  rm -rf "${work_dir}/${tokenizers_name}"
  mkdir -p "${work_dir}/${tokenizers_name}"
  if ls "${tokenizers_src_dir}"/*.table.bin >/dev/null 2>&1; then
    cp "${tokenizers_src_dir}"/*.table.bin "${work_dir}/${tokenizers_name}/"
  fi
fi

echo "==> package ${archive_path}"
tar_items=("${bin_name}" "${readme_name}")
if [[ -d "${work_dir}/${arch_name}" ]]; then
  tar_items+=("${arch_name}")
fi
if [[ -d "${work_dir}/${tokenizers_name}" ]]; then
  tar_items+=("${tokenizers_name}")
fi
tar -C "${work_dir}" -czf "${archive_path}" "${tar_items[@]}"

echo "${archive_path}"
