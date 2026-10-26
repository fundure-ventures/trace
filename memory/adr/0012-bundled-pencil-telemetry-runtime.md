# Bundle the Pencil telemetry runtime inside Trace.app

**Status:** Accepted

## Context

The Apple Pencil watcher uses `pymobiledevice3` to read the trusted iPad's
wireless lockdown log service. Previously, Trace launched its source helper
through `uv` and required a cached package environment on each Mac. That made
Pencil setup fail on a clean install and made app behavior depend on a
developer's Python tooling.

The dependency declares GPL-3.0-or-later. Trace's current license restricts
redistribution and commercial use. See [Apple Pencil automation](../features/setup.md)
and [shared Pencil actions](0011-shared-pencil-actions-and-device-watchers.md).

## Decision

Build a one-folder, architecture-specific PyInstaller executable from the
pinned telemetry source and locked `pymobiledevice3` dependency graph. Place
the executable, its embedded Python runtime, package inventory, and a helper
Info.plist in a private `PencilTelemetry.app` under
`Trace.app/Contents/Helpers`. Launch its executable directly; the installed
app does not use `uv`, invoke a system Python, or download packages. Sign every
Mach-O file, then the helper app, then the containing Trace app, without
copying the app's unrelated audio or Bluetooth entitlements onto the runtime
libraries.

Keep the build lock and packaging scripts in the repository. Build the helper
as part of both Debug and Release app packaging on the same macOS architecture
as the app. Public release remains blocked until license compatibility and
required source/notice obligations have been resolved. This decision describes
packaging only and does not grant distribution rights.

## Rejected alternatives

- Resolve dependencies through `uv` on each user's Mac: fails on clean Macs
  without the tool, cache, or network, and makes runtime behavior environment
  dependent.
- Ship a second user-installed helper app: adds a separate download and update
  lifecycle for a feature that belongs to Trace.
- Use a single-file frozen executable: extracts native libraries at runtime,
  complicating code signing and library validation; the one-folder layout keeps
  every native binary available to sign explicitly.

## Consequences

- A clean install can start the Pencil watcher without developer tools or
  package downloads.
- The app bundle and download grow to include Python and native dependencies;
  the helper embeds a generated dependency-license inventory to aid review.
- Build-time `uv` and package registry access are needed when the locked
  runtime must be prepared for a new build.
- Every bundled Mach-O dependency must be signed before the containing app.
- The chosen dependency's license remains a hard public-release gate; bundling
  it separately does not remove or answer that obligation.
