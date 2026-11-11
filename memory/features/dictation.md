# Dictation

`#voice`

## Problem
Marks alone lose the "why". Typing an explanation afterwards breaks the flow.

## Solution
Speak while annotating. The toolbar's Dictation button records, pauses,
resumes, and finalizes into a transcript (via OpenRouter) that is saved with
the trace and copied alongside the image. Failures show a temporary explanation
beside the toolbar, with the full reason still available by hovering over Error.
When the provider supplies a retry delay for rate limiting, the pending audio
stays queued and retries automatically before showing a failure.
After a failure, the toolbar's Retry action transcribes the retained recording
without opening the microphone or clearing earlier words and annotations.

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
Recording error
├─ Show the failure reason beside the toolbar for 10 seconds or until dismissed
├─ Keep the full reason on the Error label's tooltip and accessible status
├─ Rate or quota limit → identify HTTP 429 and suggest waiting before retrying
└─ Manual Retry → finish the existing recording, never replace it
   ├─ Keep all audio chunks, completed words, and annotation timing
   ├─ Retry only pending chunks; show Finishing without starting the microphone
   ├─ Failure again → keep the recording available for another retry
   └─ Changing the API key after failure → preserve the recording for retry
Rate limiting (HTTP 429)
├─ Valid Retry-After → wait for that delay; retry the same audio up to three times
│  ├─ Keep later chunks queued in order; recording and pausing remain available
│  └─ Cancellation → stop waiting without sending another retry
└─ Missing/invalid delay or exhausted retries → report the failure
Diagnostics
├─ Every failed response, including automatic retries → retain safe failure and retry details
├─ Successful retry → record recovery
└─ Never record response bodies, provider messages, audio, transcripts, or credentials
Finishing for Copy
├─ Stop microphone; keep board open with a spinner on the recording button
├─ Rotate recording chunks every 6 seconds for earlier transcript availability
├─ Keep recording and duplicate Copy actions disabled while finishing
├─ Each request → 12-second timeout; no separate Copy deadline
├─ Unrecovered API error or request timeout → show error; stop spinner; keep board open and retain chunks/words for retry
└─ Completion → save audio/transcript; copy once; then honor close-after-copy
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
- **Does Retry start over?** No. It retries pending transcription from the same
  audio and saves the completed recording. Earlier words and annotations stay
  intact, including when you change the API key after a failure.
- **Where is the transcript?** Copied with the image and saved in the `.traceboard`.
- **What went wrong?** Read the temporary error message or hover over Error.
  HTTP 429 means OpenRouter or its provider has hit a rate or quota limit. Trace
  retries up to three times when a valid retry delay is supplied.
- **Why is the recording button spinning?** Copy is waiting for the complete
  transcript. The board closes only after copying succeeds, if close-after-copy
  is enabled. Image-only Copy does not wait for transcription.

## Acceptance criteria
- Without a configured key, clicking "Set up Dictation" opens Setup rather
  than starting a recording.
- Users can start, pause, and resume a recording, then see it finishing and
  becoming a transcript, with one clear state shown at a time.
- When Dictation fails on a visible board, users see the reason without having
  to hover first. The message dismisses after 10 seconds or when clicking
  elsewhere, and remains available through the Error tooltip and accessibility.
  A rate or quota failure identifies HTTP 429 and advises waiting before retrying.
- A rate-limited request with a valid Retry-After delay waits for the specified
  number of seconds or HTTP date before resending the same audio. Later chunks
  remain queued, previously transcribed words are retained, and recording can
  continue or pause while waiting. A successful retry resumes the queue in order
  without duplicating words or showing a terminal error.
- Three unsuccessful automatic retries report the provider's final error rather
  than waiting forever. A missing or invalid delay reports the error without
  automatically resending. Cancelling during a delay prevents further retries.
- With local diagnostic persistence enabled, failed responses are available in
  the logs even when an automatic retry recovers. Entries identify the status,
  attempt, available retry delay, and
  whether another attempt is planned. Known provider error types and names are
  retained; unknown values are masked. Recovery is recorded without saving
  response bodies, provider messages, audio, transcripts, or credentials.
- Automatic Dictation starts for newly created blank or screenshot traces
  only when a key and Microphone permission are available.
- Reopening a saved trace preserves its recorded audio and transcript.
- Copy stops the microphone and keeps the board open with a spinner on its
  recording button until the complete transcript is saved and copied.
  Recording and duplicate Copy actions stay disabled during this wait.
- Recording chunks rotate every 6 seconds instead of 12 seconds.
- Transcription may finish after 3 seconds without cancellation. Each request
  uses a 12-second timeout; the spinner stays visible during provider retry waits.
- An unrecovered API failure or request timeout stops loading, shows the error,
  and leaves the board open and clipboard unchanged. Retained chunks and words
  remain available for retry.
- After a failure, clicking Retry on the recording control shows Finishing and
  transcribes the original recording without starting the microphone, clearing
  earlier words, or changing their annotation timing. Success saves the complete
  audio and transcript to the same trace without copying or closing it. Another
  failure, or changing the API key before retrying, does not discard the audio
  or completed words.
- Successful Copy stops loading and closes only after the final clipboard write
  succeeds, respecting close-after-copy. No delayed partial clipboard update occurs.
- CLI Copy and file export wait for Dictation; API errors report failure and
  retain chunks/words for retry.
