# Neo pen

**Tag:** `#pen`

## Problem
Pointing with a mouse is imprecise and unnatural while talking; drawing on
paper is natural but disconnected from the screen.

## Solution
A Neo Smartpen M1 (`NWP-F50`) on Ncode paper draws live onto the board over
Bluetooth. The menu bar shows the pen and battery, and exposes pen settings:
Blip Sound, Hover Mode, Store Drawings in Pen Memory, Auto Power On, Power
Off with Cap, Auto Power Off, Pressure Sensitivity.

## Touchpoints
- [Menu bar agent](menu-bar-agent.md) pen status and Pen submenu
- Requires [Pen calibration](pen-calibration.md); enables [Pen hover cursor](pen-hover-cursor.md)
- Cap/disconnect reactions in [App settings](app-settings.md)
- Strokes join [Timed annotations](timed-annotations.md)

## Rules
- The pen is optional; every product flow works without it.
- Status reads `Pen disconnected`, `<name> · Connecting`, or `<name> · <battery>%`.
- Neo strokes are authoritative in `document.json`, separate from canvas shapes.
- Only the M1 is validated; other models are untested.

## FAQ
- **Which pens work?** Neo Smartpen M1; others are unvalidated.
- **Does ordinary paper work?** No, Ncode paper is required.
- **Why no pen settings?** They appear once the pen connects.

## Encoded enforcement
| Rule | Guard |
| --- | --- |
| Transport and input protocol | `swift run neo-transport-tests`, `swift run neo-input-tests` |
| Stroke processing | `swift run trace-stroke-processing-tests` |
| Menu title | Gap — `TracePenMenuPresentation` has no direct check |
