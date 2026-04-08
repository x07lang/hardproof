# Report fixtures

This directory contains JSON fixtures used by:

- `hardproof ci validate-fixtures` (schema-shape validation)
- `scripts/ci/check_all.sh` (regression and consistency checks)

## Full scan report samples

Files that declare `schema_version: "x07.mcp.scan.report@…"` are full scan reports and must:

- include all five score dimensions (`conformance`, `security`, `performance`, `trust`, `reliability`)
- keep `status`, `overall_status`, `partial_score`, and related score fields internally consistent

CI enforces this with `python3 scripts/ci/assert_scan_report_consistency.py`.

## Schema-scoped samples

Other files in this directory are schema-scoped objects (for example a single finding, a single
dimension, usage metrics, corpus summaries, SARIF, replay sessions). They are validated by
`hardproof ci validate-fixtures` and are not expected to satisfy scan-report consistency rules.
