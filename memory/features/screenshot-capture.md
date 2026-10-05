# Screenshot capture

**Tag:** `#capture`

## Problem
Explaining something on screen starts with a clean, exact picture of the app
in question, without cropping or window-hunting.

## Solution
**New Screenshot trace** (or the Capture Frontmost App shortcut, or capping the
Neo pen) captures the frontmost app window at 1:1 point size and plays a short
Monochrome Flash transition from the window's position into a new
[board](board-window.md).

## Touchpoints
- [Menu bar agent](menu-bar-agent.md) and File → New Screenshot trace
- [Global shortcuts](global-shortcuts.md) → Capture Frontmost App
- [Neo pen](neo-pen.md) cap-off when enabled in [App settings](app-settings.md)
- Becomes a source submenu when [Device screenshots](device-screenshots.md) are available

## Rules
- Preserve the source window's 1:1 point size whenever screen bounds permit.
- One transition only (Monochrome Flash); no effect selector
  ([ADR 0004](../adr/0004-single-monochrome-capture-transition.md)).
- Reduce Motion reveals the board and toolbar directly.
- Requires Screen Recording permission ([Setup](setup.md)).
- The captured image is fully opaque, even after Highlighter use.

## FAQ
- **Which window is captured?** The frontmost app's window.
- **Why is it the same size as the original?** 1:1 keeps text and UI legible.
- **Can I disable the animation?** Enable macOS Reduce Motion.
- **Capture failed?** Check Screen Recording permission in Setup.

## Encoded enforcement
| Rule | Guard |
| --- | --- |
| Single transition, reduced motion | `RetainedInkProbe.swift › verifyCaptureTransitionEffects` |
| Default capture size | `RetainedInkProbe.swift › verifyAutomaticCaptureDefaultSize` |
| Opaque screenshot | `ProductTldrawProbe.swift › verifyCapturedScreenshotOpacity` (`TRACE_PRODUCT_TLDRAW_PROBE=text`) |
