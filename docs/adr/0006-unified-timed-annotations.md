# Unify timed Neo and tldraw annotations

**Status:** Accepted

## Context

Trace can receive paths from the Neo pen and from tldraw Draw or Rectangle
gestures. Voice transcription needs one chronological annotation vocabulary
regardless of the drawing source. Rectangle also has to remain active after
tldraw automatically selects a newly created shape.

## Decision

Completed Neo strokes and timed tldraw Draw/Rectangle shapes record intervals
on the same app clock and share one document-local annotation sequence. The
transcript planner matches those intervals to word timings and uses the same
number marker in the canvas and transcript.

Rectangle is sticky. After tldraw creates a rectangle, Trace clears the
automatic selection and reapplies the rectangle tool unless temporary
selection is active.

## Consequences

- Mixed pen and mouse annotations produce one ordered transcript reference
  system.
- Persisted word timings and drawing intervals can reconstruct the pairing.
- Repeated rectangle creation keeps the editor and native toolbar aligned.
