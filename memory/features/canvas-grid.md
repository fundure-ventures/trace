# Canvas grid

`#board`

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
```text
Reference grid
├─ Spacing → 4–64 pt; default 8 pt
├─ Dots/lines → 1 pt at 20% opacity
└─ Any window shape → uniform spacing in board-view points
Copy or export
└─ Output pixels → never include grid
```

## FAQ
- **Will the grid show up when I copy?** No.
- **How do I change spacing quickly?** Focus the spacing field and use ↑/↓.

## Acceptance criteria
- Users can choose None, Dots, Square, Rows, or Cols from the toolbar and
  adjust spacing between 4 and 64 pt, starting at 8 pt.
- Resizing the window preserves uniform spacing and the subtle 1 pt,
  20%-opacity grid marks.
- Copying or exporting a trace never includes the reference grid.
