# Global shortcuts

**Tag:** `#app`

## Problem
Capturing should be one keystroke from any app, without first clicking the
menu bar.

## Solution
Two user-recordable system-wide shortcuts: **New Blank Trace** and **Capture
Frontmost App**. They are edited in [Setup](setup.md) and mirrored as key
equivalents on the matching File and menu bar items.

## Touchpoints
- Recorded in [Setup](setup.md)
- Triggers [Blank trace](blank-trace.md) and [Screenshot capture](screenshot-capture.md)
- Shown on the desktop source of [Device screenshots](device-screenshots.md)

## Rules
- One shortcut cannot be assigned to both actions ("Already assigned to …").
- Menu items always display the currently recorded shortcut.
- Changing a shortcut updates every menu that shows it, immediately.
- Device screenshot sources never get a shortcut.

## FAQ
- **Can I clear a shortcut?** Yes, in Setup; the action stays in the menu.
- **Why was my shortcut rejected?** It is already used by the other Trace action.
- **Do they work while another app is focused?** Yes, they are global.

## Acceptance criteria
- Users can invoke New Blank Trace and Capture Frontmost App while another
  app is focused.
- Trying to assign the same shortcut to both actions is rejected with an
  explanation naming the other action.
- Changing a shortcut immediately updates every menu entry that shows it.
- Clearing a shortcut leaves the corresponding menu action available;
  device screenshot sources never acquire a shortcut.
