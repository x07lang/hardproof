# Hardproof

Deterministic verification for MCP servers.

Hardproof is a standalone verifier for MCP servers. It scans running servers and release artifacts, produces machine-readable evidence, and gives you a clear path for local triage, CI gating, and release review. It is built with X07, but you do not need X07 to use it.

**Start here:** [Install](#install) · [Scan docs](docs/scan.md) · [Doctor docs](docs/doctor.md) · [Example report (partial)](docs/examples/hardproof-scan/README.md) · [Example report (full)](docs/examples/hardproof-scan-full/README.md) · [GitHub Action](action/README.md)

## What Hardproof Checks

Hardproof evaluates five deterministic dimensions plus a usage overlay:

- conformance
- security
- performance
- reliability
- trust
- usage metrics

A normal scan writes `scan.json`, `scan.events.jsonl`, and optional rendered reports such as HTML and SARIF.

## Score Semantics

Hardproof distinguishes between a full score and a partial score.

- **Full score:** `score_mode` is `full`, `overall_score` is populated, and `score_truth_status` is `publishable`.
- **Partial score:** `score_mode` is `partial`, `score_truth_status` is `partial`, and `overall_score` is still computed as the effective score (matching `partial_score`).

Hardproof uses `score_truth_status` to distinguish publishable (“full”) scores from partial ones. To make Trust publishable, provide `--server-json` and, when available, `--mcpb`. If you need strict withholding, pass `--require-trust-for-full-score` (the scan remains `score_truth_status=partial` until Trust evidence is present). `hardproof ci` fails on `score_mode=partial` by default; use `--allow-partial-score` only when partial gating is intentional.

## Install

Release artifacts are published from tags such as `v0.4.0-beta.8`.

### Install script

Each beta release publishes an installer script that downloads the correct archive, verifies it via `checksums.txt`, and installs `hardproof` to `~/.local/bin`:

```bash
curl -fsSL "https://github.com/x07lang/hardproof/releases/download/v0.4.0-beta.8/install.sh" \
  | bash -s -- --tag "v0.4.0-beta.8"
```

To resolve the latest beta tag automatically:

```bash
curl -fsSL "https://github.com/x07lang/hardproof/releases/download/v0.4.0-beta.8/install.sh" \
  | bash -s -- --tag latest-beta
```

Windows is supported through WSL2. Use the `linux_x86_64` release artifact inside WSL.

### Manual install

1. Download `hardproof_<VERSION>_<linux_x86_64|macos_arm64|macos_x86_64>.tar.gz` and `checksums.txt` from GitHub Releases.
2. Verify the SHA-256 digest.
3. Extract the archive and place `hardproof` on your `PATH`.

## Fastest First Success

Run diagnostics first:

```bash
hardproof doctor
hardproof doctor --machine json
```

Then scan an MCP endpoint:

```bash
hardproof scan \
  --url "http://127.0.0.1:3000/mcp" \
  --allow-private-targets \
  --out out/scan \
  --format rich
```

For an alternate-screen live UI:

```bash
hardproof scan --url "http://127.0.0.1:3000/mcp" --allow-private-targets --out out/scan --ui tui
```

Review the result:

```bash
hardproof report summary --input out/scan/scan.json --ui rich
```

## Common Workflows

### Local triage

```bash
hardproof scan --url "http://127.0.0.1:3000/mcp" --allow-private-targets --out out/scan --format rich
hardproof report html --input out/scan/scan.json > out/scan/report.html
hardproof report sarif --input out/scan/scan.json > out/scan/report.sarif.json
```

### CI gating

```bash
hardproof ci \
  --url "http://127.0.0.1:3000/mcp" \
  --allow-private-targets \
  --min-score 80 \
  --min-dimension conformance=85 \
  --max-critical 0
```

Usage-budget gates are available too:

```bash
hardproof ci \
  --url "http://127.0.0.1:3000/mcp" \
  --allow-private-targets \
  --max-avg-tool-description-tokens 500 \
  --max-tool-count 50 \
  --max-metadata-to-payload-ratio-pct 500
```

### Token truth (usage metrics)

Hardproof labels token metrics by truth class:

- `estimate`: deterministic estimates
- `tokenizer_exact`: exact counts under a chosen tokenizer profile
- `trace_observed`: observed counts from a real client trace
- `mixed`: per-metric mix of exact + observed

Examples:

```bash
hardproof scan --url "http://127.0.0.1:3000/mcp" --allow-private-targets --out out/scan --usage-mode estimate
hardproof scan --url "http://127.0.0.1:3000/mcp" --allow-private-targets --out out/scan --usage-mode exact --tokenizer openai:o200k_base
hardproof scan --url "http://127.0.0.1:3000/mcp" --allow-private-targets --out out/scan --usage-mode observed --token-trace trace.json
```

Notes:

- `--usage-mode exact` is strict: if exact accounting cannot be produced, the scan fails non-zero instead of emitting ambiguous zero-ish metrics.
- `scan.json.usage_metrics` records `requested_usage_mode`, `usage_status` (`ok|fallback|error`), `usage_error_code`, and `usage_fallback_reason`.

Tokenizer tables are resolved in this order:

- `HARDPROOF_TOKENIZERS_DIR`
- `$XDG_DATA_HOME/hardproof/tokenizers` (fallback: `~/.local/share/hardproof/tokenizers`)
- `<hardproof_exe_dir>/tokenizers` (release archives ship tables next to the binary)
- `./tokenizers` (fallback)

### Explain findings and render reports

```bash
hardproof explain <FINDING_CODE>
hardproof report summary --input out/scan/scan.json --ui compact
hardproof report html --input out/scan/scan.json > out/scan/report.html
hardproof report sarif --input out/scan/scan.json > out/scan/report.sarif.json
```

### Replay, trust, and bundle verification

```bash
hardproof replay record --url "http://127.0.0.1:3000/mcp" --allow-private-targets --out out/replay.session.json --scenario smoke/basic
hardproof replay verify --session out/replay.session.json --url "http://127.0.0.1:3000/mcp" --allow-private-targets --out out/replay-verify
hardproof trust verify --server-json server.json
hardproof bundle verify --server-json server.json --mcpb server.mcpb
```

### GitHub Action

```yaml
- name: Run Hardproof scan
  uses: x07lang/hardproof/hardproof-scan@v0.4.0-beta.8
  with:
    url: http://127.0.0.1:3000/mcp
    allow-private-targets: "true"
```

## Outputs

`hardproof scan --out <DIR>` writes:

- `scan.json` with schema `x07.mcp.scan.report@0.4.0`
- `scan.events.jsonl` with the structured event stream
- conformance artifacts when the conformance dimension runs
- additional dimension-specific artifacts referenced from `scan.json.artifacts[]`

Exit codes:

- `0`: overall scan status is `pass` or `warn`
- `1`: overall scan status is `fail`
- `2`: invocation, configuration, or runtime precondition failure

## Schemas

The report contract is versioned and pinned for consumers. The main schema line is:

- `x07.mcp.scan.report@0.4.0`

Related stable schemas include:

- `x07.mcp.scan.dimension@0.3.0`
- `x07.mcp.scan.finding@0.3.0`
- `x07.mcp.scan.metrics@0.3.0`
- `x07.mcp.scan.usage@0.4.0`
- `x07.mcp.conformance.summary@0.2.0`
- `x07.mcp.replay.session@0.2.0`
- `x07.mcp.replay.verify@0.2.0`
- `x07.mcp.trust.summary@0.2.0`
- `x07.mcp.bundle.verify@0.2.0`
- `x07.mcp.sarif@0.1.0`

See [`docs/schema-versioning.md`](docs/schema-versioning.md) for the full list and versioning policy.

## Docs And Examples

- [`docs/doctor.md`](docs/doctor.md) for environment checks and target diagnosis
- [`docs/scan.md`](docs/scan.md) for scan behavior and report structure
- [`docs/targets.md`](docs/targets.md) for HTTP and stdio target configuration
- [`docs/examples/hardproof-scan/README.md`](docs/examples/hardproof-scan/README.md) for a concrete report example
- [`fixtures/reports/README.md`](fixtures/reports/README.md) for the JSON fixture corpus (full report samples vs schema-scoped samples)
- [`action/README.md`](action/README.md) and [`hardproof-scan/README.md`](hardproof-scan/README.md) for GitHub Action usage
- `corpus/README.md` for corpus-driven report generation

Refresh the checked-in example bundle with:

```bash
make refresh-example-artifacts
```

## Development

Local `./scripts/ci/check_all.sh` requires the pinned X07 toolchain plus formal verification tools for the proof and certification lanes:

- macOS: `brew install cbmc z3`
- Linux: `./scripts/ci/install_formal_verification_tools_linux.sh`

## Known Limitations

- Windows support is through WSL2.
- Some stdio target flows are still being stabilized; use the checked-in stdio fixtures as the reference shape.
- Stdio targets use a smoke performance score from a single initialize+ping probe; tool-call and concurrency sampling stay HTTP-only because repeated cold starts distort the signal.

## Feedback

File issues in `x07lang/hardproof` using the repo issue templates.
