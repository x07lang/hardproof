# Corpus runner

The corpus runner exists to make the public quality report reproducible:

- a checked-in manifest defines **what** was tested and under which assumptions
- `x07-mcp-test corpus run` executes conformance per target and emits per-target outputs plus an aggregate `index.json`

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

`x07-mcp-test corpus run --manifest <FILE> --out <DIR>` writes:

- `<DIR>/index.json` (`x07.mcp.corpus.summary@0.1.0`)
- `<DIR>/<server_id>/result.json` (`x07.mcp.corpus.result@0.1.0`)
- `<DIR>/<server_id>/summary.json` (`x07.mcp.conformance.summary@0.2.0`)
- `<DIR>/<server_id>/summary.junit.xml`
- `<DIR>/<server_id>/summary.html`
- `<DIR>/<server_id>/summary.sarif.json` (`x07.mcp.sarif@0.1.0`, stub until SARIF renderer ships)

## Exclusions

`exclusions.skip_scenarios` is recorded in the per-target `result.json` warnings as `corpus.exclusions.skip_scenarios` and is not applied to the conformance runner yet.

## Exit codes

- `0` all targets passed required scenarios
- `1` one or more targets failed conformance
- `2` invocation/config/runtime precondition failure

## Notes

- `corpus/manifests/quality-report-001.json` is a CI smoke manifest using local fixtures; replace targets before generating the public dataset.
