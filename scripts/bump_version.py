#!/usr/bin/env python3
from __future__ import annotations

import argparse
import re
import subprocess
import sys
from pathlib import Path


VERSION_RE = re.compile(r"^(?P<core>[0-9]+\.[0-9]+\.[0-9]+-(?:alpha|beta)\.[0-9]+)$")


def fail(message: str) -> None:
    print(f"ERROR: {message}", file=sys.stderr)
    raise SystemExit(1)


def normalize_version(raw: str) -> str:
    v = raw.strip()
    if v.startswith("v"):
        v = v[1:]
    if not VERSION_RE.match(v):
        fail(f"invalid version: {raw!r} (expected e.g. 0.4.0-beta.2 or v0.4.0-beta.2)")
    return v


def read_text(path: Path) -> str:
    return path.read_text(encoding="utf-8")


def write_text(path: Path, text: str) -> None:
    path.write_text(text, encoding="utf-8")


def replace_all(path: Path, old: str, new: str) -> int:
    text = read_text(path)
    if old not in text:
        return 0
    write_text(path, text.replace(old, new))
    return text.count(old)


def parse_current_tool_version(check_script: Path) -> str:
    text = read_text(check_script)
    m = re.search(r'^CURRENT_TOOL_VERSION\s*=\s*"([^"]+)"\s*$', text, flags=re.MULTILINE)
    if m is None:
        fail(f"failed to locate CURRENT_TOOL_VERSION in {check_script}")
    return normalize_version(m.group(1))


def run(cmd: list[str], *, cwd: Path) -> None:
    proc = subprocess.run(cmd, cwd=cwd, check=False)
    if proc.returncode != 0:
        fail(f"command failed ({proc.returncode}): {' '.join(cmd)}")


def main() -> None:
    ap = argparse.ArgumentParser(description="Bump hardproof tool version across release-facing surfaces.")
    ap.add_argument(
        "--to",
        required=True,
        help="New version (example: 0.4.0-beta.2 or v0.4.0-beta.2).",
    )
    ap.add_argument(
        "--refresh-example-artifacts",
        action=argparse.BooleanOptionalAction,
        default=True,
        help="Regenerate docs/examples artifacts after bump (default: true).",
    )
    args = ap.parse_args()

    repo_root = Path(__file__).resolve().parents[1]
    check_script = repo_root / "scripts" / "ci" / "check_example_artifacts.py"
    old_version = parse_current_tool_version(check_script)
    new_version = normalize_version(args.to)

    if old_version == new_version:
        fail(f"old and new versions are the same: {old_version}")

    replace_paths: list[Path] = [
        repo_root / "arch" / "schemas" / "scan_report_manifest.x07schema.json",
        repo_root / "scripts" / "ci" / "check_example_artifacts.py",
        repo_root / "scripts" / "ci" / "build_release_binaries.sh",
        repo_root / "scripts" / "install.sh",
        repo_root / "README.md",
        repo_root / "action" / "README.md",
        repo_root / "action" / "action.yml",
        repo_root / "hardproof-scan" / "README.md",
        repo_root / "hardproof-scan" / "action.yml",
        repo_root / "docs" / "examples" / "hardproof-scan" / "README.md",
        repo_root / "docs" / "examples" / "hardproof-scan-full" / "README.md",
        repo_root / "tests" / "scan_contracts.x07.json",
    ]

    # X07 AST sources are minified (single-line JSON), so treat these as text replacements.
    for src_path in sorted((repo_root / "cli" / "src").rglob("*.x07.json")):
        replace_paths.append(src_path)

    for fixture_path in sorted((repo_root / "fixtures" / "reports").glob("*.json")):
        replace_paths.append(fixture_path)

    missing: list[Path] = [p for p in replace_paths if not p.is_file()]
    if missing:
        fail("missing expected files:\n" + "\n".join(f"- {p}" for p in missing))

    total_replacements = 0
    for path in replace_paths:
        total_replacements += replace_all(path, old_version, new_version)

    if total_replacements == 0:
        fail(f"made no replacements; is current version really {old_version}?")

    if args.refresh_example_artifacts:
        run(["make", "refresh-example-artifacts"], cwd=repo_root)

    print(f"ok: bumped hardproof {old_version} -> {new_version}")


if __name__ == "__main__":
    main()
