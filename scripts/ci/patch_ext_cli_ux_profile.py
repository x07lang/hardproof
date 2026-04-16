#!/usr/bin/env python3
from __future__ import annotations

import sys
from pathlib import Path


TARGET_REL = Path(
    ".x07/deps/ext-cli-ux/0.1.7/modules/std/cli/profile.x07.json"
)

OLD = '["std.parse.u32_dec",["bytes.view","n_b"]]'
NEW = '["result_i32.unwrap_or",["std.parse.u32_dec",["bytes.view","n_b"]],0]'


def patch_text(text: str) -> tuple[str, bool]:
    if NEW in text:
        return text, False
    if OLD not in text:
        raise ValueError("expected pattern not found")
    return text.replace(OLD, NEW, 1), True


def main() -> int:
    repo_root = Path(__file__).resolve().parents[2]
    target = repo_root / TARGET_REL
    if not target.exists():
        print(f"ERROR: expected dependency file missing: {TARGET_REL}", file=sys.stderr)
        return 2

    before = target.read_text(encoding="utf-8")
    try:
        after, changed = patch_text(before)
    except ValueError as exc:
        print(f"ERROR: cannot patch {TARGET_REL}: {exc}", file=sys.stderr)
        return 2

    if changed:
        target.write_text(after, encoding="utf-8")
        print(f"patched {TARGET_REL}")

    return 0


if __name__ == "__main__":
    raise SystemExit(main())
