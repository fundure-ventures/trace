# Require the hidden-UI tldraw product canvas

**Status:** Accepted

## Context

Trace needs editable freehand and geometric shapes, image insertion, selection,
undo, persistence, and export without exposing a second product toolbar.
Maintaining a native product renderer alongside tldraw created divergent
behavior and failure paths.

## Decision

The product canvas uses the bundled hidden-UI tldraw renderer in debug and
release. Trace's native toolbar remains the only product chrome and maps its
tools and styles into tldraw.

Native ink is retained only as a DEBUG probe harness. If the web bundle,
navigation, snapshot, or bridge fails, Trace presents **Canvas unavailable**
and logs the reason. It does not silently switch renderers.

## Consequences

- The packaged app must contain a valid `WebCanvas` build.
- Product behavior has one renderer contract across build configurations.
- Renderer failures are explicit instead of producing a success-shaped but
  behaviorally different canvas.
- Native and PaperKit rendering can still be compared in Input Lab without
  becoming product fallbacks.
