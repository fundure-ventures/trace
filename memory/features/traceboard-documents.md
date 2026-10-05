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

## FAQ
- **Where are my traces?** `~/Documents/Trace`.
- **Finder opens the wrong Trace?** Launch the current build once ([Troubleshooting](../../TROUBLESHOOTING.md)).
- **Why did reopening zoom out?** It frames all saved shapes.

## Encoded enforcement
| Rule | Guard |
| --- | --- |
| Open lifecycle | `RetainedInkProbe.swift › verifyOpenFileLifecycle` (`TRACE_OPEN_FILE_PROBE=1`) |
| Snapshot persistence, folder migration | `RetainedInkProbe.swift › verifyTldrawSnapshotPersistence`, `verifyDrawingFolderMigration` |
| Reopen framing | `ProductTldrawProbe.swift › verifyOffCenterDocumentFraming` (`TRACE_PRODUCT_TLDRAW_PROBE=framing`) |
