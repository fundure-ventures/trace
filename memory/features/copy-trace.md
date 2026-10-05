# Copy trace

**Tag:** `#output`

## Problem
The result must land in Slack, an issue, or a doc in one keystroke, with the
explanation attached.

## Solution
With nothing selected, `⌘C` copies the annotated image plus transcript, saves
the trace, and (optionally) closes the board. The toolbar Copy button always
copies the whole trace; its options menu picks the format.

## Touchpoints
- Edit → Copy trace / Copy trace and close; toolbar Copy and Copy options
- Format and close behavior from [App settings](app-settings.md)
- Triggered on pen disconnect by [Neo pen](neo-pen.md) settings
- Includes [Dictation](dictation.md) and [Timed annotations](timed-annotations.md)

## Rules
- Selection wins: with shapes or text selected, `⌘C` copies the selection and keeps the board open.
- While editing text, `⌘C` stays text copy, even with only a caret.
- Selection is read live from the canvas; if it cannot be read, Trace does not fall back to full-trace copy.
- Formats: image and dictation, image, dictation, `.pdf`.
- Copied pixels exclude grid and selection bounds.

## FAQ
- **`⌘C` copied my shape, not the trace.** Deselect first, or use the toolbar Copy.
- **Why did the board close?** "Close window after copy" is enabled.
- **How do I get a PDF?** Copy options → Copy as .pdf.

## Encoded enforcement
| Rule | Guard |
| --- | --- |
| Selection/text/caret routing | `ProductTldrawProbe.swift › verifySelectionCopy` (`TRACE_PRODUCT_TLDRAW_PROBE=framing`) |
| Composite + clipboard payload | `RetainedInkProbe.swift › verifyComposite` |
| Export planning | `WebCanvas/tests/exportPlanning.test.ts` |
