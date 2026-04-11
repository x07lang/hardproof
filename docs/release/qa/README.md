# Release QA

Run `hardproof/scripts/release/qa_matrix.sh` before tagging a release to produce a small set of scan artifacts (scan JSON, events, HTML, SARIF) for common MCP server targets.

Example:

```bash
cd hardproof
./scripts/release/qa_matrix.sh
```

The script writes outputs under `hardproof/out/release-qa/<timestamp>/`.
