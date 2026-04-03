# Replay / record (rr)

Replay support lets `hardproof` produce deterministic, reviewable evidence:

- `hardproof replay record` records a small deterministic session (HTTP or stdio) into a session file (`x07.mcp.replay.session@0.2.0`).
- `hardproof replay verify` replays the recorded cassette against a target server and emits a pass/fail verification report (`x07.mcp.replay.verify@0.2.0`).

The recorded cassette lives inside the session file:
- HTTP: `details.http_session` (schema `x07.mcp.rr.http_session@0.1.0`)
- stdio: `details.stdio_session` (schema `x07.mcp.rr.stdio_jsonl@0.1.0`, plus sidecar JSONL transcript files)

## Cassette format (v1)

### HTTP

`x07.mcp.rr.http_session@0.1.0` contains:

- `id`: scenario id (example: `smoke.basic`)
- `base_url`: scheme + host + port (example: `http://127.0.0.1:18080`)
- `mcp_path`: HTTP path (example: `/mcp`)
- `steps[]`: ordered request/response steps with normalized headers and JSON payloads

HTTP+SSE targets (Streamable HTTP) are supported by extracting and canonicalizing JSON payloads from `data: ...` event lines.

### stdio

`x07.mcp.rr.stdio_jsonl@0.1.0` contains:

- `id`: scenario id (example: `smoke.basic`)
- `cmd`: stdio command used to spawn the server
- `cwd` / `env_file`: optional process inputs
- `c2s_jsonl`: path to canonical client→server JSON-RPC lines
- `s2c_jsonl`: path to canonical server→client JSON-RPC lines

## Sanitization

`replay record` supports `--sanitize` categories to redact token-like / secret-like fields before writing the session file.

## Fixtures and schemas

- Fixture session output: `fixtures/reports/replay.session.json`
- Fixture cassette: `rr/fixtures/good-http.session.json`
- Cassette schema: `rr/schemas/session.schema.json`
- Verify schema: `rr/schemas/replay-verify.schema.json`
