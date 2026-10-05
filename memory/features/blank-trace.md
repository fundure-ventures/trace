# Blank trace

**Tag:** `#capture`

## Problem
Sometimes there is nothing to capture: a sketch, a diagram, or a place to
collect pasted images.

## Solution
**New Blank trace** opens an empty page in the last-used background color and
viewport size. The native board paints the background instantly, then fades in
the canvas when ready ([ADR 0005](../adr/0005-native-first-blank-page-loading.md)).

## Touchpoints
- [Menu bar agent](menu-bar-agent.md), File → New Blank trace, [Global shortcuts](global-shortcuts.md)
- Created implicitly by [Image import](image-import.md) and [Device screenshots](device-screenshots.md)
- Background from [Page background](page-background.md)

## Rules
- No blank flash: the saved background paints before the canvas is ready.
- Canvas fades in over 280 ms; Reduce Motion reveals directly.
- Remembers the last blank viewport size.
- Renderer failure shows **Canvas unavailable**, never a fallback canvas.

## FAQ
- **Why is my blank page colored?** It reuses the last page background.
- **Why did it open at that size?** It remembers your last blank viewport.
- **"Canvas unavailable"?** The bundled canvas failed to load; see logs.

## Encoded enforcement
| Rule | Guard |
| --- | --- |
| Viewport persistence | `RetainedInkProbe.swift › verifyBlankViewportPersistenceAndCalibration` |
| Presentation defaults | `RetainedInkProbe.swift › verifyDocumentPresentationDefaults` |
| No silent renderer fallback | `RetainedInkProbe.swift › verifyProductCanvasPolicy` |
