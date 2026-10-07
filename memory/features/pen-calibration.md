# Pen calibration

`#pen`

## Problem
Pen coordinates on paper must map exactly onto the screenshot, or marks land in
the wrong place.

## Solution
A guided corner-tapping calibration in [Setup](setup.md), stored per paper
profile and applied to compatible pages.

## Touchpoints
- [Setup](setup.md) → Start calibration / Calibration
- Required by [Neo pen](neo-pen.md) drawing and [Pen hover cursor](pen-hover-cursor.md)

## Rules
```text
Guided calibration
├─ Any point → "Cancel calibration" available
└─ Saved calibration → per paper profile; survives restarts
Map compatible page
└─ Aspect-fit → keep exact page
```

## FAQ
- **Marks are offset.** Recalibrate from Setup.
- **Do I recalibrate each launch?** No, it is saved.

## Acceptance criteria
- Users can start or repeat guided calibration from Setup and cancel it
  at any point.
- After restarting Trace, the same paper profile uses its saved calibration
  without requiring another corner-tapping session.
- Drawing on a compatible calibrated page places marks at the corresponding
  board positions without stretching the page out of proportion.
