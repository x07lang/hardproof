# Hardproof — Agent Notes

- Run `scripts/ci/check_all.sh` before pushing.
- Keep product code in pure X07 (`*.x07.json`); Python is only for CI helper scripts.
- On Windows, run inside WSL2 (native Windows toolchains are not currently published).

## Bump Version

Hardproof embeds its tool version in multiple release-facing surfaces (CLI banner, docs, action examples, fixtures, and the generated example artifacts under `docs/examples/`).

Workflow:

1. Decide the new version (example: `0.4.0-beta.2`).
2. From the repo root, run:
   - `python3 scripts/bump_version.py --to 0.4.0-beta.2`
3. Run the full gate:
   - `./scripts/ci/check_all.sh`
4. Commit the result (bump script updates version strings and regenerates the example artifacts via `make refresh-example-artifacts`).
