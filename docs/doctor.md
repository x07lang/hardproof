# `hardproof doctor`

Environment and toolchain diagnostics for running the private-alpha MCP wedge CLI.

## Usage

```bash
hardproof doctor
hardproof doctor --cmd "my-mcp-server --stdio"
hardproof doctor --url "http://127.0.0.1:3000/mcp"

# machine output:
hardproof doctor --machine json
```

## Options

- `--cmd <STR>`: MCP stdio command to check (verifies the first token exists).
- `--url <STR>`: MCP HTTP URL to check (reachability via `curl`).
- `--machine json`: Emit machine-readable JSON output.

## Exit codes

- `0`: success
- `1`: verification failures
- `2`: usage/config error (example: unsupported `--machine` value)

## Fixtures

Negative fixtures used by CI live in `fixtures/doctor/`.
