# Hardproof VHS tapes

This directory contains `vhs` tapes used to capture short live-demo clips of:

- `hardproof scan --ui rich` (live rich)
- `hardproof scan --ui tui` (alternate-screen TUI)

Render the clips with:

```sh
./scripts/dev/render_vhs.sh
```

Dependencies:

- `vhs`
- `ttyd`
- `ffmpeg`

On macOS:

```sh
brew install vhs ttyd ffmpeg
```

