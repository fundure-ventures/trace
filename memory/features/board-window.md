# Board window

`#board`

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
```text
Board presentation
├─ Window → no title bar, traffic lights, reserved toolbar rows, or permanent bezels
└─ Floating toolbar → reserve its band; consume no screenshot pixels
Resize board
└─ Change window/viewport only → preserve page, shapes, and zoom
Drag empty space
├─ Toolbar chrome → move window
└─ Drawing area → never move window
Toolbar controls
├─ Structure → five outer dividers; native separated drawing-tool segments
└─ Selection
   ├─ Board active → system accent
   └─ Board inactive → grey
```

## FAQ
- **How do I move the board?** Drag empty toolbar space.
- **Resizing didn't zoom.** By design; use pinch/`⌘-`/`⌘+`, `⌘0` to reset.
- **Where are window controls?** Use `⌘W` or the toolbar close button.

## Acceptance criteria
- Users see their content and a floating toolbar above it, without a title
  bar, traffic lights, or a permanent frame covering the screenshot.
- Resizing the board changes the visible viewport without resizing marks,
  changing the page, or changing zoom.
- Dragging empty toolbar space moves the board; dragging empty canvas space
  does not move the window.
- Drawing tools appear as separated native segments, with five outer
  dividers organizing the toolbar.
- Selected toolbar controls follow the system accent while active and
  become grey when the board is inactive.
