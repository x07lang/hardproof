# x07-mcp-test GitHub Action (alpha)

This Action downloads an `x07-mcp-test` alpha release binary and runs `x07-mcp-test conformance run` against a target MCP server URL.

## Usage

```yaml
name: mcp-quality

on:
  push:
  pull_request:

jobs:
  conformance:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4

      # Start your MCP server here (or target a deployed URL).
      # - name: Start server
      #   run: ./scripts/start-server.sh

      - name: Run MCP conformance
        uses: x07lang/x07-mcp-test/action@v0.1.0-alpha.4
        with:
          url: http://127.0.0.1:3000/mcp
          full-suite: "false"

      - name: Upload reports
        if: always()
        uses: actions/upload-artifact@v4
        with:
          name: x07-mcp-test-reports
          path: |
            out/doctor.json
            out/conformance/summary.json
            out/conformance/summary.junit.xml
            out/conformance/summary.html
```

## Inputs

- `url` (required): MCP HTTP URL (example: `http://127.0.0.1:3000/mcp`)
- `full-suite` (optional): `"true"` to run the full official suite
- `baseline` (optional): path to an expected-failures YAML file
- `version` (optional): `v0.1.*-alpha.*` tag, or `latest-alpha`

## Outputs

- `ok`: `true` if conformance passed (exit 0)
- `json_report`: `out/conformance/summary.json`
- `junit_report`: `out/conformance/summary.junit.xml`
- `html_report`: `out/conformance/summary.html`

## Notes

- The official conformance suite runs via `npx`, so Node/npm/npx must be available on the runner.
- Windows is supported via WSL2; this Action currently targets Linux/macOS runners.
