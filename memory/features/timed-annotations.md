# Timed annotations

**Tag:** `#voice`

## Problem
A transcript and a marked-up image are hard to connect: "this" and "here"
lose their meaning once copied.

## Solution
Strokes and rectangles drawn while dictating get a number marker. The same
number is inserted into the transcript at the matching spoken words
([ADR 0006](../adr/0006-unified-timed-annotations.md)).

## Touchpoints
- Created by [Drawing tools](drawing-tools.md) and [Neo pen](neo-pen.md) during [Dictation](dictation.md)
- Marker size from [App settings](app-settings.md) → Annotation scale
- Visible in [Copy trace](copy-trace.md) output

## Rules
- Neo strokes and canvas shapes share one clock and one numbering sequence per document.
- Canvas marker and transcript reference always use the same number.
- Late labels are offset and clamped to stay on the page.
- Annotation scale: Small 75%, Medium 100%, Large 150%.

## FAQ
- **Why do numbers appear on my drawing?** You drew while dictating.
- **Can I make markers smaller?** Settings → Dictation → Annotation scale.
- **Do pen and mouse strokes share numbers?** Yes, one sequence.

## Acceptance criteria
- Marks made with the Neo pen and canvas tools during Dictation share one
  numbering sequence within the trace.
- A number beside a mark matches the reference beside its corresponding
  spoken words in the transcript.
- Labels added after transcription stay on the page rather than being
  clipped at its edge.
- Choosing Small, Medium, or Large annotation scale changes marker size
  to 75%, 100%, or 150% respectively.
