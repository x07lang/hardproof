#!/usr/bin/env python3
from __future__ import annotations

import json
import subprocess
import sys
from pathlib import Path


def fail(message: str) -> None:
    print(f"ERROR: {message}", file=sys.stderr)
    raise SystemExit(1)


def main() -> None:
    repo_root = Path(__file__).resolve().parents[2]
    fixtures_dir = repo_root / "fixtures" / "reports"
    assert_script = repo_root / "scripts" / "ci" / "assert_scan_report_consistency.py"

    if not fixtures_dir.is_dir():
        fail(f"missing fixtures directory: {fixtures_dir}")
    if not assert_script.is_file():
        fail(f"missing assertion script: {assert_script}")

    scan_reports: list[Path] = []
    for path in sorted(fixtures_dir.glob("scan*.sample.json")):
        try:
            doc = json.loads(path.read_text(encoding="utf-8"))
        except json.JSONDecodeError as exc:
            fail(f"invalid JSON in fixture: {path.relative_to(repo_root)} ({exc})")

        schema_version = doc.get("schema_version")
        if not isinstance(schema_version, str):
            continue
        if not schema_version.startswith("x07.mcp.scan.report@"):
            continue
        scan_reports.append(path)

    if not scan_reports:
        fail("no scan report fixtures found under fixtures/reports/")

    for path in scan_reports:
        rel = str(path.relative_to(repo_root))
        proc = subprocess.run(
            [sys.executable, str(assert_script.relative_to(repo_root)), rel],
            cwd=repo_root,
            check=False,
        )
        if proc.returncode != 0:
            fail(f"scan report fixture consistency check failed: {rel}")

    print(f"ok: scan report fixtures ({len(scan_reports)})")


if __name__ == "__main__":
    main()
