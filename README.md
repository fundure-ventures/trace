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

## Pen and paper support

Trace is developed and physically tested with the **Neo Smartpen M1
(`NWP-F50`)** over Bluetooth. Other Neo models have not been validated.

Pen coordinates require compatible **Neo Ncode paper**; ordinary paper cannot
provide spatial input. Trace does not distribute proprietary Ncode patterns.
Use authorized Neo paper when possible. For local print testing, only the
B-source pattern printed at its original 100% scale has produced usable
coordinates; scaled and A-source variants are not supported.

Complete Trace's four-corner calibration before drawing with the pen.

## Custom build configuration

Voice transcription is optional. Custom builds can provide an OpenRouter API
key in the repository-root `.env`:

```dotenv
OPEN_ROUTER_API_KEY=your-openrouter-api-key
```

`OPENROUTER_API_KEY`, `TRACE_ENV_FILE`, the process environment, and the
bundle-relative `.env` lookup are also supported. Externally supplied keys take
precedence over the personal key stored from Trace's Setup panel. Never commit
credentials.

Production builds also require the untracked file
`apps/trace-macos/RendererLabWeb/.env` with your tldraw production license:

```dotenv
VITE_TLDRAW_LICENSE_KEY=your-tldraw-license-key
```

## Launch

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

Without an externally supplied key, voice transcription can use a personal
OpenRouter API key saved from Trace's Setup panel. Trace stores it only in
macOS Keychain; Setup supports replacing or removing it.

## License and contributing

Trace is source-available, not open source. Individuals may view, clone,
modify, and build it solely for their own personal, noncommercial use.
Commercial use and redistribution of source, forks, or binaries are not
permitted. See the [personal-use license](LICENSE) for the complete terms.
Issues are welcome. Code and documentation contributions are accepted under
the terms in [CONTRIBUTING.md](CONTRIBUTING.md).
