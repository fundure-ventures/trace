# Screenshot capture

`#capture`

## Problem
Explaining something on screen starts with a clean, exact picture of the app
in question, without cropping or window-hunting.

## Solution
**New Screenshot trace** (or the Capture Frontmost App shortcut, or capping the
Neo pen) captures the frontmost app window at 1:1 point size and plays a short
Monochrome Flash transition from the window's position into a new
[board](board-window.md).
`traceapp capture` captures the window the user came from; with a board open,
the screenshot is inserted there instead of replacing it.

In experimental debug builds, a configured iPad can use Pencil pickup to
capture the Mac window, connect Sidecar, and fill its screen with the editable
board. Returning the Pencil brings that same board back to the Mac.

## Touchpoints
- [Menu bar agent](menu-bar-agent.md) and File → New Screenshot trace
- [Global shortcuts](global-shortcuts.md) → Capture Frontmost App
- [Neo pen](neo-pen.md) cap-off when enabled in [App settings](app-settings.md)
- Becomes a source submenu when [Device screenshots](device-screenshots.md) are available
- [Command-line tool](command-line-tool.md) capture

## Rules
Permissions are managed in [Setup](setup.md). The single transition follows
[ADR 0004](../adr/0004-single-monochrome-capture-transition.md).

```text
Capture frontmost window
├─ Prerequisite → Screen Recording permission
├─ Size → preserve 1:1 point size whenever screen bounds permit
└─ Captured image → fully opaque, even after Highlighter use
Reveal board and toolbar
├─ Reduce Motion off → Monochrome Flash only; no effect selector
└─ Reduce Motion on → reveal directly
CLI capture
├─ Choose source → skip invoking terminal
├─ Board open → insert at viewport center; preserve document and zoom
└─ Result
   ├─ Screenshot trace or image insert complete → success
   └─ Permission or capture failure → failure; never claim success
```

Experimental debug builds also support a Pencil capture workflow:

```text
Experimental Pencil capture
├─ Prerequisites → validated wireless iPad setup and enabled setting
├─ Pickup → capture first; then connect Sidecar and show editable board on iPad
├─ Initial state or repeated identical messages → no extra captures
└─ Return to iPad charger
   ├─ Board on iPad → bring same document back to Mac; preserve edits
   └─ Connection pending → do not move board to iPad after return
```

## FAQ
- **Which window is captured?** The frontmost app's window.
- **Why is it the same size as the original?** 1:1 keeps text and UI legible.
- **Can I disable the animation?** Enable macOS Reduce Motion.
- **Capture failed?** Check Screen Recording permission in Setup.

## Acceptance criteria
- Capturing the frontmost app creates a trace of its window at 1:1 point
  size whenever the display has enough room.
- Normal capture uses the single Monochrome Flash transition; users are
  not asked to choose an effect.
- With Reduce Motion enabled, the board and toolbar appear directly.
- Capture requires Screen Recording permission, which users can address
  from Setup.
- A screenshot remains fully opaque even if Highlighter was used before
  the capture.
- Running `traceapp capture` from a terminal captures the app the user came
  from; if a board is open, its screenshot is inserted without replacing the
  document.
- A CLI capture does not report success while screen capture is still pending;
  permission or capture failures are reported as failures.
- In the experimental debug workflow, picking up the Pencil captures the Mac
  app before connecting Sidecar, then opens the editable board across the iPad
  screen. Returning the Pencil moves the same board back without copying,
  closing, or losing its annotations.
- Starting or reconnecting the Pencil monitor does not itself create a
  screenshot, and repeated messages for the same state create no extra board.
