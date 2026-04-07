# Changelog

## Unreleased

## v0.4.0-beta.1

- Complete the remaining M2.5b.1 beta gaps: spec-aligned trust reason codes, scan-side usage threshold flags, and branded report boundary types.
- Deepen the scan coverage with score-truth regressions, security subfamily fixtures, usage duplication findings, and p99 performance metrics.
- Tighten score semantics so full scores require Trust plus at least 85% weighted coverage, while partial scores render as withheld in rich output.
- Make `hardproof ci` fail on partial scores by default and add `--allow-partial-score` for explicit opt-in.
- Add example-artifact maintenance checks and a reproducible `make refresh-example-artifacts` path for the public docs bundle.
- Refresh release-facing docs, examples, fixtures, and embedded tool-version strings for `0.4.0-beta.1`.

## v0.4.0-beta.0

- Upgrade the scan report contract to `x07.mcp.scan.report@0.4.0` / `x07.mcp.scan.usage@0.4.0`.
- Make score truth explicit with `overall_score`, `partial_score`, `score_truth_status`, `dimension_coverage`, `unknown_dimensions`, `partial_reasons`, and `gating_reasons`.
- Add `--require-trust-for-full-score` to `hardproof scan` and `hardproof ci`.
- Add CI usage thresholds for `--max-avg-tool-description-tokens`, `--max-tool-count`, and `--max-metadata-to-payload-ratio-pct`.
- Update rich/compact rendering and public docs to explain partial versus publishable scores.

## v0.3.0-beta.0

- Add `hardproof scan` v0.3 report contract (`x07.mcp.scan.*@0.3.0`) with five deterministic dimensions plus usage overlay.
- Add rich/compact/json/jsonl scan output modes and a stable `scan.events.jsonl` event stream.
- Add `hardproof ci` gating on overall score/status, per-dimension thresholds, severity counts, and usage/token thresholds.
- Add `hardproof explain` and `hardproof report` (summary/html/sarif) for scan reports.
- Add `score_core/` certified score kernel with PBT + `x07 trust certify` in CI.

## v0.2.0-beta.1

- Implement `hardproof ci` threshold gating based on conformance score (passed/total).
- Update GitHub Action to run `hardproof ci` and add `threshold` input (default `"80"`).
- Update `install.sh` to resolve `latest-beta`.
- Update release workflow to build beta tags.
- Bump embedded tool version strings to `0.2.0-beta.1`.

## v0.1.0-alpha.9

- Fix GitHub Action to call `hardproof` without the unsupported `--sarif` flag.
- Bump embedded tool version strings to `0.1.0-alpha.9`.

## v0.1.0-alpha.8

- Fix release packaging to emit `hardproof_<version>_<os>_<arch>.tar.gz` deterministically on all supported runners.
- Update `install.sh` to resolve the correct platform artifact from GitHub Release assets (supports both legacy and current archive naming).
- Remove the legacy compatibility alias surface from the install flow and CI smoke.

## v0.1.0-alpha.6

- Rename release archives to `hardproof_<version>_<os>_<arch>.tar.gz`.
- Add `hardproof-scan` as the preferred GitHub Action path (legacy `action/` path remains available during beta).
- Normalize Action outputs (`scan_ok`, `report_json`, `report_junit`, `report_html`, `report_sarif`) with compatibility aliases.

## v0.1.0-alpha.5

- Rebrand public CLI to `hardproof` (docs, installer, Action, and release artifacts).
- Add public hero commands: `hardproof scan` and `hardproof ci`.
- Implement proof machinery: stdio conformance + replay, corpus runner outputs, and SARIF export.

## v0.1.0-alpha.4

- Implement verifier commands: `conformance run`, `replay record`, `replay verify`, `trust verify`, `bundle verify`.
- Add schema-versioned JSON outputs under `schemas/` with CI fixture validation.
- Add fixture coverage for replay/trust/bundle verification.
- Publish Linux/macOS alpha binaries plus `checksums.txt` and `install.sh`.
- Add alpha GitHub Action to run `conformance run` using release binaries.
- Add action smoke workflow against the `good-http` fixture target.
