# Import Finder image batches into one canvas

**Status:** Accepted

## Context

Finder can open multiple selected files in one application event. Creating one
Trace document per image loses the user's batch intent and makes comparison or
arrangement unnecessarily expensive.

## Decision

Trace registers as an alternate editor for `public.image`. Opening one or more
decodable image files creates one blank trace, inserts the complete selection
in one tldraw transaction, arranges the images without overlap, and selects the
batch.

Image drag and drop uses the same batched layout behavior.

## Consequences

- A Finder multi-selection becomes one editable visual workspace.
- Import ordering and group selection remain consistent across Open With and
  drag/drop.
- `.traceboard` documents continue to open through their separate owned
  document type.
