#!/usr/bin/env python3
from __future__ import annotations

import re
import sys
from pathlib import Path


VERSION_RE = re.compile(r"\b(?P<v>[0-9]+\.[0-9]+\.[0-9]+-(?:alpha|beta)\.[0-9]+)\b")
CURRENT_RE = re.compile(r'^CURRENT_TOOL_VERSION\s*=\s*"([^"]+)"\s*$', flags=re.MULTILINE)


def fail(message: str) -> None:
    print(f"ERROR: {message}", file=sys.stderr)
    raise SystemExit(1)


def read_text(path: Path) -> str:
    return path.read_text(encoding="utf-8")


def parse_current_tool_version(repo_root: Path) -> str:
    text = read_text(repo_root / "scripts" / "ci" / "check_example_artifacts.py")
    m = CURRENT_RE.search(text)
    if m is None:
        fail("failed to locate CURRENT_TOOL_VERSION in scripts/ci/check_example_artifacts.py")
    return m.group(1).strip()


def main() -> None:
    repo_root = Path(__file__).resolve().parents[2]
    current = parse_current_tool_version(repo_root)

    # These are the surfaces that should never drift from the current tool version.
    globs = [
        "arch/schemas/*.x07schema.json",
        "cli/src/**/*.x07.json",
        "tests/scan_contracts.x07.json",
        "fixtures/reports/*.json",
        "docs/examples/hardproof-scan/*.json",
    ]

    mismatches: dict[str, set[str]] = {}
    for g in globs:
        for path in sorted(repo_root.glob(g)):
            if not path.is_file():
                continue
            text = read_text(path)
            versions = {m.group("v") for m in VERSION_RE.finditer(text)}
            bad = {v for v in versions if v != current}
            if bad:
                mismatches[str(path.relative_to(repo_root))] = bad

    if mismatches:
        lines = ["version drift detected (expected CURRENT_TOOL_VERSION=" + repr(current) + "):"]
        for rel, bad in sorted(mismatches.items()):
            lines.append(f"- {rel}: {', '.join(sorted(bad))}")
        fail("\n".join(lines))

    print("ok: version consistency")


if __name__ == "__main__":
    main()
