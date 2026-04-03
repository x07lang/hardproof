# Trust verification

`hardproof trust verify` checks a registry `server.json` file for required publisher-provided trust metadata and emits a machine-readable trust summary report (`x07.mcp.trust.summary@0.2.0`).

This is intentionally a small, deterministic set of checks for the private alpha. It validates the presence and basic format of trust fields; it does not prove a server is secure or safe to run.

## Usage

```sh
hardproof trust verify --server-json ./server.json

# machine output:
hardproof trust verify --server-json ./server.json --machine json
```

## Fixtures

- `trust/fixtures/server-good.json` (expected pass)
- `trust/fixtures/server-bad.json` (expected fail)
