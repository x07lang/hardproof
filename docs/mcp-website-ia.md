# MCP website IA + message hierarchy

Information architecture and messaging hierarchy for the MCP wedge pages.
Messaging refreshed for `v0.4` — hardproof is a five-dimension verifier, not a conformance-only checker.

## Route list

- `/hardproof` — Verifier landing page.
- `/hardproof/install` — Install `hardproof` and run `doctor`.
- `/hardproof/ci` — CI integration (GitHub Action surface).
- `/hardproof/faq` — Compatibility and migration notes.
- `/mcp` — x07-native MCP authoring path.
- `/mcp/codespaces` — Zero-install evaluation path (Codespaces).

## What hardproof is (message pillars)

Carry these consistently across the `/hardproof` pages:

- **Five deterministic dimensions + a usage overlay** — conformance, security, performance, trust, reliability. The weighted result is presented as the **AI Infrastructure Score**.
- **Deterministic, not LLM-as-judge** — every dimension is scored by fixed rules and measurements, so a score is reproducible and auditable. The core score arithmetic is a formally verified kernel; the rules and weights are tested.
- **Score truth is explicit** — `full` / `partial` / `insufficient`; partial and insufficient states are surfaced honestly rather than published as a confident number.
- **Machine-readable evidence** — `scan.json`, SARIF, and a tamper-evident `attestation.json` (verifiable with `hardproof attest verify`).
- **Standalone, any language** — verifies any MCP server over stdio or Streamable HTTP; no x07 toolchain required to run it.
- **Differentiators** — rug-pull / tool-definition drift detection (pin the tool catalog, diff on later scans via `--tool-baseline`) and tamper-evident scan attestation.

## Message hierarchy

### `/hardproof`

- Headline: Ship MCP servers you can verify.
- Subhead: `hardproof` is a standalone verifier that scores MCP servers across five deterministic dimensions (no LLM-as-judge) and emits machine-readable, reproducible evidence — any language.
- CTA 1: Install
- CTA 2: Use in CI
- CTA 3: FAQ / migration

### `/hardproof/install`

- Headline: Install `hardproof`
- Subhead: Prebuilt binaries; the full scan (all five dimensions) runs inside `hardproof` with no external toolchain.
- CTA 1: Download latest beta release
- CTA 2: Run `hardproof doctor`
- CTA 3: Run `hardproof scan`

### `/hardproof/ci`

- Headline: Gate MCP quality in CI
- Subhead: A GitHub Action wrapper around `hardproof scan` / `hardproof ci` — fail the build on score, dimension, or finding thresholds, with SARIF for code scanning.
- CTA 1: See the Action YAML snippet
- CTA 2: View sample report artifacts
- CTA 3: Open an issue for early access

### `/mcp/codespaces`

- Headline: Try MCP verification with zero install
- Subhead: Codespaces is the default “first success” path for the x07-native authoring toolkit.
- CTA 1: Open the Codespace
- CTA 2: Run the quickstart
- CTA 3: Leave feedback

## Explicitly out of scope (for now)

- No x07 homepage rewrite.
- No public “State of MCP quality” report page yet. (The `corpus run` engine now produces the underlying full five-dimension data, but the render→website pipeline and scheduled runs are not wired — see roadmap P2-13.)
- No aggressive comparison pages vs other MCP SDKs.

## Feedback destination

File issues in `x07lang/hardproof` with label `feedback`.
