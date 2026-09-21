# Trace

Trace is a macOS menu-bar app for turning a screenshot or blank canvas into a
visual prompt. Capture a window, annotate it with a Neo Smartpen or the built-in
drawing tools, optionally record a transcript, then copy the image and text in
one action.

## Requirements

- macOS 13 or later
- Xcode Command Line Tools or Xcode with Swift 5.10 support
- Bun 1.4+ for the bundled tldraw canvas
- Bluetooth for Neo Smartpen input
- Screen Recording permission for screenshot capture
- Microphone permission for voice annotation

## Proprietary materials

Trace does not distribute proprietary printable patterns or vendor manuals.
Obtain compatible Neo/Ncode paper and hardware documentation from authorized
vendor or reseller sources. Keep local copies only in the ignored paths listed
in `.gitignore`.

## Launch

Before building a production copy, create the untracked file
`apps/trace-macos/RendererLabWeb/.env` with your tldraw production license:

```dotenv
VITE_TLDRAW_LICENSE_KEY=your-tldraw-license-key
```

The repository ignores this file. Do not commit the license key. Vite embeds
the value in the bundled web canvas, so use a key whose tldraw license
restrictions match the distributed app.

From the repository root:

```sh
./tools/trace
```

The launcher builds the Swift app and bundled web canvas, signs the local app,
and opens it. On first launch, grant the requested permissions and complete the
paper calibration if you want to use a Neo pen.

To repeat onboarding without deleting saved `.traceboard` documents:

```sh
./tools/trace --clear
```

## Primary workflow

1. Create a screenshot trace with `Cmd+N`, create a blank trace with
   `Shift+Cmd+N`, or open one or more images from Finder.
2. Draw with the Neo pen or the Select, Pen, Highlighter, and Rectangle tools.
3. Use Voice when a spoken explanation helps.
4. Press `Cmd+C` to copy the annotated image and transcript, save the trace,
   and close the board.

Finder **Open With** accepts an image batch and places the images together on
one blank canvas.

## More detail

- [Development guide](DEVELOPMENT.md) — setup, commands, architecture,
  diagnostics, and troubleshooting
- [Architecture decision records](docs/adr/README.md) — current durable
  implementation decisions
- [POC and investigation archive](docs/poc/README.md) — product drafts,
  hardware findings, experiments, and historical plans
- [Design system](DESIGN.md) and [product definition](PRODUCT.md)

Voice transcription can use a personal OpenRouter API key saved from Trace's
Setup panel. Trace stores that key only in macOS Keychain and never displays it
again after saving; Setup supports replacing or removing it.

Custom builds can instead supply `OPEN_ROUTER_API_KEY` or
`OPENROUTER_API_KEY` through the process environment, `TRACE_ENV_FILE`, the
repository-root `.env`, or the existing bundle-relative `.env` lookup. These
sources take precedence over Keychain and hide the personal-key controls.
Never commit credentials.

## License and contributing

Trace is source-available, not open source. Individuals may view, clone,
modify, and build it solely for their own personal, noncommercial use.
Commercial use and redistribution of source, forks, or binaries are not
permitted. See the [personal-use license](LICENSE) for the complete terms.
Issues are welcome. Code and documentation contributions are accepted under
the terms in [CONTRIBUTING.md](CONTRIBUTING.md).
