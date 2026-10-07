# Command-line tool

`#app`

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
```text
Run traceapp
├─ App connection → matching installed instance only; separate Debug/Release IPC endpoints
└─ Action that changes or exports a trace
   ├─ Another such action running → documented busy status
   └─ Target trace changed or closed after action began → fail; never affect another trace
New trace or capture
├─ --no-recording → suppress Dictation for this request
└─ Otherwise → follow app Dictation settings
Open paths
├─ Image batch → insert into open board
└─ Lone .traceboard → open as document
Capture
├─ Desktop → exclude invoking terminal; insert into open board without replacing it
└─ Device → refresh discovery before resolving name; no restart for newly connected devices
Copy
└─ Whole board → follow close-after-copy setting
Export
├─ Write files → keep board open
└─ Format
   ├─ Includes Dictation → wait for transcript
   └─ Image only → do not wait for transcript
Capture or document open
├─ Requested work complete → report success
└─ Permission, capture, load, or save failure → nonzero result; keep UI error visible
Other failures
└─ File, usage, unavailable-app, action, or busy → documented exit code; never claim success
Install from Setup
└─ Existing non-symlink file at destination → preserve it; never replace
```

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
