# Command-line tool

**Tag:** `#app`

## Problem
Terminal users need to start a trace, capture a window, import images, and
reuse the current trace without switching to the menu bar for every action.

## Solution
Install `traceapp` from the final section of Setup, then run commands to start
blank or screenshot traces, capture connected devices, open traceboards,
import images into the current board, copy, or export.

## Touchpoints
- [Setup](setup.md) installs or removes the helper
- [Blank trace](blank-trace.md), [Screenshot capture](screenshot-capture.md),
  [Device screenshots](device-screenshots.md), [Image import](image-import.md)
- [Copy trace](copy-trace.md) and [Traceboard documents](traceboard-documents.md)

## Rules
- `traceapp` communicates only with the matching installed Trace app instance;
  Debug and Release builds use separate IPC endpoints.
- A new trace or capture may suppress Dictation for that request with
  `--no-recording`; default Dictation behavior otherwise follows app settings.
- CLI image batches insert into an open board, while a lone `.traceboard`
  opens as a document.
- CLI capture excludes the invoking terminal from frontmost-window selection
  and inserts into an open board without replacing it.
- Capture and document-open commands report success only after the requested
  work finishes; permission, capture, load, and save failures are nonzero
  results while existing UI errors remain visible.
- Device names are resolved against refreshed discovery results for every
  capture request, so newly connected devices work without restarting Trace.
- Each action stays tied to the trace that was open when it began. A changed
  or closed trace fails rather than receiving an unrelated insertion or export.
- Only one CLI action that changes or exports a trace runs at a time; another
  concurrent action returns the documented busy status.
- `copy` copies the whole board and follows the app's close-after-copy setting.
- `export` writes files without closing the board. Dictation formats wait for
  the transcript; image-only operations do not.
- Setup installation never replaces an existing non-symlink file at the
  `traceapp` destination.
- File, usage, unavailable-app, action, and busy failures return documented
  exit codes and do not claim success.

## FAQ
- **How do I install it?** Use Setup → Command-line tool or make a symlink
  from the app's bundled helper.
- **Does image import replace my open trace?** No, CLI imports add images to
  the current board.
- **How do I choose a copy or export format?** Use `--format`; see [CLI.md](../../CLI.md).
- **Does export close my trace?** No. Copy follows the existing close-after-copy setting.

## Acceptance criteria
- From Terminal, `traceapp` opens a blank trace and `traceapp capture` captures
  the app the user came from, with no accidental self-capture of the terminal.
- Device listing and device capture show availability or actionable failure
  information without replacing an existing trace on failure.
- A capture request waits until the new screenshot trace or in-board image is
  actually created, and a failed capture never reports success.
- A CLI image batch adds its images to the open board; a single traceboard
  opens its saved content.
- A traceboard that cannot be loaded, or cannot be opened because the current
  trace failed to save, returns failure and leaves the current trace intact.
- Users can copy the entire board or export supported formats; export files
  are written at the requested location and the board remains open.
- If the target trace changes while a capture or export is being prepared, the
  request fails rather than applying its result to another trace.
- Concurrent CLI actions that could mutate or export a trace return busy
  instead of overlapping.
- When Trace is closed, the helper starts the matching app. The Setup action
  distinguishes a current link from a missing, broken, or conflicting link.
