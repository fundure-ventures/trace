# Page background

**Tag:** `#board`

## Problem
Blank traces sometimes need a dark or tinted page to match the content being
explained.

## Solution
A color well in the toolbar sets the page background per document; new blank
pages reuse the last choice (default white).

## Touchpoints
- [Board window](board-window.md) toolbar
- Feeds [Ink colors](ink-colors.md) and [Canvas grid](canvas-grid.md) contrast
- Default for [Blank trace](blank-trace.md)

## Rules
- Stored per document; remembered for the next blank page.
- Painted natively before the canvas loads.

## FAQ
- **Can I change a screenshot's background?** It affects the page around it.
- **Why is my new blank page dark?** It reuses the last background.

## Encoded enforcement
| Rule | Guard |
| --- | --- |
| Control layout | `RetainedInkProbe.swift › verifyBackgroundControlLayout` |
| Remembered default | Gap — covered only indirectly by `verifyDocumentPresentationDefaults` |
