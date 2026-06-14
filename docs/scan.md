# Scan (v0.4)

`hardproof scan` is the primary orchestrator command. It runs five deterministic dimensions (Conformance, Security, Performance, Trust, Reliability) plus a first-class usage/token overlay and emits a stable `x07.mcp.scan.report@0.4.0` report.

## Quickstart

```sh
hardproof scan --url "http://127.0.0.1:3000/mcp" --allow-private-targets --out out/scan
hardproof report summary --input out/scan/scan.json --ui rich
hardproof ci --url "http://127.0.0.1:3000/mcp" --allow-private-targets --min-score 80 --max-critical 0
```

By default, `--url` rejects localhost and private IP targets. Use `--allow-private-targets` for local dev URLs.

For stdio targets, prefer `--cmd-argv` to avoid invoking a shell:

```sh
hardproof scan --cmd-argv '["npx","-y","@modelcontextprotocol/server-github"]' --transport stdio --out out/scan
```

## Scoring

Hardproof aggregates the five dimensions with fixed weights:

- Conformance: 30%
- Security: 20%
- Performance: 15%
- Trust: 20%
- Reliability: 15%

`overall_score` is the weighted effective score. The rich/TUI view presents this weighted result as the **AI Infrastructure Score**, alongside a `Score Truth` badge reflecting `score_truth_status` (below).

Every dimension is scored by deterministic rules and measurements — there is no LLM-as-judge anywhere — so a score is reproducible and auditable.

Hardproof distinguishes three score-truth states (`score_truth_status`):

- **full** (`publishable`): all four core dimensions present and weighted coverage ≥ 85%; `overall_score` is populated and publishable.
- **partial**: some dimensions could be scored; `overall_score` is still computed as the effective score (matching `partial_score`), with `partial_reasons` / `gating_reasons` explaining why it is not publishable.
- **insufficient**: no dimensions could be evaluated (weighted coverage 0%, e.g. the target was unreachable); no numeric score is published and the rich UI renders `INSUFFICIENT SCORE`.

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
- `--score-preview` stays provisional until a full score is available. Partial runs still stream preview events with a numeric effective `overall_score` (matching `partial_score`) and `score_available=true` (including when `--require-trust-for-full-score` is set).
- `--metrics <STR>`: request extra metric payloads in `scan.events.jsonl` (example: `usage,perf`).
- `--perf-profile <STR>`: set the workload profile for the Performance dimension (`smoke|steady_small|concurrent_small`).
- `--max-avg-tool-description-tokens <INT>`: attach a usage-policy preview threshold to the scan invocation.
- `--max-tool-count <INT>`: attach a usage-policy preview threshold to the scan invocation.
- `--require-trust-for-full-score`: require trust evidence before reporting a full overall score.
- `--server-json <PATH>` / `--mcpb <PATH>`: enable deeper Trust checks by providing registry artifacts.
- `--event-log <PATH>`: override the default `scan.events.jsonl` path.
- `--render-interval-ms <INT>`: live render cadence for debugging/profiling.

`hardproof scan` accepts the usage-policy threshold flags so the same invocation surface is available in local triage. Enforcement still happens in `hardproof ci`.

Partial scans are explicit in `v0.4.0`: `score_mode=partial`, `score_truth_status=partial`, and `partial_reasons` / `gating_reasons` explain why the scan is not eligible for a publishable score. `overall_score` is still computed as the effective score (matching `partial_score`).

## Probe timeouts

Each probe spawns the target (stdio) or issues an HTTP request with a bounded timeout, so a hung server cannot block a probe forever. The defaults are 20s per stdio process and 30s per HTTP read.

`HARDPROOF_PROBE_TIMEOUT_MS` overrides both, in milliseconds, for the whole scan:

```bash
HARDPROOF_PROBE_TIMEOUT_MS=5000 hardproof scan --cmd "npx -y some-mcp-server"
```

A server that passes discovery but then hangs on later dimension probes would otherwise incur one timeout per probe; lowering this bounds the worst-case scan time (for example, CI can set a few seconds to fail fast). The timeout governs only how long a hang waits — it never changes scores for a healthy server, so scans stay deterministic. The HTTP read timeout is derived as `ms / 1000` seconds (integer floor, minimum 1s).

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

- `--usage-mode exact` uses `--tokenizer` (default: `openai:o200k_base`).
- `--usage-mode observed` requires `--token-trace`.
- `--usage-mode auto` selects the best available truth source (tokenizer and/or trace), otherwise falls back to `estimate`.
- When `--usage-mode exact` is explicitly requested and exact accounting cannot be produced, the scan fails non-zero instead of emitting ambiguous zero-ish metrics.
- `scan.json.usage_metrics` records `requested_usage_mode`, `usage_status` (`ok|fallback|error`), `usage_error_code`, and `usage_fallback_reason`.
- Hardproof locates tokenizer tables in this order:
  - `HARDPROOF_TOKENIZERS_DIR`
  - `$XDG_DATA_HOME/hardproof/tokenizers` (fallback: `~/.local/share/hardproof/tokenizers`)
  - `<hardproof_exe_dir>/tokenizers` (release archives ship tables next to the binary)
  - `./tokenizers` (fallback)

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
- `tools.pin.json` (`hardproof.tools.pin@0.1.0`): content-addressed pin of the tool catalog for rug-pull detection (pass back via `--tool-baseline`)
- `attestation.json` (`hardproof.attestation@0.2.0`): SHA-256 digests of `scan.json` and `scan.events.jsonl` plus a `record_hash` self-hash (and a `prev_hash` link + optional HMAC `signature`); verify with `hardproof attest verify --attestation <DIR>/attestation.json --out-dir <DIR>` (add `--attest-key`/`--attest-ledger` to also check the signature/hash-chain)
- `scan.failed.json` (`hardproof.scan.failed@0.1.0`): written **only** when a run reaches target resolution but cannot produce `scan.json` (conflicting target flags, or an I/O fault mid-scan); carries `status`, `error_code`, and `reason`. Guarantees that no such invocation exits without a structured artifact. Never written alongside a `scan.json`.
- `conformance.summary.*` artifacts when the conformance dimension runs
- `perf.samples.json` when the performance dimension runs (referenced via `scan.json.artifacts[]`)
- `trust/server.observed.json` when Hardproof performs `initialize` for `--url` auto-discovery and the server returns `serverInfo` (self-reported identity snapshot)
- `trust/server.json` when Hardproof resolves an MCP `server.json` manifest during auto-discovery (prefers `/.well-known/mcp.json`, with registry fallback)
- other referenced artifacts as the scan grows (pinned in `scan.json.artifacts[]`)

Auto-discovery is best-effort and only runs when `--server-json` is not supplied.

## Event stream (`scan.events.jsonl`)

The event stream is intended for CI log streaming and future TUI/integrations.

Current event types include:

- `scan.started`
- `scan.stage.started` / `scan.stage.finished`
- `scan.dimension.started` / `scan.dimension.finished`
- `scan.check.started` / `scan.check.finished`
- `scan.finding.emitted`
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
hardproof ci --url "http://127.0.0.1:3000/mcp" --allow-private-targets --min-score 80 --min-dimension conformance=85 --max-critical 0
hardproof ci --url "http://127.0.0.1:3000/mcp" --allow-private-targets --max-tool-catalog-tokens 2000 --max-response-p95-tokens 2000
hardproof ci --url "http://127.0.0.1:3000/mcp" --allow-private-targets --allow-partial-score --max-tool-count 50
hardproof ci --url "http://127.0.0.1:3000/mcp" --allow-private-targets --max-avg-tool-description-tokens 500 --max-tool-count 50 --max-metadata-to-payload-ratio-pct 500
```

`hardproof ci` fails on `score_mode=partial` by default. Use `--allow-partial-score` only when you want threshold checks to accept a partial result.
