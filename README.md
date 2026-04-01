# x07-mcp-test

Private-alpha MCP verifier CLI (Track A wedge).

## Status

Week 2 scope is real `conformance run` behavior against fixtures + report exports.
Other commands are still stubs until later weeks.

## Usage

- `x07-mcp-test --help`
- `x07-mcp-test doctor`
- `x07-mcp-test doctor --machine json --cmd "<stdio cmd>" --url "<http url>"`
- `x07-mcp-test conformance run --url "<http url>"`
- `x07-mcp-test conformance run --url "<http url>" --out out/`
- `x07-mcp-test conformance run --url "<http url>" --full-suite`

See `docs/doctor.md`.

## Commands (M1 contract)

- `doctor`
- `conformance run`
- `replay record`
- `replay verify`
- `trust verify`
- `bundle verify`

## Install (alpha)

Release artifacts are built via GitHub Actions on tags like `v0.1.*-alpha*`.

On Windows, run inside WSL2 and use the `linux-x64` artifact.

## Schemas

Week 1 freezes report schema naming and the shared envelope fields:

- `x07.mcp.conformance.summary@0.1.0` (`schemas/x07.mcp.conformance.summary.schema.json`)
- `x07.mcp.replay.session@0.1.0` (`schemas/x07.mcp.replay.session.schema.json`)
- `x07.mcp.replay.verify@0.1.0` (`schemas/x07.mcp.replay.verify.schema.json`)
- `x07.mcp.trust.summary@0.1.0` (`schemas/x07.mcp.trust.summary.schema.json`)
- `x07.mcp.bundle.verify@0.1.0` (`schemas/x07.mcp.bundle.verify.schema.json`)

Sample fixtures live under `fixtures/reports/` and validate in CI.

## Conformance outputs

`x07-mcp-test conformance run` writes:
- `summary.json` (schema: `x07.mcp.conformance.summary@0.1.0`)
- `summary.junit.xml`
- `summary.html`

Exit codes:
- `0` all required scenarios passed
- `1` one or more required scenarios failed
- `2` invocation/config/runtime precondition failure

## Fixture targets (Week 2)

Local fixture servers live under `fixtures/servers/` and are wired via:
- `conformance/fixtures/targets.json`
- `conformance/scripts/spawn_reference_http.sh`
- `conformance/scripts/wait_for_http.sh`

Ports/URLs:
- `good-http`: `http://127.0.0.1:18080/mcp`
- `auth-http`: `http://127.0.0.1:18081/mcp`
- `broken-http`: `http://127.0.0.1:18082/mcp`

Start a fixture server:
- `conformance/scripts/spawn_reference_http.sh good-http noauth`
