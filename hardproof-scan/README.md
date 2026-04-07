# Hardproof Scan (beta)

Run Hardproof verification in GitHub Actions using a release binary.

## Usage

### Streamable HTTP target

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

      - name: Run Hardproof scan
        id: mcp
        uses: x07lang/hardproof/hardproof-scan@v0.4.0-beta.0
        with:
          url: http://127.0.0.1:3000/mcp
          threshold: "85"
          require-trust-for-full-score: "true"
          full-suite: "false"
          sarif: "true"

      - name: Upload reports
        if: always()
        uses: actions/upload-artifact@v4
        with:
          name: hardproof-reports
          path: |
            out/doctor.json
            out/scan
```

### stdio target

```yaml
- name: Run Hardproof scan (stdio)
  id: mcp
  uses: x07lang/hardproof/hardproof-scan@v0.4.0-beta.0
  with:
    cmd: ./server --stdio
    cwd: servers/my-mcp
    env-file: .env.mcp
    threshold: "85"
    require-trust-for-full-score: "true"
    full-suite: "false"
```

## Inputs

- `url` (required unless `cmd`): MCP HTTP URL (example: `http://127.0.0.1:3000/mcp`)
- `cmd` (required unless `url`): MCP stdio command (example: `./server --stdio`)
- `cwd` (optional): working directory for `cmd`
- `env-file` (optional): env file to load for `cmd`
- `full-suite` (optional): `"true"` to run the extended suite
- `baseline` (optional): path to an expected-failures YAML file
- `sarif` (optional): `"true"` to emit a `report.sarif.json` file
- `require-trust-for-full-score` (optional): `"true"` to fail when the scan remains partial because trust evidence is missing/unknown
- `threshold` (optional): minimum score (0-100) required to pass (default `"80"`)
- `version` (optional): `v0.4.*-beta.*` tag, or `latest-beta`

## Outputs

- `scan_ok`: `true` if scan passed (exit 0)
- `report_json`: `out/scan/scan.json`
- `report_junit`: `out/scan/conformance.summary.junit.xml`
- `report_html`: `out/scan/report.html`
- `report_sarif`: `out/scan/report.sarif.json` (when enabled)

Compatibility aliases (beta):
- `ok`, `json_report`, `junit_report`, `html_report`, `sarif_report`

## Migration (beta)

If you previously used:

```yaml
uses: x07lang/hardproof/action@v0.1.0-alpha.9
```

Switch to:

```yaml
uses: x07lang/hardproof/hardproof-scan@v0.4.0-beta.0
```

The `action/` path remains available during the beta transition.
