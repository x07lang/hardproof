# Hardproof

Deterministic verification for MCP servers.

Hardproof is a standalone verifier for MCP servers. It scans running servers and release artifacts, produces machine-readable evidence, and gives you a clear path for local triage, CI gating, and release review. It is built with X07, but you do not need X07 to use it.

**Start here:** [Install](#install) · [Scan docs](docs/scan.md) · [Doctor docs](docs/doctor.md) · [Example report (partial)](docs/examples/hardproof-scan/README.md) · [Example report (full)](docs/examples/hardproof-scan-full/README.md) · [GitHub Action](action/README.md)

## What Hardproof Checks

Hardproof evaluates five deterministic dimensions plus a usage overlay. Every dimension is scored by deterministic rules and measurements — there is no LLM-as-judge anywhere — so a score is reproducible and auditable. The core score arithmetic is a formally verified kernel (`score_core`); the per-dimension rules and weights are deterministic and covered by tests.

- conformance
- security
- performance
- trust
- reliability
- usage metrics

A normal scan writes `scan.json`, `scan.events.jsonl`, and optional rendered reports such as HTML and SARIF.

## Score Semantics

The weighted overall result is presented as the **AI Infrastructure Score** in the rich/TUI view, paired with a `Score Truth` badge (`full` / `partial` / `insufficient`). Hardproof distinguishes between a full score, a partial score, and an insufficient score.

- **Full score:** `score_mode` is `full`, `overall_score` is populated, and `score_truth_status` is `publishable` (all four core dimensions present and weighted coverage ≥ 85%).
- **Partial score:** `score_mode` is `partial`, `score_truth_status` is `partial`, and `overall_score` is still computed as the effective score (matching `partial_score`) whenever any dimensions could be scored.
- **Insufficient score:** when no dimensions could be evaluated (weighted coverage 0%, e.g. the target was unreachable), `score_truth_status` is `insufficient`, no numeric score is published, and the rich UI renders `INSUFFICIENT SCORE`.

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

### Probe timeouts

Each probe bounds its I/O so a hung server cannot block forever (defaults: 20s per stdio process, 30s per HTTP read). `HARDPROOF_PROBE_TIMEOUT_MS` overrides both (milliseconds, whole scan) — useful to fail fast in CI when a server passes discovery but hangs on later probes:

```bash
HARDPROOF_PROBE_TIMEOUT_MS=5000 hardproof scan --cmd "npx -y some-mcp-server"
```

The timeout governs only how long a hang waits; it never changes scores for a healthy server.

### Explain findings and render reports

```bash
hardproof explain <FINDING_CODE>
hardproof report summary --input out/scan/scan.json --ui compact
hardproof report html --input out/scan/scan.json > out/scan/report.html
hardproof report sarif --input out/scan/scan.json > out/scan/report.sarif.json
```

### Tool-definition pinning (rug-pull detection)

Every scan writes a deterministic, content-addressed pin of the server's tool catalog to `<out>/tools.pin.json` (a per-tool canonical SHA-256 plus a `catalog_hash`). Pin it once at approval time, then pass it back on later scans to detect a **rug pull** — a server that silently changes, adds, or removes tool definitions after you approved it:

```bash
# 1) approve: capture the baseline pin
hardproof scan --url "http://127.0.0.1:3000/mcp" --allow-private-targets --out out/approved
cp out/approved/tools.pin.json policy/server.tools.pin.json

# 2) monitor: fail if the tool catalog drifts from the pinned baseline
hardproof ci --url "http://127.0.0.1:3000/mcp" --allow-private-targets \
  --tool-baseline policy/server.tools.pin.json --max-critical 0
```

Drift emits per-tool findings — `SEC-TOOL-DEFINITION-DRIFT` (critical) when an existing tool's definition changed, and `SEC-TOOL-ADDED` / `SEC-TOOL-REMOVED` (warning) when tools appear or disappear — each carrying the affected tool name as evidence; a changed definition also lowers the Security score. Detection is fully deterministic (per-tool canonical JSON + SHA-256); an unchanged catalog never produces a false positive.

### Tamper-evident attestation

Every scan writes `<out>/attestation.json` (`hardproof.attestation@0.2.0`) that binds the scan's outputs by SHA-256: it records `report_digest`, `scan_json_sha256`, and `scan_events_jsonl_sha256` alongside the `run_id`, `tool_version`, and `methodology_version`. It also carries a `record_hash` — `sha256(run_id:report_digest:scan_json_sha256:scan_events_jsonl_sha256:prev_hash)` — that binds every field into one self-hash. `attest verify` recomputes the digests from the output directory and confirms the report and its event stream have not been altered since the scan ran:

```bash
hardproof scan --url "http://127.0.0.1:3000/mcp" --allow-private-targets --out out/scan
hardproof attest verify --attestation out/scan/attestation.json --out-dir out/scan
```

The verdict is deterministic. Exit `0` means intact; exit `1` means a mismatch (`--machine json` reports `scan_json_match` / `events_match` / `record_hash_match` so you can tell what changed); exit `2` means a missing or malformed attestation. This lets a downstream consumer — a registry, a CI gate, an auditor — trust a stored `scan.json` without re-running the scan.

**Hash-chained ledger.** Pass `--attest-ledger <file>` to maintain an append-only ledger of `record_hash`es across runs: each attestation's `prev_hash` links to the prior record, so altering any past run breaks the chain. Verify the chain head with `attest verify --attest-ledger <file>` (`chain_match`).

**Signing.** Pass `--attest-key <file>` (or set `HARDPROOF_ATTEST_KEY` to a key-file path) to add an HMAC-SHA256 `signature` (`signature_alg: "hmac-sha256"`) over the record's chain input. `attest verify --attest-key <file>` recomputes and checks it (`signature_match`); without a key the attestation is unsigned and `signature_match` is reported as `null`.

```bash
hardproof scan --cmd "npx -y some-mcp-server" --out out/scan \
  --attest-key /secrets/attest.key --attest-ledger out/attest.ledger
hardproof attest verify --attestation out/scan/attestation.json --out-dir out/scan \
  --attest-key /secrets/attest.key --attest-ledger out/attest.ledger
```

### Security screening

The Security dimension applies a deterministic, versioned screening ruleset (`security.metrics.ruleset_version`) over the tool catalog — no LLM-as-judge. Findings are screening **warnings**, each tagged with an OWASP MCP category in `evidence.owasp`:

- `SEC-INJECTION-PATTERN` (MCP: Prompt Injection) — imperative prompt-style instructions in tool metadata.
- `SEC-COMMAND-RISK-PATTERN` (MCP: Command Injection) — shell/command execution surfaces.
- `SEC-SECRET-EXPOSURE` (MCP: Sensitive Information Disclosure) — credential-like tokens. Structured tokens (GitHub `ghp_`/`github_pat_`, AWS `AKIA`, Slack `xox[bp]-`) are matched by **precise anchored regex** on the full token shape, so prose mentions of a prefix do not false-positive.
- `SEC-EXCESSIVE-AGENCY` (MCP: Excessive Agency) — tools that declare both `destructiveHint` and `openWorldHint`, combining irreversible effects with open-ended reach (`security.metrics.excessive_agency_tool_count`).
- `SEC-LETHAL-TRIFECTA` (MCP: Excessive Agency) — a **config-policy** check: the server's tool catalog spans all three lethal-trifecta legs — untrusted input (`fetch`/`browse`/…), private-data access (`secret`/`credential`/`filesystem`/…), and external communication (`send_email`/`webhook`/`upload`/…) — so a prompt injection in untrusted content could exfiltrate sensitive data. By the *Rule of Two*, at most two of these should co-occur within one trust boundary. The three capability flags are reported in `security.metrics.capability_untrusted_input` / `capability_private_data` / `capability_external_comms`, and `security.metrics.lethal_trifecta` is `1` when all three are present.

Regex matching is bounded to simple anchored patterns over the (bounded) tool metadata, so it stays linear and cannot be turned into a scan-time DoS by adversarial server content. The lethal-trifecta capability classifier is a deterministic keyword heuristic over tool names/descriptions; like the rest of the ruleset it is a screening signal, versioned via `security.metrics.ruleset_version`.

### Replay, trust, and bundle verification

```bash
hardproof replay record --url "http://127.0.0.1:3000/mcp" --allow-private-targets --out out/replay.session.json --scenario smoke/basic
hardproof replay verify --session out/replay.session.json --url "http://127.0.0.1:3000/mcp" --allow-private-targets --out out/replay-verify
hardproof trust verify --server-json server.json
hardproof bundle verify --server-json server.json --mcpb server.mcpb
```

### A2A agent-card verification (prototype)

`hardproof a2a verify --card agent-card.json` runs deterministic checks over an [A2A](https://a2a-protocol.org) Agent Card: required structure (`name`, `url`, `version`, `capabilities`, well-formed `skills`), the publisher identity claim (`provider.organization`), and signature **presence** (`signatures[]`).

```bash
hardproof a2a verify --card agent-card.json
hardproof a2a verify --machine json --card agent-card.json
```

Exit `0` means the card is structurally valid (`--machine json` reports per-field booleans plus `provider_present` and `signed`); exit `1` means required fields are missing/malformed; exit `2` means a missing or unreadable card. This is an early prototype — it validates structure, identity claims, and signature presence; full cryptographic JWS verification (resolving the signing JWK) is not yet performed.

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
- `tools.pin.json` (`hardproof.tools.pin@0.1.0`): a content-addressed pin of the tool catalog for rug-pull detection
- `attestation.json` (`hardproof.attestation@0.1.0`): SHA-256 digests of `scan.json` and `scan.events.jsonl` for tamper-evident verification via `attest verify`
- conformance artifacts when the conformance dimension runs
- additional dimension-specific artifacts referenced from `scan.json.artifacts[]`

When a run reaches target resolution but cannot produce `scan.json` (e.g. conflicting target flags, or an I/O fault mid-scan), Hardproof instead writes `scan.failed.json` (`hardproof.scan.failed@0.1.0`: `status`, `error_code`, `reason`) so no such invocation exits without a structured artifact.

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
- `x07.mcp.attestation@0.2.0`
- `x07.mcp.attest.verify@0.2.0`
- `x07.mcp.a2a.verify@0.1.0`
- `x07.mcp.scan.failed@0.1.0`
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
