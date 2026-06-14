# Corpus runner

The corpus runner exists to make the public quality report reproducible:

- a checked-in manifest defines **what** was tested and under which assumptions
- `hardproof corpus run` executes the **full five-dimension scan** per target and emits per-target outputs plus an aggregate `index.json` carrying every target's dimension scores and the corpus-wide dimension averages

## Manifest

- Schema: `schemas/x07.mcp.report.manifest.schema.json` (`x07.mcp.report.manifest@0.1.0`)
- Example: `corpus/manifests/quality-report-001.json`

Each `targets[]` entry captures:

- `id`: stable server id used in output paths
- `source`: repo/version (and optional commit/registry id) for reproducibility
- `target`: transport + reference (`streamable_http` URL or `stdio` command)
- `assumptions`: auth mode notes for fair testing
- `exclusions`: explicit skipped scenarios

## `corpus run` outputs

`hardproof corpus run --manifest <FILE> --out <DIR>` writes:

- `<DIR>` may be relative or absolute.
- `<DIR>/index.json` (`x07.mcp.corpus.summary@0.3.0`) — per-target `scores` (conformance/security/performance/trust/reliability/overall), `score_truth_status`, `counts`, corpus-wide `dimension_averages`, and `tool_shadowing` (`collision_count` + the tool names appearing in more than one target's catalog — a cross-server shadowing risk if those servers are wired into one agent)
- `<DIR>/<server_id>/result.json` (`x07.mcp.corpus.result@0.2.0`) — the target's dimension `scores` plus pointers to its scan outputs
- `<DIR>/<server_id>/scan.json` (`x07.mcp.scan.report@0.4.0`) — the full scan report for the target
- `<DIR>/<server_id>/tools.pin.json` (`hardproof.tools.pin@0.1.0`) — the tool-catalog pin for rug-pull tracking
- `<DIR>/<server_id>/conformance.summary.{json,junit.xml,html,sarif.json}` and the other dimension artifacts referenced from `scan.json.artifacts[]`

## `corpus render` outputs

`hardproof corpus render --input <DIR>/index.json --out <DIR>` writes:

- `<DIR>/report.html` (corpus index with links to per-target artifacts)

## Exclusions

`exclusions.skip_scenarios` is advisory metadata recorded in the manifest; the full scan does not yet apply per-scenario skips.

## Exit codes

- `0` every target produced a score (`score_available`)
- `1` one or more targets could not be scored
- `2` invocation/config/runtime precondition failure

## Manifests

- `corpus/manifests/quality-report-001.json` — hermetic CI smoke manifest using the local `good-http` fixture. The `Corpus` GitHub workflow (`.github/workflows/corpus.yml`) runs this on a weekly schedule (and on demand) via `scripts/ci/generate_corpus_sample.sh`, producing the full five-dimension dataset (`index.json` @0.2.0 + per-target scans + rendered report) as a build artifact. Deterministic; no network.
- `corpus/manifests/public-servers-001.json` — the curated public-benchmark target list of popular reference MCP servers (stdio/npx). It is **not** run by CI because it fetches third-party packages over the network and is non-deterministic. Generate the public dataset manually:

  ```bash
  hardproof corpus run --manifest corpus/manifests/public-servers-001.json --out out/public
  hardproof corpus render --input out/public/index.json --out out/public
  ```

Current schema-scoped `@0.2.0` samples live in `fixtures/reports/corpus.summary.sample.json` and `corpus.result.sample.json`. The `release_qa/external_smoke_matrix/0.4.0-beta.2/corpus/` tree is a historical snapshot at the superseded `@0.1.0` (conformance-only) schema and is retained only as a release record.

## Notes

- Wiring the rendered corpus into a public `/hardproof/quality-report` web page lives in the `x07-website` repo and is intentionally out of scope for this repo.
