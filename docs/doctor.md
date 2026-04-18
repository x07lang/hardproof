# `hardproof doctor`

Environment and toolchain diagnostics for running Hardproof.

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

## Command resolution

When `--cmd` is supplied, Hardproof verifies the command can be resolved using the same PATH policy used by real stdio scans:

- If the first token looks like a path (contains `/`), Hardproof checks it exists and is a file.
- Otherwise, Hardproof checks it via `/bin/sh -lc 'command -v <token>'` with `PATH` sourced from the current environment (fallback: a minimal `/usr/local/bin:/opt/homebrew/bin:/usr/bin:/bin:/usr/sbin:/sbin`).

## Exit codes

- `0`: success
- `1`: verification failures
- `2`: usage/config error (example: unsupported `--machine` value)

## Fixtures

Negative fixtures used by CI live in `fixtures/doctor/`.
