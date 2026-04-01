# Manual install QA (M1)

This is the Week 4 manual install QA worksheet for `x07-mcp-test`.

Goal: confirm that a cold user can download and run the alpha verifier without building from source.

## Release under test

- tag:
- release URL:

## Required coverage (M1)

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
- [ ] `x07-mcp-test --help` works

### 2) Diagnostics

- [ ] `x07-mcp-test doctor` works
- [ ] `x07-mcp-test doctor --machine json` works

### 3) Conformance (smoke)

- [ ] Node/npm/npx preconditions satisfied
- [ ] run `x07-mcp-test conformance run --help`
- [ ] run `x07-mcp-test conformance run --url "<URL>" --out out/conformance --machine json`
- [ ] outputs produced: `summary.json`, `summary.junit.xml`, `summary.html`

## Notes

- Windows support for M1 is via WSL2 (run X07 tools inside Linux).
