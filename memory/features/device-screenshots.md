# Device screenshots

**Tag:** `#capture`

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
- Desktop source is first and keeps the capture shortcut; devices have none.
- With no open trace, create a blank one; otherwise insert centered in the
  current viewport without changing zoom or replacing the document.
- Capture errors never damage the open trace.
- Unauthorized/offline Android devices appear disabled with a hint.
- Simulators are excluded; ADB/Xcode are never bundled.
- Opening the submenu warms iOS connections (deduped, 10 s cooldown), without
  taking screenshots or keeping a continuous keep-alive.

## FAQ
- **My iPhone is missing.** It must be paired and available; same Wi‑Fi alone is not enough.
- **Android device disabled?** Authorize debugging on the device.
- **Installed ADB but nothing changed?** Restart Trace; tools resolve once per session.
- **Blank Android screenshot?** Secure windows block capture.

## Encoded enforcement
| Rule | Guard |
| --- | --- |
| Parsing, ordering, routing, failures, timeouts | `DeviceScreenshotProbe.swift` (`TRACE_DEVICE_SCREENSHOT_PROBE=1`) |
| Centered insertion in viewport | `WebCanvas/tests/imagePlacement.test.ts` |
