# Hardproof Scan example artifacts (publishable full score)

This directory contains sample artifacts that website/docs/announcements can embed directly.

Generated from the `good-http` fixture target using `hardproof v0.4.0-beta.3`, with Trust inputs provided (`--server-json` + `--mcpb`) to unlock a publishable full score.

## Contents

- `scan.json`: scan report (schema `x07.mcp.scan.report@0.4.0`)
- `scan.json` references additional dimension artifacts (for example `perf.samples.json`) that are emitted in a real scan output directory but are not checked into this example bundle.
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
