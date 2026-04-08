# External smoke matrix (release QA)

This directory holds **release QA evidence** for running Hardproof against real (non-fixture) targets.

Goal: before a proof push, record at least:

- one stdio target smoke
- one HTTP target smoke
- one trust-evaluable target smoke (scan with `--server-json` + `--mcpb`)
- one corpus/public-sample flow smoke (`hardproof corpus run` + `hardproof corpus render`)

## Run

From the `hardproof/` repo root (in the multi-repo `x07lang/` workspace):

```sh
./scripts/release_qa/run_external_smoke_matrix.sh
```

Inputs:

- `X07_MCP_ROOT` (optional): path to an `x07lang/x07-mcp` checkout (defaults to `../x07-mcp`).
- `HARDPROOF_BIN` (optional): use an existing Hardproof binary instead of building one.

## Outputs

Each run overwrites:

- `release_qa/external_smoke_matrix/<hardproof_version>/`

That directory contains:

- `command.log`: full command transcript
- `meta.json`: tool versions + git commits
- per-target evidence directories (`scan/` outputs, trust/bundle/replay artifacts)

