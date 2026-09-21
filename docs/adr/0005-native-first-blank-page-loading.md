# Paint blank pages natively until tldraw is ready

**Status:** Accepted

## Context

Blank documents previously risked showing a transparent or unfinished WebKit
surface while the bundled canvas initialized. The saved page color is already
known before the renderer is ready.

## Decision

For a blank document, the native board root immediately paints the saved
background color. The tldraw WebView remains hidden until it reports that the
document is ready.

After readiness, WebKit fades in over 280 ms and the toolbar uses the same
`-20 pt` entrance as screenshot capture. Reduced Motion reveals both directly.
Renderer failure remains visible as **Canvas unavailable**.

## Consequences

- Blank pages have the correct color from their first visible frame.
- Loading does not flash transparent WebKit content.
- Blank and captured documents share toolbar motion without sharing their
  renderer-readiness gates.
