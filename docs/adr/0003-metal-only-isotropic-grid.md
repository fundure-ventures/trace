# Render the grid only with Metal in board-view points

**Status:** Accepted

## Context

Trace grids must remain square and optically consistent while the board
viewport resizes. Source-image UV coordinates stretch under non-proportional
resize and are therefore unsuitable for grid geometry. Grid contrast also has
to adapt across light and dark captured content.

## Decision

All active grid styles render in a transparent pass-through `MTKView`. Geometry
uses isotropic board-view points; texture UVs are used only to sample the
underlying content.

Spacing is clamped to 4–64 pt. Dots are 1 pt in diameter, lines are 1 pt wide,
and all styles use 20% opacity. Each fragment uses Rec. 709 luminance weights
to choose black over light content or white over dark content. There is no
CPU/AppKit grid fallback.

## Consequences

- Grid cells and dots retain their shape during window resize.
- Contrast can vary correctly across one captured image.
- Grid rendering requires a working Metal pipeline.
- The grid remains a non-interactive, non-persisted, non-exported overlay.
