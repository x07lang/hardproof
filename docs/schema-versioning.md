# Schema versioning and compatibility

`hardproof` emits machine-readable JSON artifacts. Every JSON artifact includes a required top-level `schema_version` string of the form:

```text
x07.mcp.<artifact>@<semver>
```

## Rules

- Consumers must gate behavior on `schema_version`, not on `tool_version`.
- The JSON shape for a given `schema_version` is frozen: any shape change requires bumping the schema version string.
- While schemas are `<1.0.0`, treat `0.<minor>.0` bumps as potentially breaking (SemVer pre-1.0 rules).

## Current schema ids

- `x07.mcp.conformance.summary@0.2.0`
- `x07.mcp.replay.session@0.2.0`
- `x07.mcp.replay.verify@0.2.0`
- `x07.mcp.trust.summary@0.2.0`
- `x07.mcp.bundle.verify@0.2.0`
- `x07.mcp.report.manifest@0.1.0`
- `x07.mcp.corpus.result@0.1.0`
- `x07.mcp.corpus.summary@0.1.0`
- `x07.mcp.sarif@0.1.0` (SARIF 2.1.0 payloads)
