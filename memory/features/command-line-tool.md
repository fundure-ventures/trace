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
- `copy` copies the whole board and follows the app's close-after-copy setting.
- `export` writes files without closing the board. Dictation formats wait for
  the transcript; image-only operations do not.
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
- A CLI image batch adds its images to the open board; a single traceboard
  opens its saved content.
- Users can copy the entire board or export supported formats; export files
  are written at the requested location and the board remains open.
- When Trace is closed, the helper starts the matching app. The Setup action
  distinguishes a current link from a missing, broken, or conflicting link.
