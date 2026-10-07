# Tool sizes

`#board`

## Problem
A fine pen line and a broad highlight need very different widths; resetting
size on every tool switch wastes time.

## Solution
One toolbar slider adjusts the active tool: Pen 1–12 pt, Highlighter
16–124 pt, Text font 12–124 pt. Rectangle outlines reuse the Pen width.

## Touchpoints
- [Board window](board-window.md) toolbar slider
- Applies to [Drawing tools](drawing-tools.md)

## Rules
```text
Adjust active tool size
├─ Values → whole points only
├─ Pen → 1–12 pt
├─ Highlighter → 16–124 pt
├─ Text → 12–124 pt; label "Font size"; independent of stroke widths
└─ Rectangle → reuse Pen width; preserve geometry at both ends of range
Switch tool or restart Trace
└─ Restore each tool's own remembered size
```

## FAQ
- **Why did my highlighter size not change with the pen?** Sizes are per tool.
- **How do I resize a rectangle outline?** Change the Pen width.
- **Does text size change existing text?** It applies to the active/edited text.

## Acceptance criteria
- Users can choose whole-point Pen widths from 1 to 12 pt, Highlighter
  widths from 16 to 124 pt, and Text sizes from 12 to 124 pt.
- Switching tools and restarting Trace preserve each tool's chosen size
  independently.
- Selecting Text changes the slider label to "Font size" without changing
  either stroke-width setting.
- Rectangle outlines use the Pen width without changing the rectangle's
  geometry at either end of the width range.
