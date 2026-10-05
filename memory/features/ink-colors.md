# Ink colors

**Tag:** `#board`

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
- Toolbar swatches always show canonical colors, never themed ones.
- Documents store color names; reopening on another background re-derives inks.
- Inks keep their hue family; theming changes lightness/tint, never the named color.

## FAQ
- **Why does red look different on a dark page?** Inks adapt for contrast.
- **Will my old trace change color?** Only if its page background changes.

## Encoded enforcement
| Rule | Guard |
| --- | --- |
| Derivation, contrast, hue lean | `WebCanvas/tests/inkPalette.test.ts` |
| Visible ink layers | `RetainedInkProbe.swift › verifyVisibleInkLayers` |
