# Projection

`#app`

## Problem
When presenting on a projector or TV, the audience should see the trace, not
the presenter's desktop, and the presenter should control when it appears.

## Solution
For each extra display the menu bar offers **System preference** (macOS
mirrored/extended), **Mirror** (show the open trace), or **Project** (black
until a trace is activated, then the trace without the editor).

## Touchpoints
- [Menu bar agent](menu-bar-agent.md) projection section
- Shows the current [Board window](board-window.md) content

## Rules
```text
Display options
├─ One display → no projection options
└─ Extra displays → offer targets; never include working display
Choose Mirror or Project
└─ One target only → every other display stays System
Output mode
├─ Mirror → show open trace
└─ Project
   ├─ No document activated → black
   └─ Document activated → show trace; hide editor
Output presentation
├─ Content → aspect-fit and centered
├─ HDMI / AirPlay → identical behavior
└─ Keep display awake → only while showing a document
```

## FAQ
- **Why is the projector black?** Project mode waits for a trace to be activated.
- **Mirror vs Project?** Mirror shows the trace whenever one is open; Project waits.
- **No options in the menu?** Only one display is connected.

## Acceptance criteria
- With an extra display connected, users can choose System, Mirror, or
  Project for it; the working display is never offered as a target.
- Selecting Mirror or Project for one display returns all other displays
  to System mode.
- Mirror shows an open trace; Project shows black until a trace is activated
  and then shows the trace without its editor.
- The trace fits and centers on the output without distortion, with the
  same behavior over HDMI or AirPlay.
- The output is kept awake while showing a trace, not while idle.
