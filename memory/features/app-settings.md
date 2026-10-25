# App settings

`#app`

## Problem
People use Trace in different rhythms: pen-driven bursts, keyboard copy-paste,
or narrated walkthroughs. One fixed behavior fits none of them.

## Solution
The menu bar **Settings** submenu groups behavior by moment:
- **Pencil:** Pick up to capture and open; Put down to copy. Both apply to
  Neo Smartpen cap/connection changes and configured Apple Pencil devices.
  Checked device rows choose which pens Trace watches.
- **Copy:** Close window after copy; **Format** (image and dictation, image,
  dictation, `.pdf`).
- **Dictation:** Start dictation automatically; Annotation scale
  (Small 75%, Medium 100%, Large 150%).
- **Launch in menu bar at login.**
- Each configured iPad appears by name followed by **Apple Pencil**.

## Touchpoints
- [Menu bar agent](menu-bar-agent.md) → Settings
- Changes [Copy trace](copy-trace.md) wording and close behavior
- Configures [Dictation](dictation.md) and [Timed annotations](timed-annotations.md)
- Drives [Neo pen](neo-pen.md) cap/disconnect reactions

## Rules
```text
Change settings
└─ Relaunch Trace → chosen values persist
Copy settings
├─ Format choices → same list as toolbar copy options
└─ Close window after copy
   ├─ Enabled → Edit menu reads "Copy trace and close"
   └─ Disabled → Edit menu reads "Copy trace"
Pencil section
├─ Presentation → muted "Pencil" heading, shared actions, checked device rows
├─ Disconnected device → keep controls available
├─ Pick up to capture and open → same preference for Neo and Apple Pencil
├─ Put down to copy → copy whole trace using Copy format
│  └─ Close window after copy → sole setting deciding whether copy closes board
├─ Neo Smartpen → uncheck to stop Bluetooth discovery and disconnect
├─ Configured iPad Apple Pencil → uncheck to stop its listener
├─ Multiple configured iPads → independent device checks; remember all devices
├─ All devices unchecked → no background pen watching
└─ iPad temporarily unavailable → retain device; explain status in its tooltip
```

## FAQ
- **Why does `⌘C` close my board?** "Close window after copy" is on under Copy.
- **Can the pen cap start a capture?** Yes: Pencil → Pick up to capture and open.
- **How do I copy only the transcript?** Copy → Format → Copy dictation.
- **Can putting down a pen copy but keep the trace open?** Enable Put down
  to copy and disable Copy → Close window after copy.
- **How do I stop watching one iPad?** Untick its Apple Pencil device row.

## Acceptance criteria
- Users can reach Settings directly from Trace's status-bar menu.
- After changing settings and restarting Trace, users find their chosen
  values unchanged.
- Copy format choices are available consistently in Settings and the
  toolbar's copy-options menu.
- Changing "Close window after copy" immediately updates the Edit menu to
  describe whether copying will close the trace.
- Pencil controls remain available when no device is connected, allowing users
  to re-enable a disabled device.
- Configuring an iPad adds its named Apple Pencil device row without removing
  previously configured iPads. Each row retains its checked state after relaunch.
- Disabling one device stops its watcher without disabling other devices.
  Disabling every device stops all normal Bluetooth discovery and iPad listeners.
  Disabling is not a put-down event: it does not copy or close the trace.
- With Put down to copy enabled, returning an Apple Pencil to its magnetic
  charger or disconnecting/capping the Neo pen copies the open trace. With
  Close window after copy disabled, that copied trace stays open; with it
  enabled, the trace closes after copying succeeds.
- When a configured iPad becomes unreachable, its device row remains available
  with a tooltip explaining the connection problem.
