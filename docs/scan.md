# Scan (v0.4)

`hardproof scan` is the primary orchestrator command. It runs five deterministic dimensions (Conformance, Security, Performance, Trust, Reliability) plus a first-class usage/token overlay and emits a stable `x07.mcp.scan.report@0.4.0` report.

## Quickstart

```sh
hardproof scan --url "http://127.0.0.1:3000/mcp" --out out/scan
hardproof report summary --input out/scan/scan.json --ui rich
hardproof ci --url "http://127.0.0.1:3000/mcp" --min-score 80 --max-critical 0
```

## Output modes

Use `--format` (or `--ui`) to choose a presentation mode:

- `rich` (default): live progress on interactive terminals + final scorecard
- `tui`: alternate-screen live UI (falls back to `rich` when the terminal is non-interactive)
- `compact`: stable, line-oriented output suited to CI logs
- `json`: the full report JSON
- `jsonl`: the scan event stream only (live JSONL to stdout)

Live rendering is enabled by default for `rich`, `compact`, `jsonl`, and `tui` on interactive terminals. Use `--no-live` to disable live rendering and only print the final report render.

## Extra scan options

- `--score-preview`: emit intermediate score preview events into `scan.events.jsonl`.
- `--score-preview` stays provisional until a full score is available. Partial runs still stream preview events with `overall_score=null`, a numeric `partial_score`, and `score_available=true`.
- `--metrics <STR>`: request extra metric payloads in `scan.events.jsonl` (example: `usage,perf`).
- `--perf-profile <STR>`: set the workload profile for the Performance dimension (`smoke|steady_small|concurrent_small`).
- `--max-avg-tool-description-tokens <INT>`: attach a usage-policy preview threshold to the scan invocation.
- `--max-tool-count <INT>`: attach a usage-policy preview threshold to the scan invocation.
- `--require-trust-for-full-score`: require trust evidence before reporting a full overall score.
- `--server-json <PATH>` / `--mcpb <PATH>`: enable deeper Trust checks by providing registry artifacts.
- `--event-log <PATH>`: override the default `scan.events.jsonl` path.
- `--render-interval-ms <INT>`: live render cadence for debugging/profiling.

`hardproof scan` accepts the usage-policy threshold flags so the same invocation surface is available in local triage. Enforcement still happens in `hardproof ci`.

Partial scans are explicit in `v0.4.0`: `score_mode=partial`, `overall_score` stays `null`, `partial_score` remains machine-readable, and `score_truth_status` plus `partial_reasons` / `gating_reasons` explain why the scan is not eligible for a full score.

## Token truth modes

Hardproof’s token/context metrics support multiple truth classes:

- `estimate`: deterministic estimates (not billing-grade)
- `tokenizer_exact`: exact counts under a selected tokenizer profile
- `trace_observed`: observed counts from a real client trace
- `mixed`: a mix of exact + observed, per-metric

Key flags:

```sh
hardproof scan --tokenizer openai:o200k_base
hardproof scan --usage-mode exact --tokenizer openai:o200k_base
hardproof scan --usage-mode observed --token-trace path/to/trace.json
hardproof scan --usage-mode estimate
```

Notes:

- `--usage-mode exact` requires `--tokenizer`.
- `--usage-mode observed` requires `--token-trace`.
- `--usage-mode auto` selects the best available truth source (tokenizer and/or trace), otherwise falls back to `estimate`.
- Hardproof locates tokenizer tables in this order:
  - `HARDPROOF_TOKENIZERS_DIR`
  - `$XDG_DATA_HOME/hardproof/tokenizers` (fallback: `~/.local/share/hardproof/tokenizers`)
  - `./tokenizers`

`--token-trace` currently expects a JSON object shaped like:

```json
{
  "source": "trace:<id>",
  "metrics": {
    "tool_catalog_tokens": 3068,
    "avg_tool_description_tokens": 42,
    "max_tool_description_tokens": 120,
    "input_schema_tokens_total": 900,
    "response_tokens_p50": 12,
    "response_tokens_p95": 48
  }
}
```

## Output directory layout

`hardproof scan --out <DIR>` writes:

- `<DIR>` may be relative or absolute.
- `scan.json` (schema: `x07.mcp.scan.report@0.4.0`)
- `scan.events.jsonl` (stable JSONL event stream)
- `conformance.summary.*` artifacts when the conformance dimension runs
- `perf.samples.json` when the performance dimension runs (referenced via `scan.json.artifacts[]`)
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

`hardproof explain` covers the scan finding codes emitted in `scan.json`, including aggregate conformance failures (`CONFORMANCE.FAIL`) and scenario-specific codes such as `CONFORMANCE.tools-call-with-progress`.

## CI gating

`hardproof ci` evaluates a scan report against thresholds and returns:

- `0` pass
- `1` policy failure
- `2` invocation/config/runtime failure

Common gates:

```sh
hardproof ci --url "http://127.0.0.1:3000/mcp" --min-score 80 --min-dimension conformance=85 --max-critical 0
hardproof ci --url "http://127.0.0.1:3000/mcp" --max-tool-catalog-tokens 2000 --max-response-p95-tokens 2000
hardproof ci --url "http://127.0.0.1:3000/mcp" --allow-partial-score --max-tool-count 50
hardproof ci --url "http://127.0.0.1:3000/mcp" --max-avg-tool-description-tokens 500 --max-tool-count 50 --max-metadata-to-payload-ratio-pct 500
```

`hardproof ci` fails on `score_mode=partial` by default. Use `--allow-partial-score` only when you want threshold checks to accept a partial result.
