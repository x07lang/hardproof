# Manual install QA

Manual install QA worksheet for `hardproof`.

Goal: confirm that a cold user can download and run the beta verifier without building from source.

## Release under test

- tag:
- release URL:

## Required coverage

- macOS arm64 (fresh machine)
- macOS x64 (fresh machine)
- Ubuntu x64 (fresh VM)
- Windows x64 via WSL2 (fresh VM + Ubuntu distro)

## Checklist (per environment)

Record:
- time to install:
- time to first green conformance:
- missing dependencies:
- confusing output:
- manual workarounds:

### 1) Install

- [ ] download via `install.sh`
- [ ] checksum verification succeeds
- [ ] binary installed to `PATH`
- [ ] `hardproof --help` works

### 2) Diagnostics

- [ ] `hardproof doctor` works
- [ ] `hardproof doctor --machine json` works
- [ ] `hardproof doctor --cmd 'bash conformance/scripts/spawn_reference_stdio.sh good-stdio'` agrees with running the same stdio target via `hardproof scan --cmd ... --transport stdio`

### 3) Conformance (smoke)

- [ ] target URL reachable (or stdio command runnable)
- [ ] run `hardproof scan --help` (verify it lists `--url` and/or `--cmd`)
- [ ] run `hardproof trust verify --help` (verify it lists `--server-json`)
- [ ] run `hardproof bundle verify --help` (verify it lists `--mcpb`)
- [ ] run `hardproof ci validate-json --help` (verify it lists `--schema` and `--input`)
- [ ] run `hardproof scan --url "<URL>" --out out/scan --machine json`
- [ ] outputs produced:
  - `scan.json`
  - `scan.events.jsonl`
  - `conformance.summary.json`
  - `conformance.summary.junit.xml`
  - `conformance.summary.html`
  - `conformance.summary.sarif.json`

## Notes

- Windows support is via WSL2 (run X07 tools inside Linux).
