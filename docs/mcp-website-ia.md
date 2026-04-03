# MCP website IA + message hierarchy

Information architecture and messaging hierarchy for the MCP wedge pages.

## Route list (frozen)

- `/hardproof` — Verifier landing page.
- `/hardproof/install` — Install `hardproof` and run `doctor`.
- `/hardproof/ci` — CI integration preview (GitHub Action surface).
- `/hardproof/faq` — Compatibility and migration notes.
- `/mcp` — x07-native MCP authoring path.
- `/mcp/codespaces` — Zero-install evaluation path (Codespaces).

## Message hierarchy (frozen)

### `/hardproof`

- Headline: Ship MCP servers you can verify.
- Subhead: `hardproof` is a standalone verifier that runs deterministic checks and emits machine-readable evidence (any language).
- CTA 1: Install
- CTA 2: Use in CI
- CTA 3: FAQ / migration

### `/hardproof/install`

- Headline: Install `hardproof`
- Subhead: Prebuilt binaries; conformance runs inside `hardproof` with no external toolchain.
- CTA 1: Download latest alpha release
- CTA 2: Run `hardproof doctor`
- CTA 3: Run `hardproof scan`

### `/hardproof/ci`

- Headline: Run MCP conformance in CI
- Subhead: GitHub Action wrapper around `hardproof scan` outputs.
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
- No “State of MCP quality” report page yet.
- No aggressive comparison pages vs other MCP SDKs.

## Feedback destination

File issues in `x07lang/hardproof` with label `feedback`.
