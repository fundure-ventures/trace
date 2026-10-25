# Shared Pencil actions with independent device watchers

**Status:** Accepted

## Context

Trace supports a Neo Smartpen on Ncode paper and Apple Pencil on a
Sidecar-connected iPad. Their physical pickup signals differ, but users
expect the same capture and copy preferences rather than separate
automation rules per pen type.

Apple Pencil attachment is not exposed by a public Mac Bluetooth API.
Sidecar drawing events alone cannot distinguish putting the Pencil on its
magnetic charger from lifting it between strokes. The working prototype
reads charging/attachment diagnostics from an explicitly trusted iPad over
Wi-Fi, then connects Sidecar through Apple's private SidecarCore framework.
This decision preserves those implementation constraints rather than
presenting them as public or guaranteed Apple interfaces.

See [App settings](../features/app-settings.md),
[Setup](../features/setup.md), [Neo pen](../features/neo-pen.md),
[Screenshot capture](../features/screenshot-capture.md), and
[Copy trace](../features/copy-trace.md).

## Decision

Keep capture-on-pickup and copy-on-put-down as shared application settings.
Retain their existing saved values rather than resetting preferences during
the menu reorganization. A put-down requests the existing whole-trace Copy
pipeline, including snapshot flush, selected Copy format, persistence, and
Dictation completion. The Copy close-after-copy preference remains the
only authority for closing after a successful copy. Disabling a watcher
does not synthesize a put-down or trigger Copy.

Use separate device watching controls beneath one Pencil section:

- Neo uses the existing CoreBluetooth transport and protocol normalizer.
  Unticking it stops discovery, cancels automatic reconnection through an
  intentional disconnect, and resets input state without closing the board.
- Each validated iPad is stored by its stable device identifier with its
  hostname and display name. It has an independent enabled preference and
  one owned telemetry helper process. Preserve the previous single-iPad
  configuration and opt-out when loading older settings.
- Enabled iPads can be watched concurrently, but only one Pencil owns an
  active automatic Sidecar capture. Pickup targets that device's iPad;
  another device's return must not copy or move the active board.

The bundled helper runs through external `uv` with cached
`pymobiledevice3==11.44.0`, offline. It uses the Mac's existing pairing
record and lockdown port 62078 to open the iPad's diagnostic log service.
Only normalized Pencil state, setup events, names, and actionable errors
cross the process pipe; raw logs are not saved by the app. Reconnect begins
with a baseline and duplicate states are suppressed.

Guided Setup owns a separate, cancellable helper. It discovers iPads with
system Bonjour, guides USB connection and user-driven Finder/iPad trust,
and requires explicit consent before enabling wireless lockdown access.
USB/trust and unplug transitions are observed automatically; permission
approval and Pencil attachment/pickup/return advance as detected.
Normal iPad watchers are paused during live verification, so test gestures
cannot capture or copy. Save a new device only after successful verification;
closing Setup stops checks and resumes only enabled device watchers.

Capture the frontmost Mac app before starting or changing Sidecar.
Place the editable board on the matched display rather than a read-only
projection. Return restores the Mac placement before requesting Copy.
Track ownership of newly started Sidecar sessions and disconnect on board
close only when Trace started that session. Preserve a pre-existing session.
Drawing still goes through tldraw, as described in
[ADR 0001](0001-required-tldraw-product-canvas.md).

## Rejected alternatives

- Treat Pencil hover or stroke-end as put-down: these occur during ordinary
  drawing and would copy between strokes.
- Keep independent Apple Pencil action preferences: they duplicate the
  Neo workflow and can disagree with the global Copy close preference.
- Keep one global iPad listener and overwrite its configuration: that
  loses previously configured devices and cannot disable watching per iPad.
- Require an iPad companion app: it adds another installation and lifecycle;
  the currently proven workflow works with the Mac app and existing trust.

## Consequences

- Device protocols remain separate while capture and Copy behavior share
  the existing product paths.
- Users can disable one watcher or every watcher without losing pairings,
  saved traces, or their shared action choices.
- Diagnostic message formats and private Sidecar interfaces can change with
  OS updates. This is not a Mac App Store-compatible integration.
- Local Network and Screen Recording permissions, USB trust, same-network
  reachability, and external diagnostic runtime prerequisites remain real
  setup requirements. Dependencies are not silently downloaded.
- Multi-device watching does not imply simultaneous editable Sidecar boards;
  Trace retains its single active board workflow.
