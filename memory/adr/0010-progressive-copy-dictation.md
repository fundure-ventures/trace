# Copy available content before bounded background Dictation

**Status:** Accepted

## Context
[Copy trace](../features/copy-trace.md) previously waited for all pending
[Dictation](../features/dictation.md) chunks before copying anything. Slow
network responses disabled board controls for an unbounded sequence of
requests. Reported API errors and timeouts were covered, but a stalled request
could still prevent the initial clipboard write.

## Decision
Copy the locally rendered image and already completed transcript first.
Release controls and honor close-after-copy after this write. Detach the
recording controller from the live board and give its remaining transcription
one 3-second budget measured from Copy, not a budget per chunk.

Save the result and recorded audio to the original trace. On an API error or
deadline, cancel remaining transcription and explicitly return a partial
result; audio merging and persistence may finish after the network deadline.
Update the clipboard only on complete transcription and only while its
pasteboard change count still matches the initial write. Reuse the original
image and numbered-reference state, never subsequent canvas edits.

Use the current or freshly loaded original document when persisting, preserving
later canvas edits. A replacement recording supersedes the older recording's
document ownership. Scope delayed UI feedback to the originating document and
latest Copy; never let a delayed result close a new recording.

CLI clipboard Copy shares this behavior. CLI file export retains its waiting
finalization because file export needs a single final result.

## Rejected alternatives
- Wait for every chunk: preserves one-step completion but makes Copy depend
  on network latency and keeps the board blocked.
- Return only the available content: responds promptly but discards the chance
  to copy the final words without another action.
- Always replace the clipboard on completion: can destroy something copied
  from another app or a newer Trace.

## Consequences
- Users can paste available content and continue drawing, close, or open
  another trace without waiting for transcription.
- Content already pasted elsewhere is not updated; a later paste may differ.
- Dictation-only Copy with no completed text cannot provide an immediate
  payload. It releases the board and waits for the same bounded result.
- Timeout/error preserves the first clipboard payload and recorded audio,
  but the saved transcript can remain partial.
- Detached work requires explicit document and clipboard ownership guards.
  The transcription budget does not bound local rendering, audio merging,
  or disk persistence.
