# Features

Trace's user-facing behavior, one file per feature in
[`memory/features/`](memory/features/).
Each file is the source of truth for
*what* the feature does and *which rules must not regress*.

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
8. `## Acceptance criteria` — explanatory, observable scenarios describing
   what users must be able to do and what must happen. Rules state the
   invariant; acceptance criteria show how to recognize it in use.
   Write these independently of the implementation: no test filenames,
   symbols, commands, coverage claims, or `Gap` bookkeeping.

## Documentation principles

- Describe one coherent user-facing capability per file, using a stable
  kebab-case filename in `memory/features/`.
- Explain the user's problem and workflow, not classes, bridges, or algorithms.
  Keep implementation rationale in [ADR.md](ADR.md), engineering practice in
  [DEVELOPMENT.md](DEVELOPMENT.md), and design guidance in [DESIGN.md](DESIGN.md).
- Use one existing top-level tag for the primary UX surface. Link related
  features by name under Touchpoints instead of duplicating their contracts.
- Keep Rules durable and Acceptance criteria observable. Include entry points,
  persistence, errors, and relevant edge cases when they affect the user.
- Describe shipped behavior verified against the app. Clearly distinguish
  proposals from existing capabilities; do not turn examples into requirements.
- Update the file and inventory in the same change as the feature. Remove both
  when the feature is removed.

## Before changing behavior

1. Find the affected features in the inventory and read their files.
2. Treat each **Rule** as a requirement. If the change breaks one, confirm with
   the user before proceeding and update the rule explicitly.
3. Find relevant decisions in [ADR.md](ADR.md) and read linked ADRs before
   changing an implementation they cover.

## After changing behavior

- Update the feature file in the same change: Solution, Touchpoints, Rules,
  FAQ, and Acceptance criteria must match the shipped behavior.
- New user-facing feature: add `memory/features/<feature-name>.md` and an
  inventory row here. Removed feature: delete both.
- New rule: describe its observable outcome under Acceptance criteria and add
  an appropriate guard (probe, test, or lint). If a guard is missing, disclose
  that in the change description, not in the feature's UX contract.
- New durable implementation decision: follow the template and principles in
  [ADR.md](ADR.md), add the record in `memory/adr/`, and update its inventory.
- Keep feature files UX-focused. Commands and engineering practice belong in
  [DEVELOPMENT.md](DEVELOPMENT.md); visual guidelines belong in [DESIGN.md](DESIGN.md).
- Keep Acceptance criteria independent of test filenames, symbols, and
  coverage status. They describe what users should experience, not how the
  repository currently checks it.

## Feature template

Copy this structure into `memory/features/<feature-name>.md`, replacing the
placeholders. Add enough acceptance criteria to demonstrate the Rules without
referencing tests or implementation details.

```markdown
# Feature name

**Tag:** `#existing-tag`

## Problem
What users are trying to accomplish and what gets in their way.

## Solution
How users accomplish it in Trace, including the primary entry point.

## Touchpoints
- [Related feature](related-feature.md) - how users arrive here or continue.

## Rules
- A durable user-facing invariant.

## FAQ
- **Common question?** A concise user-facing answer.
- **Second question?** Answer.
- **Third question?** Answer.

## Acceptance criteria
- From the entry point, users can perform the action and see the expected result.
- After the relevant transition or restart, the expected behavior is preserved.
- When a relevant failure occurs, users see the expected explanation and retain
  their existing work.
```

## Testing philosophy

Tests assert **Acceptance criteria**, making the feature Rules observable
without freezing implementation details. Only assertions protecting those
outcomes are relevant. When tests need updates without a change to acceptance
criteria, rewrite them against the documented outcome or remove them. See
[Code testing quality](DEVELOPMENT.md#code-testing-quality) for engineering guidance.

Acceptance criteria describe expected behavior, not proof that it is currently
tested. Test implementation belongs in the tests themselves; validation
commands and engineering practice belong in [DEVELOPMENT.md](DEVELOPMENT.md).
Do not turn an illustrative scenario or proposed behavior into a claim about
the shipped app without verifying it.
