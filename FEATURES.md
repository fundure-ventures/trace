# Features

Trace's user-facing behavior, one file per feature in
[`memory/features/`](memory/features/). Each file is the source of truth for
*what* the feature does and *which rules must not regress*. Implementation
rationale lives in [ADRs](memory/adr/README.md).

## Tags

| Tag | UX surface |
| --- | --- |
| `#app` | Menu bar agent, settings, setup, and system integration |
| `#capture` | Ways to start a trace |
| `#board` | The trace window, its toolbar, and the canvas |
| `#voice` | Dictation and its link to marks |
| `#output` | Copying, saving, and reopening traces |
| `#pen` | Neo Smartpen hardware input |

## Inventory

| Feature | Tag | Summary |
| --- | --- | --- |
| [Menu bar agent](memory/features/menu-bar-agent.md) | `#app` | Trace lives in the menu bar, with no dock icon or app shell |
| [Setup](memory/features/setup.md) | `#app` | One panel for permissions, pen, Dictation key, and shortcuts |
| [Global shortcuts](memory/features/global-shortcuts.md) | `#app` | System-wide New Blank Trace and Capture Frontmost App |
| [App settings](memory/features/app-settings.md) | `#app` | Pen, copy, Dictation, and login behavior |
| [Projection](memory/features/projection.md) | `#app` | Mirror or Project a trace on an external display |
| [Screenshot capture](memory/features/screenshot-capture.md) | `#capture` | Capture the frontmost window 1:1 into a board |
| [Blank trace](memory/features/blank-trace.md) | `#capture` | Start from an empty page |
| [Device screenshots](memory/features/device-screenshots.md) | `#capture` | Capture Android and iOS devices directly |
| [Image import](memory/features/image-import.md) | `#capture` | Open, drop, or paste images onto a canvas |
| [Board window](memory/features/board-window.md) | `#board` | Borderless window with one floating toolbar |
| [Drawing tools](memory/features/drawing-tools.md) | `#board` | Select, Pen, Highlighter, Rectangle, Text |
| [Tool sizes](memory/features/tool-sizes.md) | `#board` | Per-tool stroke width and font size |
| [Ink colors](memory/features/ink-colors.md) | `#board` | Four inks derived from the page background |
| [Page background](memory/features/page-background.md) | `#board` | Per-document page color |
| [Canvas grid](memory/features/canvas-grid.md) | `#board` | Adaptive reference grid, never exported |
| [Dictation](memory/features/dictation.md) | `#voice` | Narrate while annotating |
| [Timed annotations](memory/features/timed-annotations.md) | `#voice` | Numbered marks matched to spoken words |
| [Copy trace](memory/features/copy-trace.md) | `#output` | One-keystroke image + transcript copy |
| [Traceboard documents](memory/features/traceboard-documents.md) | `#output` | Autosaved, reopenable `.traceboard` packages |
| [Neo pen](memory/features/neo-pen.md) | `#pen` | Draw on Ncode paper with a Neo Smartpen |
| [Pen calibration](memory/features/pen-calibration.md) | `#pen` | Map paper coordinates onto the page |
| [Pen hover cursor](memory/features/pen-hover-cursor.md) | `#pen` | See where a hovering pen will land |

## Feature file format

Every `memory/features/<feature-name>.md` uses these sections, in order:

1. `# Feature name`
2. `**Tag:**` one tag from the table above
3. `## Problem` — the UX problem it solves
4. `## Solution` — how the UX solves it
5. `## Touchpoints` — features it is reached from or leads to, as links
6. `## Rules` — UX invariants that must not regress
7. `## FAQ` — 3–5 common questions
8. `## Encoded enforcement` — `Rule | Guard` table mapping each rule to the
   probe, test, or lint that fails when it regresses. Mark unguarded rules
   `Gap` rather than omitting them.

## Testing philosophy

Tests exist to enforce **Rules**, not to freeze implementation details. A good
guard fails only when a listed rule breaks, and names that rule. Prefer one
behavioral probe per rule over many assertions on internal values. When a test
needs frequent updates that do not correspond to a rule change, it is guarding
the wrong thing: rewrite it against the rule or delete it.
