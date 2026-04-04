# Hardproof Scan example artifacts

This directory contains sample artifacts that website/docs/announcements can embed directly.

Generated from the `good-http` fixture target using `hardproof v0.1.0-alpha.9`.

## Contents

- `summary.json`: machine-readable conformance summary (schema `x07.mcp.conformance.summary@0.2.0`)
- `summary.html`: HTML report rendering of the same run
- `terminal.svg`: screenshot-style rendering of a `hardproof scan` terminal run

## Repro

From the repo root:

```sh
x07 bundle --project x07.json --profile os --out out/hardproof
conformance/scripts/spawn_reference_http.sh good-http noauth
hardproof scan --url "http://127.0.0.1:18080/mcp" --out out/conformance --machine json
```

