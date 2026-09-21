# Development

## Prerequisites

- macOS 13+
- Full Xcode with Swift 5.10 support
- Bun 1.4+
- Bluetooth for Neo input
- Screen Recording and Microphone permissions

The launcher selects full Xcode automatically. An explicitly set
`DEVELOPER_DIR` must point to full Xcode. Set `TRACE_MACOS_SDK_PATH` if the
required macOS 26.5 SDK is not found automatically.

## Run

Build, package, sign, and launch Trace:

```sh
./tools/trace
```

Build and package without launching:

```sh
TRACE_BUILD_ONLY=1 ./tools/trace
```

Reset onboarding, calibration, window state, and Trace privacy grants:

```sh
./tools/trace --clear
```

Dictation accepts `OPEN_ROUTER_API_KEY` or `OPENROUTER_API_KEY`.
Keys may also be supplied through `TRACE_ENV_FILE` or an untracked repository
root `.env`. The same root file supplies `VITE_TLDRAW_LICENSE_KEY` to the web
renderer. Never commit keys.

## Build

```sh
export DEVELOPER_DIR="$(./tools/resolve-xcode-developer-dir)"
swift build
```

Build the web renderer:

```sh
cd apps/trace-macos/WebCanvas
bun install --frozen-lockfile
bun run build
```

## Test

```sh
swift run neo-transport-tests
swift run neo-input-tests
swift run trace-geometry-tests
swift run trace-calibration-tests
swift run trace-metrics-tests
swift run trace-stroke-processing-tests
swift run trace-lab-replay-tests
swift run trace-app-core-tests
swift run trace-voice-tests
```

Hardware-free checks:

```sh
swift build --product trace
TRACE_GLOBAL_SHORTCUTS_PROBE=1 .build/debug/trace
TRACE_HARDWARE_FREE_PROBE=1 .build/debug/trace
TRACE_BUILD_ONLY=1 ./tools/trace
TRACE_PRODUCT_TLDRAW_PROBE=1 ".build/Trace.app/Contents/MacOS/trace"
```

## Diagnostics

```sh
./tools/neo-diagnostics
./tools/trace-input-lab
```

Build either app without launching:

```sh
TRACE_BUILD_ONLY=1 ./tools/neo-diagnostics
TRACE_BUILD_ONLY=1 ./tools/trace-input-lab
```

## Project constraints

- Trace is an AppKit `LSUIElement` menu agent; the product canvas is the
  bundled hidden-UI tldraw renderer.
- Neo stroke data is authoritative in `document.json`; tldraw owns mouse
  drawing and stores its state in `tldraw.json`.
- `.traceboard` packages contain the source image, `document.json`, and
  optional voice, transcript, and tldraw files.
- The packaged app must be launched through `./tools/trace` so web resources
  are embedded and the app is signed consistently.
