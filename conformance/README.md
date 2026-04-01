# Conformance

This folder contains pinned inputs and fixture wiring used by `x07-mcp-test conformance run`.

- `pinned/official-package-version.txt`: pinned `@modelcontextprotocol/conformance` version.
- `pinned/conformance-baseline.yml`: expected failures baseline passed to the official suite.
- `fixtures/targets.json`: local Week 2 fixture matrix (good/auth/broken).
- `scripts/spawn_reference_http.sh`: fixture server launcher.
- `scripts/wait_for_http.sh`: HTTP readiness helper.

