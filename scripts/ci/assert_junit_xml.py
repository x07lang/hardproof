#!/usr/bin/env python3

import sys
import xml.etree.ElementTree as ET
from pathlib import Path


def main(argv: list[str]) -> int:
    if len(argv) != 2:
        print("usage: assert_junit_xml.py <xml_path>", file=sys.stderr)
        return 2

    xml_path = Path(argv[1])
    raw = xml_path.read_text(encoding="utf-8")
    root = ET.fromstring(raw)

    if root.tag != "testsuite":
        raise ValueError(f"unexpected root tag: {root.tag!r}")

    suite_name = root.attrib.get("name")
    if suite_name != "x07-mcp-test conformance":
        raise ValueError(f"unexpected testsuite name: {suite_name!r}")

    testcases = root.findall("testcase")
    if not testcases:
        raise ValueError("missing testcase elements")

    for tc in testcases:
        if "classname" not in tc.attrib:
            raise ValueError("missing testcase@classname")
        if "name" not in tc.attrib:
            raise ValueError("missing testcase@name")

        failures = tc.findall("failure")
        if len(failures) > 1:
            raise ValueError("expected at most one failure per testcase")
        for f in failures:
            if "message" not in f.attrib:
                raise ValueError("missing failure@message")

    return 0


if __name__ == "__main__":
    raise SystemExit(main(sys.argv))

