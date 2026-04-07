# Hardproof Scan example artifacts

This directory contains sample artifacts that website/docs/announcements can embed directly.

Generated from the `good-http` fixture target using `hardproof v0.4.0-beta.1`.

The sample target produces a partial score: core quality dimensions pass, but Trust remains unevaluated, so `score_mode` is `partial`, `overall_score` stays `null`, and rich output renders the primary score as withheld.

## Contents

- `scan.json`: scan report (schema `x07.mcp.scan.report@0.4.0`)
- `scan.events.jsonl`: scan event stream
- `conformance.summary.json`: conformance dimension summary (schema `x07.mcp.conformance.summary@0.2.0`)
- `conformance.summary.html`: conformance dimension HTML report
- `conformance.summary.junit.xml`: conformance dimension JUnit XML report
- `conformance.summary.sarif.json`: conformance dimension SARIF report
- `report.html`: HTML rendering of `scan.json`
- `report.sarif.json`: SARIF rendering of `scan.json`
- `terminal.svg`: screenshot-style rendering of a `hardproof scan` terminal run

## Repro

From the repo root:

```sh
make refresh-example-artifacts
```
