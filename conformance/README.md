# Conformance

This folder contains pinned inputs and fixture wiring used by `hardproof scan` (and `hardproof conformance run`).

- `pinned/official-package-version.txt`: pinned `@modelcontextprotocol/conformance` version.
- `pinned/conformance-baseline.yml`: expected failures baseline passed to the official suite.
- `fixtures/targets.json`: local fixture matrix (HTTP + stdio).
- `scripts/spawn_reference_http.sh`: Streamable HTTP fixture launcher.
- `scripts/spawn_reference_stdio.sh`: stdio fixture launcher.
- `scripts/wait_for_http.sh`: HTTP readiness helper.
