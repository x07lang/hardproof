#!/usr/bin/env python3
from __future__ import annotations

import html
import json
import re
import subprocess
import sys
import xml.etree.ElementTree as ET
from pathlib import Path


CURRENT_TOOL_VERSION = "0.4.0-beta.4"


def fail(message: str) -> None:
    print(f"ERROR: {message}", file=sys.stderr)
    raise SystemExit(1)


def validate_json(bin_path: Path, schema_rel: str, input_rel: str, repo_root: Path) -> None:
    cmd = [
        str(bin_path),
        "ci",
        "validate-json",
        "--schema",
        schema_rel,
        "--input",
        input_rel,
    ]
    proc = subprocess.run(
        cmd,
        cwd=repo_root,
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        text=True,
        check=False,
    )
    if proc.returncode != 0:
        fail(
            f"schema validation failed for {input_rel} against {schema_rel}\n"
            f"stdout:\n{proc.stdout}\n"
            f"stderr:\n{proc.stderr}"
        )


def main() -> None:
    if len(sys.argv) != 2:
        fail("usage: check_example_artifacts.py <hardproof-bin>")

    repo_root = Path(__file__).resolve().parents[2]
    bin_path = Path(sys.argv[1]).resolve()
    if not bin_path.is_file():
        fail(f"missing hardproof binary: {bin_path}")

    def validate_example(example_name: str, expect_score_mode: str) -> None:
        example_dir = repo_root / "docs" / "examples" / example_name

        scan_rel = f"docs/examples/{example_name}/scan.json"
        conformance_rel = f"docs/examples/{example_name}/conformance.summary.json"
        scan_sarif_rel = f"docs/examples/{example_name}/report.sarif.json"
        conformance_sarif_rel = f"docs/examples/{example_name}/conformance.summary.sarif.json"

        validate_json(bin_path, "schemas/x07.mcp.scan.report.schema.json", scan_rel, repo_root)
        validate_json(bin_path, "schemas/x07.mcp.conformance.summary.schema.json", conformance_rel, repo_root)
        validate_json(bin_path, "schemas/x07.mcp.sarif.schema.json", scan_sarif_rel, repo_root)
        validate_json(bin_path, "schemas/x07.mcp.sarif.schema.json", conformance_sarif_rel, repo_root)

        scan_path = example_dir / "scan.json"
        scan_events_path = example_dir / "scan.events.jsonl"
        scan_html_path = example_dir / "report.html"
        scan_sarif_path = example_dir / "report.sarif.json"
        conformance_json_path = example_dir / "conformance.summary.json"
        conformance_html_path = example_dir / "conformance.summary.html"
        conformance_junit_path = example_dir / "conformance.summary.junit.xml"
        conformance_sarif_path = example_dir / "conformance.summary.sarif.json"
        terminal_svg_path = example_dir / "terminal.svg"

        scan = json.loads(scan_path.read_text(encoding="utf-8"))
        if scan.get("schema_version") != "x07.mcp.scan.report@0.4.0":
            fail(f"{example_name}: unexpected scan schema_version: {scan.get('schema_version')!r}")
        if scan.get("tool_version") != CURRENT_TOOL_VERSION:
            fail(f"{example_name}: unexpected scan tool_version: {scan.get('tool_version')!r}")
        if scan.get("usage_metrics", {}).get("estimator_version") != "v1":
            fail(f"{example_name}: scan usage_metrics.estimator_version must be 'v1'")
        if scan.get("score_mode") != expect_score_mode:
            fail(f"{example_name}: expected score_mode={expect_score_mode!r} (got {scan.get('score_mode')!r})")

        if expect_score_mode == "partial":
            if scan.get("score_truth_status") != "partial":
                fail(f"{example_name}: expected score_truth_status=partial")
            if not isinstance(scan.get("overall_score"), int):
                fail(f"{example_name}: expected overall_score integer for partial")
            if scan.get("overall_score") != scan.get("partial_score"):
                fail(f"{example_name}: expected overall_score to match partial_score for partial")
            if scan.get("unknown_dimensions") != []:
                fail(f"{example_name}: expected unknown_dimensions=[] for partial")
            if scan.get("dimension_coverage", {}).get("trust") is not True:
                fail(f"{example_name}: expected trust dimension_coverage=true")
        else:
            if scan.get("score_truth_status") != "publishable":
                fail(f"{example_name}: expected score_truth_status=publishable")
            if not isinstance(scan.get("overall_score"), int):
                fail(f"{example_name}: expected overall_score integer for full score")
            if scan.get("unknown_dimensions") != []:
                fail(f"{example_name}: expected unknown_dimensions=[] for full score")
            if scan.get("dimension_coverage", {}).get("trust") is not True:
                fail(f"{example_name}: expected trust dimension_coverage=true")

        report_html = scan_html_path.read_text(encoding="utf-8")
        match = re.search(r"<pre>(.*)</pre>", report_html, re.DOTALL)
        if match is None:
            fail(f"{example_name}: report.html is missing the embedded JSON body")
        embedded_scan = json.loads(html.unescape(match.group(1)))
        if embedded_scan != scan:
            fail(f"{example_name}: report.html does not embed the current scan.json payload")

        events = []
        for line in scan_events_path.read_text(encoding="utf-8").splitlines():
            if not line.strip():
                continue
            events.append(json.loads(line))
        if not events:
            fail(f"{example_name}: scan.events.jsonl is empty")
        run_id = scan.get("run_id")
        if any(event.get("run_id") != run_id for event in events):
            fail(f"{example_name}: scan.events.jsonl run_id drifted from scan.json")
        has_check_started = any(event.get("type") == "scan.check.started" for event in events)
        has_check_finished = any(event.get("type") == "scan.check.finished" for event in events)
        if not has_check_started:
            fail(f"{example_name}: scan.events.jsonl is missing scan.check.started events")
        if not has_check_finished:
            fail(f"{example_name}: scan.events.jsonl is missing scan.check.finished events")
        finished = events[-1]
        if finished.get("type") != "scan.finished":
            fail(f"{example_name}: scan.events.jsonl is missing a final scan.finished event")
        if finished.get("report_path") != "out/scan/scan.json":
            fail(f"{example_name}: unexpected scan.finished report_path: {finished.get('report_path')!r}")
        for key in ("score_truth_status", "status", "overall_score", "partial_score"):
            if finished.get(key) != scan.get(key):
                fail(f"{example_name}: scan.finished {key} does not match scan.json")

        conformance = json.loads(conformance_json_path.read_text(encoding="utf-8"))
        if conformance.get("schema_version") != "x07.mcp.conformance.summary@0.2.0":
            fail(f"{example_name}: unexpected conformance schema_version: {conformance.get('schema_version')!r}")
        if conformance.get("tool_version") != CURRENT_TOOL_VERSION:
            fail(f"{example_name}: unexpected conformance tool_version: {conformance.get('tool_version')!r}")

        details = conformance.get("details")
        if not isinstance(details, dict):
            fail(f"{example_name}: conformance.summary.json missing details object")
        counts = details.get("counts")
        if not isinstance(counts, dict):
            fail(f"{example_name}: conformance.summary.json missing details.counts object")

        conformance_html = conformance_html_path.read_text(encoding="utf-8")
        expected_target = f"{conformance['target']['transport']} {conformance['target']['ref']}"
        expected_counts = f"{counts['total']} total, {counts['failed']} failed, {counts['warnings']} warnings"
        for needle in (conformance["generated_at"], expected_target, expected_counts, conformance["schema_version"]):
            if needle not in conformance_html:
                fail(f"{example_name}: conformance.summary.html is stale: missing {needle!r}")

        suite = ET.parse(conformance_junit_path).getroot()
        if suite.tag != "testsuite":
            fail(f"{example_name}: unexpected JUnit root tag: {suite.tag!r}")
        if suite.attrib.get("timestamp") != conformance["generated_at"]:
            fail(f"{example_name}: conformance.summary.junit.xml timestamp drifted from conformance.summary.json")
        if int(suite.attrib.get("tests", "-1")) != counts["total"]:
            fail(f"{example_name}: conformance.summary.junit.xml tests count drifted from conformance.summary.json")
        if int(suite.attrib.get("failures", "-1")) != counts["failed"]:
            fail(f"{example_name}: conformance.summary.junit.xml failures count drifted from conformance.summary.json")

        scan_sarif = json.loads(scan_sarif_path.read_text(encoding="utf-8"))
        scan_runs = scan_sarif.get("runs")
        if not isinstance(scan_runs, list) or len(scan_runs) != 1:
            fail(f"{example_name}: report.sarif.json must contain exactly one run")
        scan_driver = scan_runs[0].get("tool", {}).get("driver", {})
        if scan_driver.get("name") != "hardproof":
            fail(f"{example_name}: report.sarif.json driver.name must be 'hardproof'")
        if len(scan_runs[0].get("results", [])) != len(scan.get("findings", [])):
            fail(f"{example_name}: report.sarif.json results count drifted from scan.json findings")

        conformance_sarif = json.loads(conformance_sarif_path.read_text(encoding="utf-8"))
        conformance_runs = conformance_sarif.get("runs")
        if not isinstance(conformance_runs, list) or len(conformance_runs) != 1:
            fail(f"{example_name}: conformance.summary.sarif.json must contain exactly one run")
        conformance_driver = conformance_runs[0].get("tool", {}).get("driver", {})
        if conformance_driver.get("name") != "hardproof":
            fail(f"{example_name}: conformance.summary.sarif.json driver.name must be 'hardproof'")
        if conformance_driver.get("version") != CURRENT_TOOL_VERSION:
            fail(f"{example_name}: conformance.summary.sarif.json driver.version drifted from current tool_version")

        svg_text = terminal_svg_path.read_text(encoding="utf-8")
        if expect_score_mode == "partial":
            if "Hardproof - PARTIAL SCORE" not in svg_text:
                fail(f"{example_name}: terminal.svg is missing PARTIAL SCORE banner")
        else:
            if "Hardproof - FULL SCORE" not in svg_text:
                fail(f"{example_name}: terminal.svg is missing FULL SCORE banner")
        for needle in ("mode: tokenizer_exact", "confidence: high", "tokenizer: openai:o200k_base"):
            if needle not in svg_text:
                fail(f"{example_name}: terminal.svg is missing usage truth line: {needle!r}")

    validate_example("hardproof-scan", "partial")
    validate_example("hardproof-scan-full", "full")

    print("ok: example artifacts")


if __name__ == "__main__":
    main()
