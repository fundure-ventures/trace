# Traceboard documents

**Tag:** `#output`

## Problem
Traces should never be lost, and reopening one should show its content, not an
empty corner of the page.

## Solution
Every trace autosaves as a `.traceboard` package in `~/Documents/Trace`.
**Open traces…** (`⌘O`) reveals the folder; double-clicking a package reopens
it in a board fitted to its content.

## Touchpoints
- File → Open traces…; Finder double-click
- Saved by [Copy trace](copy-trace.md) and on edit
- Contains [Dictation](dictation.md) audio/transcript and [Neo pen](neo-pen.md) strokes

## Rules
- Autosave after 0.6 s idle; save failures are surfaced, never silent.
- Package holds source image, `document.json` (authoritative Neo strokes),
  optional voice/transcript, and `tldraw.json` (canvas state).
- Reopening fits and centers visible shapes; empty documents fall back to the page.
- Opening one `.traceboard` is a document open, not an image import.
- A CLI open reports failure if the package cannot be loaded or the current
  document cannot be saved; the current board and its UI error remain intact.

## FAQ
- **Where are my traces?** `~/Documents/Trace`.
- **Finder opens the wrong Trace?** Launch the current build once ([Troubleshooting](../../TROUBLESHOOTING.md)).
- **Why did reopening zoom out?** It frames all saved shapes.

## Acceptance criteria
- After 0.6 s without edits, a trace autosaves; if saving fails, users are
  informed rather than led to believe their work is safe.
- Users can find saved traces through Open traces and reopen a `.traceboard`
  with its source image, pen strokes, canvas content, and any audio/transcript.
- Reopening centers and fits all visible saved shapes, including content
  beyond the original page; an empty trace frames the page instead.
- Opening a single `.traceboard` restores the document rather than adding
  it as an imported image.
- Running `traceapp path.traceboard` reports a failure for corrupt or
  unloadable packages and when saving the current trace fails, without
  replacing the current board.
