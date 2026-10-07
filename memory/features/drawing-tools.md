# Drawing tools

`#board`

## Problem
Pointing at UI needs a few fast, predictable marks — not a full drawing app.

## Solution
Five tools in the toolbar: **Select** (`V`, or hold `⌘`), **Pen** (`D`),
**Highlighter** (`H`), **Rectangle** (`R`), **Text** (`T`). Double-clicking
empty space with Select also creates text. Undo/Redo live in Edit.

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
```

## FAQ
- **How do I select without switching tools?** Hold `⌘`.
- **Why isn't my rectangle selected after drawing?** Rectangle is sticky for quick repeats.
- **How do I add text?** `T` then click, or double-click empty space with Select.

## Acceptance criteria
- Users can choose Select, Pen, Highlighter, Rectangle, and Text from the
  native toolbar or their shortcuts, without a second drawing toolbar.
- Holding `⌘` temporarily enables Select without losing a previous selection
  before drawing starts.
- Drawing one rectangle leaves Rectangle active, ready to draw another.
- Highlighter marks use the chosen ink at 50% opacity.
- Users can create text with the Text tool or a Select double-click, type
  spaces, and change tool settings without interrupting text editing.
