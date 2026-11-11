# Copy trace

`#output`

## Problem
The result must land in Slack, an issue, or a doc in one keystroke, with the
explanation attached.

## Solution
With nothing selected, `⌘C` copies the annotated image plus transcript, saves
the trace, and (optionally) closes the board. The toolbar Copy button always
copies the whole trace; its options menu picks the format.
Whole-trace images frame the visible content with 8 canvas units of breathing
room on every side, rather than retaining unused page space.

## Touchpoints
- Edit → Copy trace / Copy trace and close; toolbar Copy and Copy options
- Format and close behavior from [App settings](app-settings.md)
- Triggered on pen disconnect by [Neo pen](neo-pen.md) settings
- Includes [Dictation](dictation.md) and [Timed annotations](timed-annotations.md)
- Shares image framing with command-line copy and export in [Command-line tool](command-line-tool.md)

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
Dictation-containing copy
├─ Stop microphone; keep the board open until the complete transcript is ready
├─ Waiting → spinner on the recording button; disable recording and duplicate Copy actions
│  └─ Rate limited with a valid retry delay → keep waiting; retry pending audio up to three times
├─ Complete → save audio and transcript; write the final clipboard payload once
│  └─ Clipboard write succeeds → apply close-after-copy
├─ Transcription or clipboard failure → stop loading; leave board open; do not report success
│  └─ Transcription failure → show the reason; retain audio chunks and completed words for retry
└─ Open trace changes while waiting → do not copy or close the replacement trace
Image-only copy
└─ Copy without waiting for Dictation
Copied pixels
├─ Include visible images, drawings, shapes, text, and numbered annotations
├─ Exclude grid, selection bounds, controls, cursors, and temporary pen predictions
└─ Fill output with the chosen page background color
Whole-trace image framing
├─ Visible content → smallest enclosing rectangle plus 8 canvas units on every side
│  ├─ Images → use current position and size; preserve internal whitespace
│  └─ Separated content → preserve distances; include every visible mark
├─ No visible content → document page dimensions without extra padding
├─ Zoom, pan, and selection → never change whole-trace framing
└─ Image, image and dictation, PDF, and CLI export → same image framing
```

## FAQ
- **`⌘C` copied my shape, not the trace.** Deselect first, or use the toolbar Copy.
- **Why did the board close?** "Close window after copy" is enabled.
- **How do I get a PDF?** Copy options → Copy as .pdf.
- **Why did the image size change?** It follows the visible content with an
  8-unit border, not the unused canvas or the screenshot's original position.
- **Is Dictation drawn into the image?** No. Image and dictation includes
  clipboard text and image metadata; PDF lays out the transcript separately.
- **Why is Copy waiting?** The recording button spins while the final words
  arrive. Paste after Copy finishes to get the complete transcript in one step.
- **What if Dictation fails?** The board stays open, the spinner stops, and
  the failure reason appears. Copy again to retry the retained recording.

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
- Moving or resizing a screenshot makes the whole-trace image follow its
  current bounds with 8 canvas units of background on every side, without
  keeping empty space from its original position.
- A sketch on a blank trace exports around its visible marks. Separate images,
  text, and numbered annotations remain included at their existing distances.
- An empty trace exports at the document page dimensions without added padding.
- Zooming, panning, or selecting content does not change toolbar Copy framing.
  Image copy, image and dictation, PDF, and command-line export share the same
  framing and page background.
- Copying with active Dictation keeps the board open and shows a spinner on the
  recording button. Recording and duplicate Copy actions stay disabled until
  the complete transcript is saved and copied.
- A short recording whose first words arrive after more than 3 seconds still
  produces a single complete copy. Image and dictation, Dictation-only, and PDF
  all wait; image-only Copy does not.
- Each transcription request uses a 12-second timeout. A valid Retry-After delay
  keeps the spinner visible through the wait and up to three retries.
- Successful Copy closes the board only after writing the final clipboard
  payload, and only when close-after-copy is enabled. Keeping the board open
  restores its controls and stops the spinner.
- An unrecovered API error or request timeout stops the spinner, displays the
  Dictation error, leaves the clipboard unchanged, and keeps the board open.
  Copy can retry without losing recorded chunks or completed words.
- A failed clipboard write leaves the board open and ends loading.
- Switching traces while Dictation finishes cannot copy or close the replacement.
