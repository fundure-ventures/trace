# Ink colors

`#board`

## Problem
Fixed red/blue/yellow/green inks can vanish on some backgrounds or clash with
them.

## Solution
Four named inks whose rendered color is derived from the page background, so
they stay legible and in character on any page
([ADR 0008](../adr/0008-background-derived-color-theming.md)).

## Touchpoints
- [Board window](board-window.md) toolbar swatches
- Driven by [Page background](page-background.md)
- Used by [Drawing tools](drawing-tools.md)

## Rules
```text
Choose ink
└─ Toolbar swatch → canonical color; never themed
Document ink
├─ Save → store color name
└─ Reopen → derive appearance from document background
Background theming
└─ Adjust lightness/tint → preserve hue family and named color
```

## FAQ
- **Why does red look different on a dark page?** Inks adapt for contrast.
- **Will my old trace change color?** Only if its page background changes.

## Acceptance criteria
- Users always see the same recognizable red, blue, yellow, and green
  toolbar swatches, regardless of page background.
- Changing the page background adapts drawn ink for legibility while
  preserving each chosen color's identity.
- Saving and reopening a trace preserves the chosen ink names and derives
  their appearance from that document's background.
