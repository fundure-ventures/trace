# Pen hover cursor

`#pen`

## Problem
With the pen above paper, you cannot see where it will land on screen.

## Solution
When Hover Mode is on, a subtle magnifying circle follows the hovering
pen on the board.

## Touchpoints
- Enabled from [Neo pen](neo-pen.md) → Hover Mode
- Needs [Pen calibration](pen-calibration.md) and an open [board](board-window.md)

## Rules
```text
Hover cursor eligibility
├─ Hover Mode on, annotating, compatible page → show cursor
└─ Any condition missing → do not show cursor
Visible cursor
├─ Ring → 24 diameter; 2 stroke; 2× magnification; 20% opacity
├─ Movement below 1.5 px → ignore jitter
└─ Idle for 0.5 s → hide
Reconnect pen
└─ Reapply remembered Hover Mode choice
```

## FAQ
- **No circle?** Enable Hover Mode and calibrate.
- **Circle disappears.** It hides after half a second without movement.

## Acceptance criteria
- With Hover Mode enabled, an open trace, and compatible calibrated paper,
  users see a magnifying circle following the hovering pen.
- Disabling Hover Mode or using an incompatible page prevents that cursor
  from appearing.
- Tiny movements below 1.5 px do not jitter the cursor; half a second
  without movement hides it.
- Disconnecting and reconnecting the pen preserves the user's Hover Mode
  choice.
