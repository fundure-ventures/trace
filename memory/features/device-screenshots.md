# Device screenshots

`#capture`

## Problem
Explaining a phone app means screenshotting on the device, transferring the
file, and opening it — too much friction.

## Solution
When Android (ADB) or paired iOS devices are found, **New Screenshot trace**
becomes a source submenu: `from <frontmost app>.app` first, then
`from <device name>`. Picking a device captures it directly into Trace.

## Touchpoints
- [Menu bar agent](menu-bar-agent.md) and File → New Screenshot trace
- Falls back to [Screenshot capture](screenshot-capture.md) with no devices
- Creates a [Blank trace](blank-trace.md) or inserts into the open [board](board-window.md)

## Rules
```text
Screenshot source menu
├─ Desktop → first; keep capture shortcut
├─ Devices → no shortcuts; exclude simulators
└─ Unauthorized/offline Android → disabled with setup hint
Open submenu
└─ Warm iOS connections → deduped; 10 s cooldown; no screenshot or continuous keep-alive
Capture device
├─ Failure → leave open trace intact
└─ Success
   ├─ No trace open → create blank trace; add screenshot
   └─ Trace open → insert at viewport center; preserve zoom and document
CLI
├─ traceapp capture devices → list connected devices
└─ traceapp capture --device NAME
   ├─ Refresh discovery → include recently connected devices on first request
   └─ Match exact name or identifier, then unique prefix
      ├─ Available unique match → capture device
      └─ Unavailable or ambiguous → reject with device list
Capture tools
└─ ADB/Xcode → never bundled
```

## FAQ
- **My iPhone is missing.** It must be paired and available; same Wi‑Fi alone is not enough.
- **Android device disabled?** Authorize debugging on the device.
- **Installed ADB but nothing changed?** Restart Trace; tools resolve once per session.
- **Blank Android screenshot?** Secure windows block capture.

## Acceptance criteria
- When devices are available, the screenshot menu lists the desktop source
  first with its shortcut, followed by device sources without shortcuts.
- Unauthorized or offline Android devices are disabled with a setup hint;
  simulators do not appear.
- Capturing a device with no trace open creates a blank trace; with a trace
  open, it adds the image at the viewport center without changing zoom or
  replacing existing content.
- A failed device capture leaves the open trace intact.
- A device connected since Trace started appears in the next CLI device
  capture request without requiring an app restart.
- Opening the submenu prepares available iOS connections without taking a
  screenshot; repeated openings within ten seconds do not repeat that work,
  and no continuous keep-alive runs after it.
