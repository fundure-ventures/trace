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

The repository produces two application bundles:

| Product | Purpose | Output |
|---|---|---|
| Trace Debug | Fast local iteration with a separate bundle identity and ad-hoc signature | built at `.build/Trace Debug.app`, launched from `/Applications/Trace Debug.app` |
| Trace | Production release build, unsigned until the signing step | `.build/Trace.app` |

The app quick actions intentionally contain only **Launch Debug**,
**Build Release**, and **Sign Release**.

Build, package, ad-hoc sign, and launch the debug product:

```sh
./tools/trace
```

Build the debug product without launching:

```sh
TRACE_BUILD_ONLY=1 ./tools/trace
```

`Trace Debug.app` uses the `com.traceproject.app.debug` bundle identifier so
its launch registration, privacy grants, preferences, and ad-hoc signature do
not replace the production product. Launching installs it at one canonical
location (`/Applications/Trace Debug.app`, or `TRACE_APP_INSTALL_DIR`) so
worktrees share stable Launch Services and TCC state.

Build the unsigned production product:

```sh
./tools/build-release
```

Inject an explicit release version while building:

```sh
./tools/build-release 0.2.0 2
```

The build compiles `design/app-icon/trace.icon` with Xcode's `actool`, bundles
the layered `Assets.car` and fallback `trace.icns`, and merges the generated
icon metadata before the optional signing step. Edit the source in Icon
Composer and rebuild; the standalone Blender PNGs are not used as the
application icon. Use an Xcode version that supports the source's Icon
Composer features (verified with Xcode 27).

The editable artwork is `design/app-icon/trace-e.blend`; the Python builder
and layer exporter live alongside it. Generated `trace-e.png` previews and
`layers/` exports are ignored. The assets inside `trace.icon` remain tracked
and are the inputs used by every packaged Trace build.

For known issues and fixes, see [Troubleshooting](TROUBLESHOOTING.md).

Reset debug-product onboarding, calibration, window state, and privacy grants:

```sh
./tools/trace --clear
```

Dictation accepts `OPEN_ROUTER_API_KEY` or `OPENROUTER_API_KEY`.
Keys may also be supplied through `TRACE_ENV_FILE` or an untracked repository
root `.env`. The same root file supplies `VITE_TLDRAW_LICENSE_KEY` to the web
renderer. The local `.env` is copied only into the installed debug product so
it can resolve credentials away from the repository. It is never copied into
the unsigned or signed production product. Never commit keys.

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

## Production signing

The direct-download release path signs the existing `.build/Trace.app` built
by `tools/build-release`. Signing applies the Developer ID identity, hardened
runtime entitlements, notarization, stapling, Gatekeeper verification, and
archive checksum without opening Xcode.

Required local credentials:

- A `Developer ID Application` certificate installed in a keychain.
- An App Store Connect API key authorized for notarization, or a notarytool
  keychain profile.

Store API credentials locally once:

```sh
xcrun notarytool store-credentials trace-notary \
  --key /path/to/AuthKey_KEYID.p8 \
  --key-id KEYID \
  --issuer ISSUER_ID
```

Build the release product, then sign and notarize it:

```sh
./tools/build-release 0.2.0 2

TRACE_CODE_SIGN_IDENTITY="Developer ID Application: Example (TEAMID)" \
TRACE_NOTARY_KEYCHAIN_PROFILE=trace-notary \
./tools/sign-release 0.2.0 2
```

When exactly one Developer ID Application identity is installed,
`tools/sign-release` selects it automatically. It also defaults to the
`trace-notary` keychain profile, so the **Sign Release** quick action works
after the one-time credential setup above.

Build and sign in one command:

```sh
./tools/build-signed-release 0.2.0 2
```

The command writes `.build/release/Trace-0.2.0-2.zip` and its SHA-256 file.
Release artifacts, certificates, API keys, provisioning profiles, `.env`, and
all `.build/` contents are ignored. Signing scripts, entitlements, and source
`Info.plist` defaults are versioned. Packaging refuses app bundles containing
environment files, signing credentials, provisioning profiles, keychains, or
PEM private-key material.

## Publishing a GitHub Release

Production releases are built and signed locally; CI release builds are
intentionally disabled. Use the repository Trace release skill to publish
a release. It requires a clean checkout whose current branch is `main` and
whose `HEAD` exactly matches `origin/main`.

The skill:

1. Collects and validates the app version and build number.
2. Drafts release notes for explicit approval.
3. Builds `.build/Trace.app` from current `main`.
4. Developer ID-signs, notarizes, staples, and Gatekeeper-verifies it.
5. Verifies the embedded version/build and archive checksum.
6. Creates `vVERSION` on the exact release commit and uploads only the
   notarized ZIP and SHA-256 file to GitHub Releases.

Run it from a dedicated, clean `main` session. It refuses to switch branches,
merge, stash, or publish from a feature branch.

GitHub secret scanning and push protection are enabled for this public
repository and should remain enabled.

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
TRACE_OPEN_FILE_PROBE=1 .build/debug/trace
TRACE_HARDWARE_FREE_PROBE=1 .build/debug/trace
TRACE_BUILD_ONLY=1 ./tools/trace
TRACE_PRODUCT_TLDRAW_PROBE=1 ".build/Trace Debug.app/Contents/MacOS/trace"
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
- Launch local debug builds through `./tools/trace` so web resources, the
  debug identity, and the ad-hoc signature are applied consistently.
- Build production bundles through `./tools/build-release` and sign that exact
  `.build/Trace.app` through `./tools/sign-release`.
