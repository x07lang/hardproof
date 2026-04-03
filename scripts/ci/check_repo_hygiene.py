#!/usr/bin/env python3
from __future__ import annotations

import re
import sys
from pathlib import Path


def find_repo_root() -> Path:
    here = Path(__file__).resolve()
    return here.parents[2]


def should_skip_dir(path: Path) -> bool:
    return any(
        part in {".git", ".x07", "dist", "node_modules", "out"} for part in path.parts
    )


def scan_crlf(repo_root: Path) -> list[Path]:
    text_exts = {
        ".json",
        ".md",
        ".py",
        ".sh",
        ".toml",
        ".yml",
        ".yaml",
    }

    bad: list[Path] = []
    for path in repo_root.rglob("*"):
        if path.is_dir():
            continue
        if should_skip_dir(path):
            continue
        if path.suffix not in text_exts:
            continue

        data = path.read_bytes()
        if b"\r\n" in data:
            bad.append(path)

    return bad


def validate_action_manifest(repo_root: Path) -> list[str]:
    errors: list[str] = []
    action_paths = [
        repo_root / "action" / "action.yml",
        repo_root / "hardproof-scan" / "action.yml",
    ]

    for action_path in action_paths:
        if not action_path.exists():
            continue
        lines = action_path.read_text(encoding="utf-8").splitlines()
        for idx, line in enumerate(lines, start=1):
            match = re.match(r"^\s*description:\s*(.*)$", line)
            if not match:
                continue
            value = match.group(1).strip()
            if ": " not in value:
                continue
            if value.startswith(("'", '"', "|", ">")):
                continue
            errors.append(
                f"{action_path.relative_to(repo_root)}:{idx}: description contains ': ' and must be quoted"
            )
    return errors


def main() -> int:
    repo_root = find_repo_root()

    crlf_files = scan_crlf(repo_root)
    action_errors = validate_action_manifest(repo_root)

    if crlf_files or action_errors:
        print("ERROR: repo hygiene checks failed.", file=sys.stderr)
        if crlf_files:
            print("CRLF line endings found:", file=sys.stderr)
            for path in crlf_files:
                rel = path.relative_to(repo_root)
                print(f"- {rel}", file=sys.stderr)
        if action_errors:
            print("Action manifest issues:", file=sys.stderr)
            for err in action_errors:
                print(f"- {err}", file=sys.stderr)
        return 1

    print("ok: repo hygiene")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
