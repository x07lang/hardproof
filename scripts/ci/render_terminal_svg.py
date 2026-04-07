#!/usr/bin/env python3
from __future__ import annotations

import html
import re
import sys
from pathlib import Path


def fail(message: str) -> None:
    print(f"ERROR: {message}", file=sys.stderr)
    raise SystemExit(1)


def strip_ansi(text: str) -> str:
    return re.sub(r"\x1b\[[0-9;?]*[ -/]*[@-~]", "", text)


def main() -> None:
    if len(sys.argv) != 3:
        fail("usage: render_terminal_svg.py <input.txt> <output.svg>")

    input_path = Path(sys.argv[1])
    output_path = Path(sys.argv[2])
    lines = strip_ansi(input_path.read_text(encoding="utf-8")).rstrip("\n").splitlines()
    if not lines:
        fail("terminal text is empty")

    max_len = max(len(line) for line in lines)
    char_width = 8
    line_height = 20
    width = max(960, 48 + (max_len * char_width))
    height = 90 + (len(lines) * line_height)

    tspans = []
    for idx, line in enumerate(lines):
        dy = "0" if idx == 0 else str(line_height)
        tspans.append(f'    <tspan x="24" dy="{dy}">{html.escape(line)}</tspan>')

    svg = "\n".join(
        [
            f'<svg xmlns="http://www.w3.org/2000/svg" width="{width}" height="{height}" viewBox="0 0 {width} {height}">',
            f'  <rect width="{width}" height="{height}" rx="12" fill="#0b0e14" />',
            '  <circle cx="24" cy="22" r="6" fill="#ff5f56" />',
            '  <circle cx="44" cy="22" r="6" fill="#ffbd2e" />',
            '  <circle cx="64" cy="22" r="6" fill="#27c93f" />',
            '  <text',
            '    x="24"',
            '    y="58"',
            '    font-family="SFMono-Regular, Menlo, Monaco, Consolas, monospace"',
            '    font-size="14"',
            '    fill="#c0caf5"',
            '    xml:space="preserve"',
            '  >',
            *tspans,
            '  </text>',
            '</svg>',
            "",
        ]
    )
    output_path.write_text(svg, encoding="utf-8")


if __name__ == "__main__":
    main()
