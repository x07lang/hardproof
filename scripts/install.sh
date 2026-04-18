#!/usr/bin/env bash
set -euo pipefail

REPO="x07lang/hardproof"

usage() {
  cat <<'USAGE'
Install the Hardproof verifier binary from GitHub Releases.

Usage:
  install.sh --tag <v0.X.Y-beta.N>
  install.sh --tag latest-beta
  install.sh --tag <v0.1.0-alpha.N>
  install.sh --tag latest-alpha

Options:
  --tag <TAG>         Git tag to install from (example: v0.4.0-beta.7, latest-beta, v0.1.0-alpha.9, latest-alpha)
  --install-dir <DIR> Install directory (default: ~/.local/bin)

Notes:
  - Windows is supported via WSL2. Run this script inside WSL2 to install the linux_x86_64 artifact.
  - Tokenizer tables are installed to:
      $XDG_DATA_HOME/hardproof/tokenizers (fallback: ~/.local/share/hardproof/tokenizers)
USAGE
}

tag=""
install_dir="${HOME}/.local/bin"

while [[ $# -gt 0 ]]; do
  case "$1" in
    --tag)
      tag="${2:?missing value for --tag}"
      shift 2
      ;;
    --install-dir)
      install_dir="${2:?missing value for --install-dir}"
      shift 2
      ;;
    -h|--help)
      usage
      exit 0
      ;;
    *)
      echo "ERROR: unknown argument: $1" >&2
      usage >&2
      exit 2
      ;;
  esac
done

if [[ -z "${tag}" ]]; then
  echo "ERROR: missing --tag" >&2
  usage >&2
  exit 2
fi

if [[ "${tag}" == "latest-beta" || "${tag}" == "latest-beta"* ]]; then
  echo "==> resolve latest beta tag for ${REPO}"
  curl_args=(
    -fsSL
    "https://api.github.com/repos/${REPO}/releases"
  )
  if [[ -n "${GITHUB_TOKEN:-}" ]]; then
    curl_args=(
      -fsSL
      -H "Authorization: Bearer ${GITHUB_TOKEN}"
      -H "X-GitHub-Api-Version: 2022-11-28"
      "https://api.github.com/repos/${REPO}/releases"
    )
  fi
  releases_json="$(curl "${curl_args[@]}")"
  tag="$(
    python3 - <<'PY' "${releases_json}"
import json, re, sys
data = json.loads(sys.argv[1])
for r in data:
  t = r.get("tag_name","")
  if re.match(r"^v[0-9]+\.[0-9]+\.[0-9]+-beta\.[0-9]+$", t):
    print(t)
    sys.exit(0)
print("", end="")
sys.exit(0)
PY
  )"
  if [[ -z "${tag}" ]]; then
    echo "ERROR: failed to resolve latest beta tag; pass --tag vX.Y.Z-beta.N explicitly." >&2
    exit 1
  fi
elif [[ "${tag}" == "latest-alpha" || "${tag}" == "latest-alpha"* ]]; then
  echo "==> resolve latest alpha tag for ${REPO}"
  curl_args=(
    -fsSL
    "https://api.github.com/repos/${REPO}/releases"
  )
  if [[ -n "${GITHUB_TOKEN:-}" ]]; then
    curl_args=(
      -fsSL
      -H "Authorization: Bearer ${GITHUB_TOKEN}"
      -H "X-GitHub-Api-Version: 2022-11-28"
      "https://api.github.com/repos/${REPO}/releases"
    )
  fi
  releases_json="$(curl "${curl_args[@]}")"
  tag="$(
    python3 - <<'PY' "${releases_json}"
import json, re, sys
data = json.loads(sys.argv[1])
for r in data:
  t = r.get("tag_name","")
  if re.match(r"^v0\.1\.\d+-alpha\.\d+$", t):
    print(t)
    sys.exit(0)
print("", end="")
sys.exit(0)
PY
  )"
  if [[ -z "${tag}" ]]; then
    echo "ERROR: failed to resolve latest alpha tag; pass --tag v0.1.0-alpha.N explicitly." >&2
    exit 1
  fi
fi

if [[ "${tag}" != v* ]]; then
  tag="v${tag}"
fi

platform="$(uname -s)"
arch="$(uname -m)"

artifact_suffix=""
case "${platform}-${arch}" in
  Linux-x86_64) artifact_suffix="linux_x86_64" ;;
  Darwin-arm64) artifact_suffix="macos_arm64" ;;
  Darwin-x86_64) artifact_suffix="macos_x86_64" ;;
  *)
    echo "ERROR: unsupported platform/arch: ${platform}-${arch}" >&2
    echo "NOTE: on Windows, use WSL2 and install from inside your Linux distro." >&2
    exit 2
    ;;
esac

version="${tag#v}"
base_url="https://github.com/${REPO}/releases/download/${tag}"

install_path="${install_dir}/hardproof"
data_home="${XDG_DATA_HOME:-${HOME}/.local/share}"
tokenizers_install_dir="${data_home}/hardproof/tokenizers"

tmp_dir="$(mktemp -d)"
trap 'rm -rf "${tmp_dir}"' EXIT

checksums_path="${tmp_dir}/checksums.txt"

echo "==> resolve release assets for ${tag}"
release_url="https://api.github.com/repos/${REPO}/releases/tags/${tag}"
release_curl_args=(
  -fsSL
  "${release_url}"
)
if [[ -n "${GITHUB_TOKEN:-}" ]]; then
  release_curl_args=(
    -fsSL
    -H "Authorization: Bearer ${GITHUB_TOKEN}"
    -H "X-GitHub-Api-Version: 2022-11-28"
    "${release_url}"
  )
fi
release_json="$(curl "${release_curl_args[@]}")"

asset_info="$(
  python3 -c '
import json
import re
import sys

tag = sys.argv[1]
platform = sys.argv[2]
arch = sys.argv[3]
version = tag[1:] if tag.startswith("v") else tag

release = json.loads(sys.stdin.read() or "{}")
assets = release.get("assets") or []

patterns: list[re.Pattern[str]] = []
if platform == "Linux" and arch == "x86_64":
    patterns.append(re.compile(rf"^hardproof_{re.escape(version)}_linux_x86_64\.tar\.gz$"))
    patterns.append(re.compile(rf"^hardproof-{re.escape(tag)}-linux-x64\.tar\.gz$"))
elif platform == "Darwin" and arch == "arm64":
    patterns.append(re.compile(rf"^hardproof_{re.escape(version)}_macos_arm64\.tar\.gz$"))
    patterns.append(re.compile(rf"^hardproof-{re.escape(tag)}-darwin-arm64\.tar\.gz$"))
elif platform == "Darwin" and arch == "x86_64":
    patterns.append(re.compile(rf"^hardproof_{re.escape(version)}_macos_x86_64\.tar\.gz$"))
    patterns.append(re.compile(rf"^hardproof-{re.escape(tag)}-darwin-x64\.tar\.gz$"))
else:
    raise SystemExit(f"unsupported platform/arch: {platform}-{arch}")

asset_name = ""
asset_url = ""
for pat in patterns:
    for asset in assets:
        name = asset.get("name", "")
        if pat.match(name):
            asset_name = name
            asset_url = asset.get("browser_download_url", "")
            break
    if asset_name:
        break

checksums_url = ""
for asset in assets:
    if asset.get("name", "") == "checksums.txt":
        checksums_url = asset.get("browser_download_url", "")
        break

if not asset_name or not asset_url:
    available = ", ".join(sorted(a.get("name", "") for a in assets if a.get("name")))
    raise SystemExit(f"missing release artifact for {platform}-{arch} (tag={tag}); assets=[{available}]")

print(asset_name)
print(asset_url)
print(checksums_url)
' "${tag}" "${platform}" "${arch}" <<<"${release_json}"
)"

asset_name="$(printf '%s\n' "${asset_info}" | sed -n '1p')"
asset_url="$(printf '%s\n' "${asset_info}" | sed -n '2p')"
checksums_url="$(printf '%s\n' "${asset_info}" | sed -n '3p')"
if [[ -z "${checksums_url}" ]]; then
  checksums_url="${base_url}/checksums.txt"
fi
archive_path="${tmp_dir}/${asset_name}"

echo "==> download ${asset_name}"
curl -fSL \
  --connect-timeout 10 \
  --max-time 600 \
  --retry 8 \
  --retry-delay 2 \
  --retry-all-errors \
  --output "${archive_path}" \
  "${asset_url}"

echo "==> download checksums.txt"
curl -fSL \
  --connect-timeout 10 \
  --max-time 600 \
  --retry 8 \
  --retry-delay 2 \
  --retry-all-errors \
  --output "${checksums_path}" \
  "${checksums_url}"

expected_line="$(grep -E "^[a-f0-9]{64}  ${asset_name}$" "${checksums_path}" | head -n 1 || true)"
if [[ -z "${expected_line}" ]]; then
  echo "ERROR: checksums.txt does not contain an entry for ${asset_name}" >&2
  exit 2
fi

echo "==> verify checksum"
if command -v sha256sum >/dev/null 2>&1; then
  (
    cd "${tmp_dir}"
    printf '%s\n' "${expected_line}" | sha256sum -c - >/dev/null
  )
elif command -v shasum >/dev/null 2>&1; then
  expected_hash="$(printf '%s\n' "${expected_line}" | awk '{print $1}')"
  actual_hash="$(shasum -a 256 "${archive_path}" | awk '{print $1}')"
  if [[ "${expected_hash}" != "${actual_hash}" ]]; then
    echo "ERROR: sha256 mismatch for ${asset_name}" >&2
    exit 2
  fi
else
  echo "WARN: sha256sum/shasum not found; skipping checksum verification" >&2
fi

echo "==> install ${install_path}"
mkdir -p "${install_dir}"
tar -xzf "${archive_path}" -C "${tmp_dir}"
cp "${tmp_dir}/hardproof" "${install_path}"
chmod +x "${install_path}"

if [[ -d "${tmp_dir}/tokenizers" ]]; then
  mkdir -p "${tokenizers_install_dir}"
  if ls "${tmp_dir}/tokenizers/"*.table.bin >/dev/null 2>&1; then
    cp "${tmp_dir}/tokenizers/"*.table.bin "${tokenizers_install_dir}/"
    echo "==> installed tokenizer tables to ${tokenizers_install_dir}"
  fi
fi

echo "==> ok: ${install_path}"
echo
echo "Next:"
echo "  hardproof --help"
echo "  hardproof doctor"
echo "  hardproof scan --url \"http://127.0.0.1:3000/mcp\" --out out/scan --machine json"
