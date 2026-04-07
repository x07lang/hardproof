# Targets and transports

`hardproof` supports both Streamable HTTP and stdio targets in the public beta.

For stdio targets, `hardproof` reports a smoke performance score from a single initialize+ping probe.
Tool-call and concurrency sampling stay HTTP-only because repeated cold starts are expensive and distort the signal for one-shot stdio launches.

The verifier treats MCP targets as an explicit **transport + reference** pair:

- `streamable_http`: a URL (example: `http://127.0.0.1:3000/mcp`)
- `stdio`: a local command line (example: `my-mcp-server --stdio`)

## CLI normalization

Commands that operate on a running MCP server accept exactly one of:

- `--url <URL>` (Streamable HTTP)
- `--cmd <STR>` (stdio)

Additional stdio-only flags:

- `--cwd <PATH>`: working directory for the stdio process
- `--env-file <PATH>`: env file to load for the stdio process

Conformance also accepts:

- `--transport <STR>`: a transport hint (`http` or `stdio`)

Invalid flag combinations fail with exit code `2`.

## Report target metadata

Report JSON envelopes include a normalized `target` object:

- `kind`: target kind (`mcp_server` or `file`)
- `transport`: `streamable_http` | `stdio` | `file`
- `ref`: the URL, command string, or file path
- `meta`: transport-specific metadata

For stdio targets, `meta` includes `cwd`, `env_file`, and a (sanitized) `env_keys` list when available.
