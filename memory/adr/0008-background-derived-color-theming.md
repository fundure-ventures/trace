# Derive annotation colors from the page background

**Status:** Accepted

## Context

Trace annotates on top of arbitrary content: captured screenshots and blank
pages whose background color the user picks. Four fixed ink colors (red,
yellow, green, blue) read well on white but lose contrast or clash on dark,
saturated, or same-hue pages. The colors also carry meaning: users pick red
or green for what those colors say, so theming must not turn one ink into
another.

## Decision

### Layers and owners

| Layer | Owner | Colors |
| --- | --- | --- |
| App chrome | AppKit | Semantic system colors; follows macOS appearance |
| Floating toolbar | AppKit | Graphite pill; `controlAccentColor` for selected tools, grid control and focus |
| Toolbar swatches | AppKit | Canonical `TraceRGBAColor` red/blue/yellow/green, never themed |
| Page background | `TraceAppModel` | User-picked per document, remembered for new blank pages (default white) |
| Grid | Metal | Black or white at 20% per fragment ([ADR 0003](0003-metal-only-isotropic-grid.md)) |
| Inks and highlighters | WebCanvas `inkPalette.ts` | Derived from the page background |

### Color identity crosses the bridge as a name

Native code sends tldraw a color *name* (`red`, `yellow`, `green`, `blue`),
never RGB. The rendered color is whatever tldraw's
`DefaultColorThemePalette.lightMode[name].solid` holds. Theming therefore
changes the palette in one place; stored documents keep names, so reopening
a board on another background re-derives its inks.

### Ink derivation

`deriveInkPalette(background)` uses `@basiclines/rampa-sdk` for all color
math. For each ink, starting from tldraw 4.5's light-mode solid as its anchor:

1. **Tint.** Mix 15% of the page into the anchor in Oklab. Inks pick up the
   page's character without changing hue family.
2. **Harmony lean.** Nudge the tinted hue toward the nearest harmony of the
   page's OKLCH hue (offsets 0°, 30°, 90°, 120°, 150°, 180°, 210°, 240°,
   270°, 330°: rampa's analogous, square, triadic, split-complementary and
   complementary angles), clamped to `MAX_HUE_SHIFT` (8°) so each ink keeps
   its meaning. Neutral pages (OKLCH chroma < 0.02) have no hue and are
   skipped.
3. **Contrast.** Measure APCA (`lint`) against the page. Target
   `min(30, 0.6 × best achievable)`, where best achievable is the stronger of
   pure black or white on that page. While below target, step OKLCH lightness
   by 0.01 away from the page (darker on light pages, lighter on dark ones).
   Hue and chroma are preserved.

A missing background is treated as white.

### Highlighter

A highlighter is its ink mixed 25% toward the page in Oklab, drawn at 0.6
opacity so screenshot content stays readable underneath. Highlighter strokes
use tldraw color slots Trace never exposes (`light-red`, `orange`,
`light-green`, `light-blue`), so each ink can have a distinct highlighter
color; `inkNameForColor` maps them back for the toolbar. Image shapes are
created at opacity 1 so the highlighter's next-shape opacity never fades
screenshots.

### Applying the palette

`setCanvasBackground` sets `--tl-color-background` and calls
`applyInkPalette`, which writes the derived solids into tldraw's shared
palette and bumps an atom. Trace's `Draw`, `Geo` and `Text` shape utils
subscribe to that atom, so mounted shapes repaint immediately. Exports read
the same palette, so exported pixels match the canvas.

### Toolbar swatches stay canonical

Swatches show the fixed `TraceRGBAColor` values regardless of background, so
the color a user picks stays recognizable. While Highlighter is active they
render at 0.6 alpha to signal the softer stroke.

## Rejected alternatives

- **Full rampa color harmonies.** Rotating ink hues all the way to
  complementary/triadic/etc. positions of the page hue moved inks too far from their meaning; rampa's
  HSL harmonies also keep the page's saturation and lightness, so neutral
  pages produced grey inks.
- **Themed toolbar swatches.** Mirroring derived inks in the toolbar via a
  WebKit → native palette message made swatches change with every page; fixed
  swatches keep the picked color recognizable.
- **Opaque highlighter.** Mixing 60% of the page into the ink at full opacity
  hid the screenshot content being highlighted.
- **Highlighter blend modes.** Multiply on light pages and screen on dark
  ones let content show through, but needed a custom shape wrapper and
  per-background blend rules; tint plus alpha gives the same look on empty
  page with standard rendering.

## Consequences

- Inks stay legible on any page background with recognizable hue families,
  and lean slightly toward colors that harmonize with the page.
- Changing the background repaints existing annotations and exports
  consistently, with no stored RGB to migrate.
- tldraw's `DefaultColorThemePalette` is mutated globally; the WebCanvas
  hosts one editor, so this is safe today but would need scoping for multiple
  editors.
- rampa-sdk 6.0.0 ships no type declarations and imports Node-only modules;
  WebCanvas keeps a local `.d.ts` and Vite aliases stubbing `module`/`fs`.
- Native `TraceRGBAColor` values and tldraw anchors differ slightly; only the
  name is shared, so the toolbar is a recognizable key, not an exact match.
