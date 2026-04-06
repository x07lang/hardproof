# Hardproof

Deterministic verification for MCP servers.

Hardproof is a standalone verifier for MCP servers. It runs deterministic checks for conformance, replay, trust, and release-grade evidence. Hardproof is built with x07, but you do not need to adopt x07 to use it.

## Who it's for

- MCP server developers (any language) who want CI-grade verification evidence.
- Maintainers who want deterministic repro (replay) and reviewable metadata checks (trust/bundle).

## Fastest first success

1) Install `hardproof`.

2) Run diagnostics:

```sh
hardproof doctor
hardproof doctor --machine json
```

3) Run a scan (five deterministic dimensions + usage overlay):

```sh
hardproof scan \
  --url "http://127.0.0.1:3000/mcp" \
  --out out/scan \
  --format rich
```

## Usage

- `hardproof --help`
- `hardproof scan --url "<http url>" --out out/scan --format rich|compact|json|jsonl`
- `hardproof scan --url "<http url>" --out out/scan --format jsonl --score-preview`
- `hardproof scan --url "<http url>" --out out/scan --format jsonl --metrics usage,perf`
- `hardproof scan --url "<http url>" --server-json "<path>" --mcpb "<path>" --out out/scan`
- `hardproof scan --cmd "<stdio cmd>" --cwd "<dir>" --env-file "<file>" --out out/scan`
- `hardproof scan --url "<http url>" --full-suite --baseline conformance/pinned/conformance-baseline.yml`
- `hardproof ci --url "<http url>" --threshold 80`
- `hardproof ci --url "<http url>" --min-score 80 --min-dimension conformance=85 --max-critical 0`
- `hardproof ci --url "<http url>" --max-tool-catalog-tokens 2000 --max-response-p95-tokens 2000`
- `hardproof explain <FINDING_CODE>`
- `hardproof explain CONFORMANCE.FAIL`
- `hardproof explain CONFORMANCE.<check-id>`
- `hardproof report summary --input out/scan/scan.json --ui rich|compact`
- `hardproof report html --input out/scan/scan.json > out/scan/report.html`
- `hardproof report sarif --input out/scan/scan.json > out/scan/report.sarif.json`
- `hardproof doctor`
- `hardproof doctor --machine json --cmd "<stdio cmd>" --url "<http url>"`
- `hardproof conformance run --url "<http url>"`
- `hardproof replay record --url "<http url>" --out out/replay.session.json --scenario smoke/basic`
- `hardproof replay record --cmd "<stdio cmd>" --out out/replay.session.json`
- `hardproof replay verify --session out/replay.session.json --url "<http url>" --out out/replay-verify`
- `hardproof replay verify --session out/replay.session.json --cmd "<stdio cmd>" --out out/replay-verify`
- `hardproof trust verify --server-json "<path>"`
- `hardproof bundle verify --server-json "<path>" --mcpb "<path>"`
- `hardproof corpus run --manifest corpus/manifests/quality-report-001.json --out out/corpus/quality-report-001`
- `hardproof corpus render --input out/corpus/quality-report-001/index.json --out out/corpus/quality-report-001`

See `docs/doctor.md`.
See `docs/scan.md`.
See `docs/targets.md`.
See `corpus/README.md`.

For `--score-preview`, early JSONL preview events stay provisional until at least 80% of score weight has concrete scores. Before that threshold, preview events keep `score_available=false` and expose the accumulated `score_weight_total`.

## Install (beta)

Release artifacts are built via GitHub Actions on tags like `v0.3.*-beta.*`.

On Windows, run inside WSL2 and use the `linux_x86_64` artifact.

### Install script

Each beta release publishes an installer script (`install.sh`) that downloads the right archive for your OS/arch, verifies it via `checksums.txt`, and installs `hardproof` to `~/.local/bin`:

```sh
curl -fsSL "https://github.com/x07lang/hardproof/releases/download/v0.3.0-beta.0/install.sh" \
  | bash -s -- --tag "v0.3.0-beta.0"
```

You can also resolve the latest beta tag (requires GitHub API access):

```sh
curl -fsSL "https://github.com/x07lang/hardproof/releases/download/v0.3.0-beta.0/install.sh" \
  | bash -s -- --tag latest-beta
```

### Manual install

1) Download `hardproof_<VERSION>_<linux_x86_64|macos_arm64|macos_x86_64>.tar.gz` and `checksums.txt` from GitHub Releases.
   (`VERSION` is the tag without the `v` prefix, like `0.3.0-beta.0`.)

2) Verify `sha256`, extract, and place `hardproof` on your `PATH`.

## Development

Running `./scripts/ci/check_all.sh` locally requires the pinned x07 toolchain plus formal verification tools for `x07 verify --prove` / `x07 trust certify`:

- macOS: `brew install cbmc z3`
- Linux (CI-style pinned install): `./scripts/ci/install_formal_verification_tools_linux.sh` (requires `curl`, `unzip`, and `sudo`)

## Schemas

Report schemas and shared envelope fields are versioned and pinned for consumers:

- `x07.mcp.scan.report@0.3.0` (`schemas/x07.mcp.scan.report.schema.json`)
- `x07.mcp.scan.dimension@0.3.0` (`schemas/x07.mcp.scan.dimension.schema.json`)
- `x07.mcp.scan.finding@0.3.0` (`schemas/x07.mcp.scan.finding.schema.json`)
- `x07.mcp.scan.metrics@0.3.0` (`schemas/x07.mcp.scan.metrics.schema.json`)
- `x07.mcp.scan.usage@0.3.0` (`schemas/x07.mcp.scan.usage.schema.json`)
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

- Conformance runs in the `hardproof` binary (no Node.js toolchain required). HTTP and stdio emit the same `checks.json` shape/IDs so reports stay comparable across transports.
- For now, `replay record` records the `smoke/basic` HTTP scenario and stores the cassette at `details.http_session` (schema `x07.mcp.rr.http_session@0.1.0`). See `rr/README.md`.
- Trust and bundle verification operate on registry artifacts (`server.json` and `.mcpb`) rather than a running HTTP server. See `trust/README.md`.
- Output paths may be relative (for example `out/...`) or absolute.

## Scan outputs

`hardproof scan --out <DIR>` writes:

- `scan.json` (schema: `x07.mcp.scan.report@0.3.0`)
- `scan.events.jsonl` (JSONL event stream)
- `conformance.summary.json` + `conformance.summary.junit.xml` + `conformance.summary.html` + `conformance.summary.sarif.json` (when the conformance dimension runs)
- other dimension-specific artifacts as they are added (pinned by `scan.json.artifacts[]`)

Exit codes:
- `0` overall scan status is `pass` or `warn`
- `1` overall scan status is `fail`
- `2` invocation/config/runtime precondition failure

## CI / GitHub Action contract

The Action downloads a `hardproof` release binary and runs `hardproof scan` (HTTP or stdio):

```yaml
- name: Run Hardproof scan
  uses: x07lang/hardproof/hardproof-scan@v0.3.0-beta.0
  with:
    url: http://127.0.0.1:3000/mcp
    full-suite: "false"
```

See `action/README.md`.
See `hardproof-scan/README.md`.

## Fixture targets

Local fixture servers live under `scripts/ci/fixtures/` and are wired via:
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
- `good-stdio`: `conformance/scripts/spawn_reference_stdio.sh good-stdio`
- `broken-stdio`: `conformance/scripts/spawn_reference_stdio.sh broken-stdio`

## Known limitations (beta)

- Windows support is via WSL2 (run inside a Linux distro and use `linux_x86_64`).
- Some stdio target flows are still being stabilized; use the stdio fixtures as the reference shape.

## Feedback

File issues in `x07lang/hardproof` using the issue templates (Alpha feedback / Bug report).
