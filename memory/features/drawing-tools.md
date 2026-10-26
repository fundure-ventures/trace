# Drawing tools

`#board`

## Problem
Pointing at UI needs a few fast, predictable marks — not a full drawing app.

## Solution
Five tools in the toolbar: **Select** (`V`, or hold `⌘`), **Pen** (`D`),
**Highlighter** (`H`), **Rectangle** (`R`), **Text** (`T`). Double-clicking
empty space with Select also creates text. Undo/Redo live in Edit.
On a Sidecar iPad, Pencil draws with pressure while fingers navigate the
canvas: drag to pan and pinch to zoom. Direct one-finger panning uses the
macOS 27 touch path on the Mac.

## Touchpoints
- [Board window](board-window.md) toolbar
- Sized by [Tool sizes](tool-sizes.md), colored by [Ink colors](ink-colors.md)
- Strokes become numbered markers via [Timed annotations](timed-annotations.md)
- Selection changes what [Copy trace](copy-trace.md) copies

## Rules
Tool chrome follows [ADR 0001](../adr/0001-required-tldraw-product-canvas.md).

```text
Choose drawing tool
└─ Native toolbar only → tldraw UI stays hidden
Hold ⌘
└─ Temporary Select → preserve prior selection until drawing starts
Draw rectangle
└─ Finish → clear selection; keep Rectangle active
Draw with Highlighter
└─ Chosen ink → 50% opacity
Active text editing
├─ Change tool settings → preserve editing
└─ Press Space → type a space
Sidecar canvas input
├─ Pencil → use selected tool and pressure; one stroke per gesture; hide pointer while drawing
├─ Finger drag (macOS 27 Mac) → pan, never draw
├─ Finger tap → leave canvas content unchanged
├─ Pinch → zoom around the gesture in proportion to finger spacing, never draw
└─ Return to Mac mouse → drawing and selection still work
```

## FAQ
- **How do I select without switching tools?** Hold `⌘`.
- **Why isn't my rectangle selected after drawing?** Rectangle is sticky for quick repeats.
- **How do I add text?** `T` then click, or double-click empty space with Select.
- **Does tilting the Pencil change the brush?** Not currently. Pressure changes
  freehand ink; tldraw does not use tilt, rotation, or tangential pressure to
  shape these brushes.

## Acceptance criteria
- Users can choose Select, Pen, Highlighter, Rectangle, and Text from the
  native toolbar or their shortcuts, without a second drawing toolbar.
- Holding `⌘` temporarily enables Select without losing a previous selection
  before drawing starts.
- Drawing one rectangle leaves Rectangle active, ready to draw another.
- Highlighter marks use the chosen ink at 50% opacity.
- Users can create text with the Text tool or a Select double-click, type
  spaces, and change tool settings without interrupting text editing.
- On a touch-capable Sidecar connection, dragging one finger moves the canvas
  without adding marks or moving shapes, even with Pen selected. Tapping a
  finger does not leave a dot.
- Adding a second finger during a pan allows pinch zoom without a sudden
  canvas jump; ending or cancelling the gesture leaves the next drag usable.
- Pinching keeps the content under the gesture anchored while changing zoom,
  without drawing or creating undo entries for shapes.
  On a direct-touch connection, spreading fingers 20% farther apart increases
  zoom by 20%, within the canvas zoom limits; reversing the movement restores
  the original zoom.
- A Pencil stroke creates one editable mark, with pressure variation where
  supported by the brush. It participates in undo, saving, and timed
  annotations like other canvas marks. The Mac pointer is hidden while the
  Pencil is drawing and returns when the stroke ends or is cancelled.
- After finishing or cancelling a Pencil gesture, users can draw and select
  with the Mac mouse without having to toggle a pen-only mode.
