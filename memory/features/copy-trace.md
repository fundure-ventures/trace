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

## Acceptance criteria
- With nothing selected, pressing `⌘C` copies the trace in the chosen format
  and closes the board only when the close-after-copy setting is enabled.
- With shapes or text selected, `⌘C` copies that selection and leaves the
  board open. While editing text, even a caret alone keeps it a text-copy action.
- If the current selection cannot be determined, `⌘C` never unexpectedly
  copies the whole trace.
- The toolbar Copy action copies the whole trace regardless of selection.
- Users can choose image and dictation, image, dictation, or PDF; copied
  images contain neither grid marks nor selection outlines.
