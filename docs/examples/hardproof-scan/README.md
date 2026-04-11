# Hardproof Scan example artifacts

This directory contains sample artifacts that website/docs/announcements can embed directly.

Generated from the `good-http` fixture target using `hardproof v0.4.0-beta.4`.

The sample target produces a partial score: core quality dimensions pass, but Trust evidence is missing, so `score_truth_status` is `partial` and the Trust dimension fails deterministically. `overall_score` is still computed as the effective score (matching `partial_score`), but the score is not publishable yet.

For a publishable full-score example (Trust evaluated), see: `docs/examples/hardproof-scan-full/`.

## Contents

- `scan.json`: scan report (schema `x07.mcp.scan.report@0.4.0`)
- `scan.json` references additional dimension artifacts (for example `perf.samples.json`) that are emitted in a real scan output directory but are not checked into this example bundle.
- `scan.events.jsonl`: scan event stream
- `conformance.summary.json`: conformance dimension summary (schema `x07.mcp.conformance.summary@0.2.0`)
- `conformance.summary.html`: conformance dimension HTML report
- `conformance.summary.junit.xml`: conformance dimension JUnit XML report
- `conformance.summary.sarif.json`: conformance dimension SARIF report
- `trust/server.observed.json`: self-reported server identity snapshot captured from `initialize`
- `report.html`: HTML rendering of `scan.json`
- `report.sarif.json`: SARIF rendering of `scan.json`
- `terminal.svg`: screenshot-style rendering of a `hardproof scan` terminal run

## Repro

From the repo root:

```sh
make refresh-example-artifacts
```
