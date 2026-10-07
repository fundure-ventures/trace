# Blank trace

`#capture`

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
```text
New blank trace
├─ Open → use last blank viewport size
└─ Before canvas is ready → paint saved background; no blank flash
Canvas loading
├─ Ready
│  ├─ Reduce Motion off → fade in over 280 ms
│  └─ Reduce Motion on → reveal directly
└─ Failure → show "Canvas unavailable"; never a fallback canvas
```

## FAQ
- **Why is my blank page colored?** It reuses the last page background.
- **Why did it open at that size?** It remembers your last blank viewport.
- **"Canvas unavailable"?** The bundled canvas failed to load; see logs.

## Acceptance criteria
- Creating a blank trace shows the remembered background immediately,
  without flashing a different color while the canvas loads.
- A new blank trace opens at the last-used blank viewport size.
- When the canvas becomes ready, it fades in over 280 ms; with Reduce Motion
  enabled, it appears directly.
- If the canvas cannot load, users see "Canvas unavailable" rather than a
  different drawing surface.
