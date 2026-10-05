# Canvas grid

**Tag:** `#board`

## Problem
Aligning marks or sketching layouts is easier with a reference grid, but a grid
must never pollute the shared image.

## Solution
A toolbar segmented control picks None, Dots, Square, Rows, or Cols, with a
spacing field (↑/↓). The grid adapts black/white to the content beneath
([ADR 0003](../adr/0003-metal-only-isotropic-grid.md)).

## Touchpoints
- [Board window](board-window.md) toolbar
- Contrast follows [Page background](page-background.md) and screenshot content

## Rules
- Spacing 4–64 pt (default 8); 1 pt dots/lines at 20% opacity.
- Never appears in copied/exported pixels.
- Uniform in board-view points regardless of window shape.

## FAQ
- **Will the grid show up when I copy?** No.
- **How do I change spacing quickly?** Focus the spacing field and use ↑/↓.

## Acceptance criteria
- Users can choose None, Dots, Square, Rows, or Cols from the toolbar and
  adjust spacing between 4 and 64 pt, starting at 8 pt.
- Resizing the window preserves uniform spacing and the subtle 1 pt,
  20%-opacity grid marks.
- Copying or exporting a trace never includes the reference grid.
