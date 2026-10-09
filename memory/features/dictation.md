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
├─ API error or reported timeout → report failure, not a successful transcript
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

## Acceptance criteria
- Without a configured key, clicking "Set up Dictation" opens Setup rather
  than starting a recording.
- Users can start, pause, and resume a recording, then see it finishing and
  becoming a transcript, with one clear state shown at a time.
- Automatic Dictation starts for newly created blank or screenshot traces
  only when a key and Microphone permission are available.
- Reopening a saved trace preserves its recorded audio and transcript.
- When the transcription API reports an error or timeout while finishing for
  Copy, Dictation leaves the finishing state and reports the failure. Retrying
  retains the recording and previously transcribed words.
