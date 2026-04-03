# Conformance

This folder contains pinned inputs and fixture wiring used by `hardproof scan` (and `hardproof conformance run`).

- `pinned/official-package-version.txt`: upstream `@modelcontextprotocol/conformance` reference version (parity target; Hardproof runs without Node.js).
- `pinned/conformance-baseline.yml`: expected failures baseline consumed by `hardproof scan`/`hardproof ci`.
- `fixtures/targets.json`: local fixture matrix (HTTP + stdio).
- `scripts/spawn_reference_http.sh`: Streamable HTTP fixture launcher.
- `scripts/spawn_reference_stdio.sh`: stdio fixture launcher.
- `scripts/wait_for_http.sh`: HTTP readiness helper.
