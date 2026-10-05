# Menu bar agent

**Tag:** `#app`

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
- No dock icon, title bar, or conventional app shell.
- The agent stays alive after every transient window closes.
- Resting glyph `pencil.tip`; active (capturing/annotating) glyph
  `pencil.tip.crop.circle.fill`.
- Pen-only menu sections are hidden while the pen is disconnected.

## FAQ
- **Where is the Trace window?** There is none until you create or open a trace.
- **How do I quit?** Menu bar glyph → **Quit Trace** (`⌘Q`).
- **Why does the icon change?** It shows that a capture or annotation is active.
- **Why are some settings missing?** Pen settings appear only while a pen is connected.

## Encoded enforcement
| Rule | Guard |
| --- | --- |
| Glyph per phase | `RetainedInkProbe.swift › verifyStatusItemPresentation` |
| Pen sections hidden when disconnected | `RetainedInkProbe.swift › verifyAppSettings` |
| Agent survives window close | Gap — no automated check |
