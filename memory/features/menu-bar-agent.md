# Menu bar agent

`#app`

## Problem
Annotating a screenshot should not require launching, arranging, or quitting a
conventional app. A dock icon and main window would compete with the app being
explained.

## Solution
Trace lives as one `pencil.tip` glyph in the menu bar (`LSUIElement`). The
glyph fills in while capturing or annotating. Its menu exposes pen status,
creation actions, [Settings](app-settings.md), [Projection](projection.md),
and **Quit Trace**. Boards are transient windows; closing every board leaves
the agent running.

## Touchpoints
- Entry point for [Screenshot capture](screenshot-capture.md),
  [Blank trace](blank-trace.md), [Device screenshots](device-screenshots.md)
- Hosts [Neo pen](neo-pen.md) status and settings, [App settings](app-settings.md),
  [Projection](projection.md), [Setup](setup.md)
- Can start at login ([App settings](app-settings.md))

## Rules
```text
Trace agent
├─ Presentation → no Dock icon, title bar, or conventional app shell
└─ Close every transient window → agent stays running
Status-bar glyph
├─ Resting → pencil.tip
└─ Capturing/annotating → pencil.tip.crop.circle.fill
Pen-only menu sections
├─ Pen connected → visible
└─ Pen disconnected → hidden
```

## FAQ
- **Where is the Trace window?** There is none until you create or open a trace.
- **How do I quit?** Menu bar glyph → **Quit Trace** (`⌘Q`).
- **Why does the icon change?** It shows that a capture or annotation is active.
- **Why are some settings missing?** Pen settings appear only while a pen is connected.

## Acceptance criteria
- Users can reach Trace from the status bar without a Dock icon or a
  permanent main window.
- After closing every board and transient window, the status-bar menu
  remains available to start another trace.
- The status-bar glyph visibly changes while capturing or annotating and
  returns to its resting appearance otherwise.
- Pen-only menu sections appear when a pen connects and disappear when it
  disconnects.
