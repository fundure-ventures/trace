# Architecture decision records

This is the inventory and documentation guide for durable implementation
decisions in [`memory/adr/`](memory/adr/).

ADRs explain **why** an implementation
is shaped the way it is.

## Inventory

| ADR | Decision |
| --- | --- |
| [0001](memory/adr/0001-required-tldraw-product-canvas.md) | Require the hidden-UI tldraw product canvas |
| [0002](memory/adr/0002-native-board-window-resizing.md) | Let native AppKit chrome own board resizing |
| [0003](memory/adr/0003-metal-only-isotropic-grid.md) | Render the grid only with Metal in board-view points |
| [0004](memory/adr/0004-single-monochrome-capture-transition.md) | Keep one Monochrome Flash capture transition |
| [0005](memory/adr/0005-native-first-blank-page-loading.md) | Paint blank pages natively until tldraw is ready |
| [0006](memory/adr/0006-unified-timed-annotations.md) | Unify timed Neo and tldraw annotations |
| [0007](memory/adr/0007-batched-finder-image-import.md) | Import Finder image batches into one canvas |
| [0008](memory/adr/0008-background-derived-color-theming.md) | Derive annotation colors from the page background |
| [0009](memory/adr/0009-cli-unix-socket-ipc.md) | Use a per-user Unix socket for the command-line interface |

## Documentation principles

- Record decisions with lasting constraints or meaningful tradeoffs, not every
  code change, transient investigation, or implementation detail.
- Use one decision per record, named `memory/adr/NNNN-short-decision.md`.
  Use the next available number; keep existing record numbers stable.
- State the context, the chosen approach, and why it was chosen. Explain real
  alternatives and their tradeoffs rather than inventing rejected options.
- Separate facts and evidence from assumptions. Accepted records must describe
  the implementation actually adopted; use Proposed for undecided approaches.
- Describe both benefits and costs under Consequences, including constraints
  future changes must preserve.
- Link affected feature files and related ADRs. Do not duplicate feature
  acceptance criteria, development commands, or visual guidelines.
- Add each record to this inventory in the same change as the decision.
  If a decision is replaced, preserve its rationale, mark it Superseded, and
  link the replacement record; have the replacement link back.

## ADR template

Copy this structure into `memory/adr/NNNN-short-decision.md`. Use Proposed,
Accepted, or Superseded for Status. Omit Rejected alternatives when no
meaningful alternatives were considered.

```markdown
# Decision title

**Status:** Proposed

## Context
The problem, constraints, and evidence that make this decision necessary.
Link the affected features and any related decisions.

## Decision
The chosen approach, why it fits the constraints, and its scope.

## Rejected alternatives
- Alternative considered: why it was not chosen and its tradeoffs.

## Consequences
- User or engineering benefit.
- Cost, limitation, or risk introduced.
- Constraint future implementation changes must preserve.
```
