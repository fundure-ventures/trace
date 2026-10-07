# Image import

`#capture`

## Problem
Existing images (designs, exported screenshots) need the same annotate-and-
narrate flow as live captures.

## Solution
Open images from Finder (**Open With → Trace**), drag them onto a board, or
**Paste image** (`⌘V`). A batch lands together on one canvas
([ADR 0007](../adr/0007-batched-finder-image-import.md)).
`traceapp image.png` inserts images into an open board; when no board is open,
it creates a blank trace.

## Touchpoints
- Finder Open With; [Board window](board-window.md) drag and drop; Edit → Paste image
- Creates a [Blank trace](blank-trace.md) for Finder batches
- [Command-line tool](command-line-tool.md) imports image paths

## Rules
Document opens follow [Traceboard documents](traceboard-documents.md).

```text
Open from Finder
├─ Single .traceboard → open document instead of importing image
└─ Image batch
   ├─ Any non-image or undecodable file → reject whole batch
   └─ Valid batch → one blank trace; one undoable insert
      └─ Images → arranged without overlap and selected
Drag and drop batch
└─ Use same batched layout
CLI image batch
├─ Board open → add batch; never replace board
└─ No board open → create blank trace
Inserted images
└─ Fully opaque regardless of Highlighter state
```

## FAQ
- **Why did all images land on one canvas?** Batches are intentionally grouped.
- **Paste did nothing?** The clipboard has no image.
- **Can I undo an import?** Yes, the whole batch in one step.

## Acceptance criteria
- Opening several images from Finder creates one blank trace containing
  the complete batch, selected and arranged without overlap.
- One Undo removes the entire imported batch; dropping a batch onto a board
  uses the same arrangement.
- A Finder batch containing a non-image or unreadable image is rejected
  rather than partially imported.
- Users can paste an image from the clipboard; inserted images remain
  fully opaque even when Highlighter was the previous tool.
- Opening a single `.traceboard` restores its document instead of treating
  it as an image.
- Running `traceapp image.png` while a board is open adds the image batch to
  that board; without an open board, it creates a blank trace.
