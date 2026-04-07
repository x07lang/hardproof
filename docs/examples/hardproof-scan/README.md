# Hardproof Scan example artifacts

This directory contains sample artifacts that website/docs/announcements can embed directly.

Generated from the `good-http` fixture target using `hardproof v0.4.0-beta.0`.

The sample target produces a partial score: core quality dimensions pass, but Trust remains unevaluated, so `overall_score` stays `null` and `partial_score` carries the numeric result.

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
x07 bundle --project x07.json --profile os --out out/hardproof
conformance/scripts/spawn_reference_http.sh good-http noauth
out/hardproof scan --url "http://127.0.0.1:18080/mcp" --baseline conformance/pinned/conformance-baseline.yml --out out/scan --format rich
out/hardproof report html --input out/scan/scan.json > out/scan/report.html
out/hardproof report sarif --input out/scan/scan.json > out/scan/report.sarif.json
```
