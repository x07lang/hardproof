# Manual install QA

Manual install QA worksheet for `hardproof`.

Goal: confirm that a cold user can download and run the alpha verifier without building from source.

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

### 3) Conformance (smoke)

- [ ] Node/npm/npx preconditions satisfied
- [ ] run `hardproof scan --help`
- [ ] run `hardproof scan --url "<URL>" --out out/conformance --machine json`
- [ ] outputs produced: `summary.json`, `summary.junit.xml`, `summary.html`

## Notes

- Windows support is via WSL2 (run X07 tools inside Linux).
