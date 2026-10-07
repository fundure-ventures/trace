# Copy trace

`#output`

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
```text
Copy action
├─ Toolbar Copy → whole trace
└─ ⌘C
   ├─ Editing text, even caret only → text copy; keep board open
   └─ Not editing text → read live canvas selection
      ├─ Selection unreadable → never fall back to whole-trace copy
      ├─ Shapes or text selected → selection copy; keep board open
      └─ Nothing selected → whole trace
Whole-trace copy
├─ Format → image and dictation, image, dictation, or .pdf
└─ Copy and save trace
   ├─ Close-after-copy enabled → close board
   └─ Close-after-copy disabled → keep board open
Copied pixels
└─ Exclude grid and selection bounds
```

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
