# Scan (v0.3)

`hardproof scan` is the primary orchestrator command. It runs five deterministic dimensions (Conformance, Security, Performance, Trust, Reliability) plus a first-class usage/token overlay and emits a stable `x07.mcp.scan.report@0.3.0` report.

## Quickstart

```sh
hardproof scan --url "http://127.0.0.1:3000/mcp" --out out/scan
hardproof report summary --input out/scan/scan.json --ui rich
hardproof ci --url "http://127.0.0.1:3000/mcp" --min-score 80 --max-critical 0
```

## Output modes

Use `--format` (or `--ui`) to choose a presentation mode:

- `rich` (default): terminal scorecard using `ext-cli-ux`
- `compact`: condensed text
- `json`: the full report JSON
- `jsonl`: the scan event stream

## Extra scan options

- `--score-preview`: emit intermediate score preview events into `scan.events.jsonl`.
- `--metrics <STR>`: request extra metric payloads in `scan.events.jsonl` (example: `usage,perf`).
- `--server-json <PATH>` / `--mcpb <PATH>`: enable deeper Trust checks by providing registry artifacts.

## Output directory layout

`hardproof scan --out <DIR>` writes:

- `scan.json` (schema: `x07.mcp.scan.report@0.3.0`)
- `scan.events.jsonl` (stable JSONL event stream)
- `conformance.summary.*` artifacts when the conformance dimension runs
- other referenced artifacts as the scan grows (pinned in `scan.json.artifacts[]`)

## Event stream (`scan.events.jsonl`)

The event stream is intended for CI log streaming and future TUI/integrations.

Current event types include:

- `scan.started`
- `scan.stage.started` / `scan.stage.finished`
- `scan.dimension.started` / `scan.dimension.finished`
- `scan.score.preview` (when `--score-preview` is enabled)
- `scan.metrics.dimension` / `scan.metrics.usage` (when `--metrics` is enabled)
- `scan.finished`

## Conversions and explanations

Use supporting commands to convert and interpret scan reports:

```sh
hardproof report summary --input out/scan/scan.json --ui rich|compact
hardproof report html --input out/scan/scan.json > out/scan/report.html
hardproof report sarif --input out/scan/scan.json > out/scan/report.sarif.json
hardproof explain <FINDING_CODE>
```

## CI gating

`hardproof ci` evaluates a scan report against thresholds and returns:

- `0` pass
- `1` policy failure
- `2` invocation/config/runtime failure

Common gates:

```sh
hardproof ci --url "http://127.0.0.1:3000/mcp" --min-score 80 --min-dimension conformance=85 --max-critical 0
hardproof ci --url "http://127.0.0.1:3000/mcp" --max-tool-catalog-tokens 2000 --max-response-p95-tokens 2000
```
