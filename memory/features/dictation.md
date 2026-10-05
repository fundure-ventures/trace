# Dictation

**Tag:** `#voice`

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
- Without a key, the button reads **Set up Dictation** and opens Setup instead of recording.
- States: Start → Stop/Resume → Finishing → Transcript; one visible state at a time.
- "Start dictation automatically" begins recording for newly created traces
  (blank or screenshot), and silently does nothing if not authorized/configured.
- Requires Microphone permission.

## FAQ
- **Which provider transcribes?** OpenRouter, with your own key.
- **Can I pause?** Yes; Resume continues the same recording.
- **Where is the transcript?** Copied with the image and saved in the `.traceboard`.

## Encoded enforcement
| Rule | Guard |
| --- | --- |
| State coalescing | `RetainedInkProbe.swift › verifyVoiceStateCoalescing` |
| Persistence | `RetainedInkProbe.swift › verifyVoicePackagePersistence` |
| Transcription/key handling | `swift run trace-voice-tests` |
