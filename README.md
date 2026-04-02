# x07-mcp-test

Private-alpha MCP verifier CLI (Track A wedge): run official MCP conformance plus replay/trust/bundle checks, and emit reviewable artifacts (terminal + JSON + JUnit + HTML).

## Who it's for

- MCP server developers (any language) who want CI-grade verification evidence.
- Maintainers who want deterministic repro (replay) and reviewable metadata checks (trust/bundle).

## Fastest first success

1) Install `x07-mcp-test` (alpha).

2) Run diagnostics:

```sh
x07-mcp-test doctor
x07-mcp-test doctor --machine json
```

3) Run official conformance:

```sh
x07-mcp-test conformance run \
  --url "http://127.0.0.1:3000/mcp" \
  --out out/conformance \
  --machine json
```

## Usage

- `x07-mcp-test --help`
- `x07-mcp-test doctor`
- `x07-mcp-test doctor --machine json --cmd "<stdio cmd>" --url "<http url>"`
- `x07-mcp-test conformance run --url "<http url>"`
- `x07-mcp-test conformance run --cmd "<stdio cmd>" --cwd "<dir>" --env-file "<file>"`
- `x07-mcp-test conformance run --url "<http url>" --out out/`
- `x07-mcp-test conformance run --url "<http url>" --full-suite`
- `x07-mcp-test replay record --url "<http url>" --out out/replay.session.json --scenario smoke/basic`
- `x07-mcp-test replay record --cmd "<stdio cmd>" --out out/replay.session.json`
- `x07-mcp-test replay verify --session out/replay.session.json --url "<http url>" --out out/replay-verify`
- `x07-mcp-test replay verify --session out/replay.session.json --cmd "<stdio cmd>" --out out/replay-verify`
- `x07-mcp-test trust verify --server-json "<path>"`
- `x07-mcp-test bundle verify --server-json "<path>" --mcpb "<path>"`
- `x07-mcp-test corpus run --manifest corpus/manifests/quality-report-001.json --out out/corpus/quality-report-001`

See `docs/doctor.md`.
See `docs/targets.md`.
See `corpus/README.md`.

## Install (alpha)

Release artifacts are built via GitHub Actions on tags like `v0.1.*-alpha*`.

On Windows, run inside WSL2 and use the `linux-x64` artifact.

### Install script

Each alpha release publishes an installer script (`install.sh`) that downloads the right archive for your OS/arch, verifies it via `checksums.txt`, and installs `x07-mcp-test` to `~/.local/bin`:

```sh
curl -fsSL "https://github.com/x07lang/x07-mcp-test/releases/download/v0.1.0-alpha.4/install.sh" \
  | bash -s -- --tag "v0.1.0-alpha.4"
```

You can also resolve the latest alpha tag (requires GitHub API access):

```sh
curl -fsSL "https://github.com/x07lang/x07-mcp-test/releases/download/v0.1.0-alpha.4/install.sh" \
  | bash -s -- --tag latest-alpha
```

### Manual install

1) Download `x07-mcp-test-<TAG>-<linux-x64|darwin-arm64|darwin-x64>.tar.gz` and `checksums.txt` from GitHub Releases.

2) Verify `sha256`, extract, and place `x07-mcp-test` on your `PATH`.

## Schemas

Report schemas and shared envelope fields are versioned and pinned for consumers:

- `x07.mcp.conformance.summary@0.2.0` (`schemas/x07.mcp.conformance.summary.schema.json`)
- `x07.mcp.replay.session@0.2.0` (`schemas/x07.mcp.replay.session.schema.json`)
- `x07.mcp.replay.verify@0.2.0` (`schemas/x07.mcp.replay.verify.schema.json`)
- `x07.mcp.trust.summary@0.2.0` (`schemas/x07.mcp.trust.summary.schema.json`)
- `x07.mcp.bundle.verify@0.2.0` (`schemas/x07.mcp.bundle.verify.schema.json`)
- `x07.mcp.report.manifest@0.1.0` (`schemas/x07.mcp.report.manifest.schema.json`)
- `x07.mcp.corpus.result@0.1.0` (`schemas/x07.mcp.corpus.result.schema.json`)
- `x07.mcp.corpus.summary@0.1.0` (`schemas/x07.mcp.corpus.summary.schema.json`)
- `x07.mcp.sarif@0.1.0` (`schemas/x07.mcp.sarif.schema.json`)

Sample fixtures live under `fixtures/reports/` and validate in CI.

See `docs/schema-versioning.md`.

## Notes

- HTTP conformance runs the official MCP suite via `npx` (requires Node/npm/npx); use `x07-mcp-test doctor` to confirm preconditions.
- Stdio conformance runs via an internal harness that emits the same `checks.json` shape and IDs as the pinned official package, so reports stay comparable across transports.
- For now, `replay record` records the `smoke/basic` HTTP scenario and stores the cassette at `details.http_session` (schema `x07.mcp.rr.http_session@0.1.0`). See `rr/README.md`.
- Trust and bundle verification operate on registry artifacts (`server.json` and `.mcpb`) rather than a running HTTP server. See `trust/README.md`.
- Output paths should be **relative** (example: `out/...`). Absolute paths are rejected by the current filesystem capability model.

## Conformance outputs

`x07-mcp-test conformance run` writes:
- `summary.json` (schema: `x07.mcp.conformance.summary@0.2.0`)
- `summary.junit.xml`
- `summary.html`

Exit codes:
- `0` all required scenarios passed
- `1` one or more required scenarios failed
- `2` invocation/config/runtime precondition failure

## CI / GitHub Action contract

The Action downloads an `x07-mcp-test` release binary and runs `conformance run` (HTTP or stdio):

```yaml
- name: Run MCP conformance
  uses: x07lang/x07-mcp-test/action@v0.1.0-alpha.4
  with:
    url: http://127.0.0.1:3000/mcp
    full-suite: "false"
```

See `action/README.md`.

## Fixture targets

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
- `conformance/scripts/spawn_reference_stdio.sh good-stdio`

Stdio fixtures:
- `good-stdio`: `node stdio-hello/server.mjs`
- `broken-stdio`: `node stdio-broken/server.mjs`

## Known limitations (alpha)

- Windows support is via WSL2 (run inside a Linux distro and use `linux-x64`).
- HTTP conformance requires Node/npm/npx.
- Some stdio target flows are still being stabilized; use the stdio fixtures as the reference shape.

## Feedback

File issues in `x07lang/x07-mcp-test` using the issue templates (Alpha feedback / Bug report).
