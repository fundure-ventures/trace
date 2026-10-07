# Neo pen

`#pen`

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
```text
Pen availability
├─ No pen → every product flow remains available without it
└─ Hardware validation → M1 only; other models untested
Pen status
├─ Disconnected → "Pen disconnected"
├─ Connecting → "<name> · Connecting"
└─ Connected → "<name> · <battery>%"
Save Neo strokes
└─ document.json → authoritative strokes, separate from canvas shapes
```

## FAQ
- **Which pens work?** Neo Smartpen M1; others are unvalidated.
- **Does ordinary paper work?** No, Ncode paper is required.
- **Why no pen settings?** They appear once the pen connects.

## Acceptance criteria
- With a calibrated Neo M1 and compatible Ncode paper, drawing on paper
  produces live marks on the board.
- Users can distinguish a disconnected pen, a connecting pen, and a
  connected pen with its name and battery percentage from the status menu.
- Reopening a trace preserves pen strokes alongside mouse-drawn content.
- Without a pen connected, users can still capture, annotate with the
  mouse or trackpad, dictate, and copy a trace.
