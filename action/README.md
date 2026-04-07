# Hardproof Scan (beta)

This Action downloads a `hardproof` release binary and runs `hardproof ci` against a target MCP server (HTTP or stdio).

## Usage

This Action is served from two paths during the beta transition:
- Preferred: `x07lang/hardproof/hardproof-scan@...`
- Legacy alias: `x07lang/hardproof/action@...`

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
- `allow-partial-score` (optional): `"true"` to allow threshold gating to pass when `score_mode=partial`
- `require-trust-for-full-score` (optional): `"true"` to require a full score and fail when trust evidence is missing/unknown
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

## Notes

- Hardproof runs as a standalone binary (no Node.js toolchain required).
- Windows is supported via WSL2; this Action currently targets Linux/macOS runners.
- By default, the Action now fails when the scan only reaches `score_mode=partial`.
- For release-grade CI, prefer `threshold: "85"` together with trust inputs or `require-trust-for-full-score: "true"`.

## Upload SARIF (optional)

```yaml
permissions:
  security-events: write

- name: Upload SARIF to code scanning
  if: always() && steps.mcp.outputs.report_sarif != ''
  uses: github/codeql-action/upload-sarif@v3
  with:
    sarif_file: ${{ steps.mcp.outputs.report_sarif }}
```

## PR summary snippet

```yaml
- name: MCP conformance summary
  if: always()
  run: |
    {
      echo "### MCP conformance"
      echo ""
      echo "- ok: ${{ steps.mcp.outputs.scan_ok }}"
      echo "- json: ${{ steps.mcp.outputs.report_json }}"
      echo "- junit: ${{ steps.mcp.outputs.report_junit }}"
      echo "- html: ${{ steps.mcp.outputs.report_html }}"
      echo "- sarif: ${{ steps.mcp.outputs.report_sarif }}"
    } >>"$GITHUB_STEP_SUMMARY"
```
