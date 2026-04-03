# Changelog

## Unreleased

- (none yet)

## v0.1.0-alpha.6

- Rename release archives to `hardproof_<version>_<os>_<arch>.tar.gz` and include a `x07-mcp-test` compatibility binary in the archive.
- Add `hardproof-scan` as the preferred GitHub Action path (legacy `action/` path remains available during beta).
- Normalize Action outputs (`scan_ok`, `report_json`, `report_junit`, `report_html`, `report_sarif`) with compatibility aliases.

## v0.1.0-alpha.5

- Rebrand public CLI to `hardproof` (docs, installer, Action, and release artifacts).
- Add public hero commands: `hardproof scan` and `hardproof ci`.
- Implement Week 6 proof machinery: stdio conformance + replay, corpus runner outputs, and SARIF export.

## v0.1.0-alpha.4

- Implement verifier commands: `conformance run`, `replay record`, `replay verify`, `trust verify`, `bundle verify`.
- Add schema-versioned JSON outputs under `schemas/` with CI fixture validation.
- Add fixture coverage for replay/trust/bundle verification.
- Publish Linux/macOS alpha binaries plus `checksums.txt` and `install.sh`.
- Add alpha GitHub Action to run `conformance run` using release binaries.
- Add action smoke workflow against the `good-http` fixture target.
