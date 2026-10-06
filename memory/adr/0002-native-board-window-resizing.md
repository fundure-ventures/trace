# Let native AppKit chrome own board resizing

**Status:** Accepted

## Context

Trace should look borderless while retaining reliable system resize edges,
cursors, window constraints, and accessibility. Custom resize regions were
more complex and less reliable. Resetting `contentAspectRatio` after enabling
resizable full-size chrome can crash AppKit on affected macOS versions.

## Decision

Document boards use a visually borderless
`.titled + .resizable + .fullSizeContentView` `NSWindow`. The title, traffic
lights, and separator are hidden, but AppKit owns the frame and resize
interaction.

Resizing changes only the native window and WebKit viewport. Page dimensions,
screenshot geometry, shapes, and camera zoom remain fixed. Onboarding disables
resizing. The board must not set or reset `contentAspectRatio`.

## Consequences

- System resize behavior works without visible conventional window chrome.
- Canvas content fills the frame with no reserved titlebar row.
- Page-space geometry stays stable during non-proportional window resizing.
- Future window changes must preserve the no-`contentAspectRatio` invariant.
