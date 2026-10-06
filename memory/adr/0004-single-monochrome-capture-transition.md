# Keep one Monochrome Flash capture transition

**Status:** Accepted

## Context

Multiple experimental capture shaders and a session-only selector increased
product and test complexity without establishing a stronger product contract.
The transition also needs a deterministic Reduced Motion path.

## Decision

Capture uses only the Metal `traceMonochromeFlashFragment` pipeline. The
Monochrome Flash transition begins at the captured window's screen origin,
moves through black and white into the board reveal, and introduces the
toolbar from `-20 pt`.

There is no user-facing effect selector and no Liquid or Press shader path.
When Reduce Motion is enabled, Trace reveals the board and toolbar directly.

## Consequences

- Capture behavior and probe coverage have one deterministic effect.
- The product exposes no session-only visual preference.
- Alternative shader experiments remain history rather than supported paths.
