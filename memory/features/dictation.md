# Dictation

`#voice`

## Problem
Marks alone lose the "why". Typing an explanation afterwards breaks the flow.

## Solution
Speak while annotating. The toolbar's Dictation button records, pauses,
resumes, and finalizes into a transcript (via OpenRouter) that is saved with
the trace and copied alongside the image.

## Touchpoints
- [Board window](board-window.md) toolbar Dictation group
- Configured in [Setup](setup.md) (key) and [App settings](app-settings.md) (auto start)
- Feeds [Timed annotations](timed-annotations.md) and [Copy trace](copy-trace.md)
- Stored in [Traceboard documents](traceboard-documents.md)

## Rules
```text
Dictation button
├─ No key → "Set up Dictation"; open Setup instead of recording
└─ Key available → recording requires Microphone permission
Recording flow
└─ Start → Stop/Resume → Finishing → Transcript; one visible state at a time
Finishing for Copy
├─ Stop microphone; detach finishing work from the board
├─ Copy available content immediately; finish remaining transcription within 3 seconds
├─ API error or deadline → mark partial, cancel remaining requests, save recorded audio and available words
└─ Completion → save original trace; update clipboard only while still owned by that Copy
Finishing for CLI file export
├─ Wait for active Dictation; report API errors rather than successful export
└─ Retry → retain recorded chunks and previously transcribed words
New blank or screenshot trace
└─ Start dictation automatically enabled
   ├─ Configured and authorized → begin recording
   └─ Not configured or authorized → silently do nothing
```

## FAQ
- **Which provider transcribes?** OpenRouter, with your own key.
- **Can I pause?** Yes; Resume continues the same recording.
- **Where is the transcript?** Copied with the image and saved in the `.traceboard`.
- **Does slow transcription block Copy?** No. Available content is copied
  first and the board is released. Remaining transcription gets up to
  3 seconds; audio merging and saving may finish afterward in the background.

## Acceptance criteria
- Without a configured key, clicking "Set up Dictation" opens Setup rather
  than starting a recording.
- Users can start, pause, and resume a recording, then see it finishing and
  becoming a transcript, with one clear state shown at a time.
- Automatic Dictation starts for newly created blank or screenshot traces
  only when a key and Microphone permission are available.
- Reopening a saved trace preserves its recorded audio and transcript.
- Copy stops the microphone immediately and allows closing, drawing, or
  starting another trace while transcription finishes independently.
- API failure or the 3-second Copy deadline returns a partial result, saves
  recorded audio and available words, and leaves the first clipboard payload
  unchanged. Late network callbacks cannot update that result.
- CLI file export remains a waiting operation; API errors or reported timeouts
  leave its finishing state, report failure, and retain chunks/words for retry.
