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
├─ Copy current image and already completed transcript without waiting for the network
│  └─ First clipboard write → release controls and apply close-after-copy
├─ Remaining transcription → finish in background using a 12-second per-request timeout
│  ├─ Complete → save to original trace; update clipboard only if Trace still owns it
│  └─ API error or request timeout → cancel remaining requests; keep first copy; save available words and audio
├─ Late update → reuse original image and numbered references, not subsequent canvas edits
├─ Another copy, from Trace or another app → never overwrite it with the late result
└─ Dictation-only with no completed text → release controls; copy on successful completion
   └─ API error or request timeout → clipboard unchanged; available audio saved
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
- **Can I paste immediately while Dictation finishes?** Yes. The first copy
  contains the image and available transcript. Once Dictation finishes,
  a second paste can include the complete transcript. Content
  already pasted into another app is not changed.
- **What if I close the board or open another trace?** Finishing Dictation
  belongs to the original trace. The new board stays usable and is not closed
  or changed by that work. Starting a replacement recording on the original
  trace supersedes its older recording.

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
- Copying with active Dictation does not wait for transcription before
  writing available content, releasing controls, or honoring close-after-copy.
- Remaining transcription is not canceled after 3 seconds. Each request uses
  a 12-second timeout; multiple chunks may take longer overall.
  An API failure or request timeout preserves the first copy, available words, and
  recorded audio; status explains whether Dictation finished, updated, or
  remained partial.
- The late image/PDF uses the original image and annotation references.
  A newer clipboard owner, including another Trace copy, prevents replacement.
- Closing, reopening, editing, or switching traces while Dictation finishes
  cannot redirect the result to another trace or overwrite later canvas edits.
- A short recording with no completed text still updates the initial image
  copy when transcription succeeds after more than 3 seconds.
- Dictation-only Copy without available text never writes an empty clipboard
  payload and cannot close a newly started recording after its delayed result.
