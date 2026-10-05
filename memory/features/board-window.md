# Board window

**Tag:** `#board`

## Problem
The annotated screenshot should feel like the captured window itself, not a
document inside another app's chrome.

## Solution
Each trace opens in a visually borderless window: the screenshot is the whole
color field and one floating toolbar pill sits 10 pt above it. AppKit still
owns resizing ([ADR 0002](../adr/0002-native-board-window-resizing.md)).
`⌘0` resets zoom; `⌘W` or the toolbar close button closes.

## Touchpoints
- Opened by every `#capture` feature and [Traceboard documents](traceboard-documents.md)
- Toolbar hosts [Drawing tools](drawing-tools.md), [Tool sizes](tool-sizes.md),
  [Ink colors](ink-colors.md), [Canvas grid](canvas-grid.md),
  [Page background](page-background.md), [Dictation](dictation.md), [Copy trace](copy-trace.md)
- Shown on external displays by [Projection](projection.md)

## Rules
- No title bar, traffic lights, reserved toolbar rows, or permanent bezels.
- Toolbar consumes no screenshot pixels; sizing reserves its band.
- Resizing changes only the window/viewport, never page, shapes, or zoom.
- Empty toolbar chrome drags the window; empty drawing area never does.
- Five outer toolbar dividers; drawing tools use a native separated segmented control.
- Toolbar selection uses the system accent and greys out when inactive.

## FAQ
- **How do I move the board?** Drag empty toolbar space.
- **Resizing didn't zoom.** By design; use pinch/`⌘-`/`⌘+`, `⌘0` to reset.
- **Where are window controls?** Use `⌘W` or the toolbar close button.

## Encoded enforcement
| Rule | Guard |
| --- | --- |
| Native resize, deferred positioning | `RetainedInkProbe.swift › verifyNativeResizeTracking`, `verifyDeferredResizePositioning` |
| Toolbar groups/dividers | `RetainedInkProbe.swift › verifyToolbarGroupLayout`; `TRACE_PRODUCT_TLDRAW_PROBE=framing` |
| Native segmented tools | `TRACE_PRODUCT_TLDRAW_PROBE=framing` |
| Drag regions | Gap — manual check |
