# Image import

**Tag:** `#capture`

## Problem
Existing images (designs, exported screenshots) need the same annotate-and-
narrate flow as live captures.

## Solution
Open images from Finder (**Open With → Trace**), drag them onto a board, or
**Paste image** (`⌘V`). A batch lands together on one canvas
([ADR 0007](../adr/0007-batched-finder-image-import.md)).

## Touchpoints
- Finder Open With; [Board window](board-window.md) drag and drop; Edit → Paste image
- Creates a [Blank trace](blank-trace.md) for Finder batches

## Rules
- One Finder batch → one blank trace, one undoable insert, images arranged
  without overlap and selected.
- Drag and drop uses the same batched layout.
- A single `.traceboard` opens as a document instead ([Traceboard documents](traceboard-documents.md)).
- Any non-image or undecodable file rejects the whole Finder batch.
- Inserted images are fully opaque regardless of Highlighter state.

## FAQ
- **Why did all images land on one canvas?** Batches are intentionally grouped.
- **Paste did nothing?** The clipboard has no image.
- **Can I undo an import?** Yes, the whole batch in one step.

## Encoded enforcement
| Rule | Guard |
| --- | --- |
| Open With registration and policy | `RetainedInkProbe.swift › verifyOpenWithRegistration`, `verifyOpenWithImagePolicy` (`TRACE_OPEN_FILE_PROBE=1`) |
| Paste decoding | `RetainedInkProbe.swift › verifyPasteboardImageDecoding` |
| Non-overlapping layout | `WebCanvas/tests/imagePlacement.test.ts` |
