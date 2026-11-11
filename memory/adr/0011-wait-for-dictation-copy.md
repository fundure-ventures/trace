# Wait visibly for complete Dictation before Copy

**Status:** Accepted

## Context
[Progressive Copy](0010-progressive-copy-dictation.md) let users paste before
Dictation finished. A successful rate-limit retry updated the clipboard later,
but could not update text already pasted elsewhere. This looked like failed
transcription even when the complete transcript was eventually saved.

## Decision
For [Copy trace](../features/copy-trace.md) formats containing
[Dictation](../features/dictation.md), reuse the existing waiting voice
finalization used by file export. Keep the original board open, show a native
spinner on the recording button, and disable recording and duplicate Copy.
Save the complete recording, write the final clipboard payload once, then
honor close-after-copy. Image-only Copy continues without waiting.

Keep the existing per-request timeout, serial chunk queue, and bounded
Retry-After handling. Transcription failures retain chunks and completed words
for retry, show the error, and leave the board open without changing the
clipboard. Guard completion against a changed document.

## Consequences
- One successful Copy provides the complete transcript for the first paste.
- Network and provider retry delays keep the board open with visible progress.
- Clipboard failure ends loading without closing the board.
- Copy no longer uses detached background finalization or late clipboard writes.
- There is still no overall deadline across sequential chunks and retry waits.
