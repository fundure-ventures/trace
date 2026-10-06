# App settings

**Tag:** `#app`

## Problem
People use Trace in different rhythms: pen-driven bursts, keyboard copy-paste,
or narrated walkthroughs. One fixed behavior fits none of them.

## Solution
The menu bar **Settings** submenu groups behavior by moment:
- **When pen is connected:** Capture screenshot (on cap off).
- **When pen is disconnected:** copy the open trace and close it.
- **Copy:** Close window after copy; **Format** (image and dictation, image,
  dictation, `.pdf`).
- **Dictation:** Start dictation automatically; Annotation scale
  (Small 75%, Medium 100%, Large 150%).
- **Launch in menu bar at login.**

## Touchpoints
- [Menu bar agent](menu-bar-agent.md) → Settings
- Changes [Copy trace](copy-trace.md) wording and close behavior
- Configures [Dictation](dictation.md) and [Timed annotations](timed-annotations.md)
- Drives [Neo pen](neo-pen.md) cap/disconnect reactions

## Rules
- Settings persist across launches.
- The Copy format list is the same list as the toolbar's copy-options menu.
- The Edit menu reads **Copy trace and close** or **Copy trace** to match the
  close-after-copy setting.
- Pen-dependent sections are hidden while no pen is connected.

## FAQ
- **Why does `⌘C` close my board?** "Close window after copy" is on under Copy.
- **Can the pen cap start a capture?** Yes: When pen is connected → Capture screenshot.
- **How do I copy only the transcript?** Copy → Format → Copy dictation.

## Acceptance criteria
- Users can reach Settings directly from Trace's status-bar menu.
- After changing settings and restarting Trace, users find their chosen
  values unchanged.
- Copy format choices are available consistently in Settings and the
  toolbar's copy-options menu.
- Changing "Close window after copy" immediately updates the Edit menu to
  describe whether copying will close the trace.
- With no pen connected, pen-dependent settings are hidden; connecting a pen
  makes them available.
