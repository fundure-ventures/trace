# Drawing tools

**Tag:** `#board`

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
- Native toolbar is the only tool chrome; tldraw UI stays hidden
  ([ADR 0001](../adr/0001-required-tldraw-product-canvas.md)).
- Holding `⌘` is temporary Select; selections made before `⌘` are preserved
  until drawing starts.
- Rectangle is sticky: after drawing, selection clears and Rectangle stays active.
- Highlighter is the same ink at 50% opacity.
- Changing tool settings never interrupts active text editing; Space inside text types a space.

## FAQ
- **How do I select without switching tools?** Hold `⌘`.
- **Why isn't my rectangle selected after drawing?** Rectangle is sticky for quick repeats.
- **How do I add text?** `T` then click, or double-click empty space with Select.

## Encoded enforcement
| Rule | Guard |
| --- | --- |
| Tool controls and shortcuts | `RetainedInkProbe.swift › verifyDrawingToolControls` |
| Text creation/editing, spaces | `ProductTldrawProbe.swift › verifyTextEditing` (`TRACE_PRODUCT_TLDRAW_PROBE=text`) |
| Sticky rectangle | Gap — no automated check |
