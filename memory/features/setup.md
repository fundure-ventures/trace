# Setup

**Tag:** `#app`

## Problem
Trace depends on macOS permissions, an optional pen, an optional Dictation key,
and global shortcuts. Discovering missing pieces mid-annotation is frustrating.

## Solution
A single **Trace Setup** panel lists every prerequisite with its status and one
action: pen connection and [calibration](pen-calibration.md), Screen
Recording and Microphone permissions, the OpenRouter key for
[Dictation](dictation.md), and [Global shortcuts](global-shortcuts.md). It
opens on first launch (onboarding) and later from the menu bar.

## Touchpoints
- [Menu bar agent](menu-bar-agent.md) → **Setup**
- Toolbar Dictation button when Dictation is not configured ([Dictation](dictation.md))
- Leads into [Pen calibration](pen-calibration.md) and [Global shortcuts](global-shortcuts.md)

## Rules
- Every item is optional except what the chosen workflow needs; the pen is never required.
- Externally supplied keys (env / `.env`) take precedence over the key saved in Setup.
- The personal OpenRouter key is stored only in macOS Keychain and can be replaced or removed.
- Onboarding disables board resizing.
- `./tools/trace --clear` repeats onboarding without deleting saved traces.

## FAQ
- **Do I need a Neo pen?** No; mouse/trackpad tools work without it.
- **Where is my API key stored?** Only in the macOS Keychain.
- **Why does Dictation say setup required?** No OpenRouter key is available.
- **How do I see onboarding again?** `./tools/trace --clear` (debug product).

## Encoded enforcement
| Rule | Guard |
| --- | --- |
| Onboarding presentation and optional flow | `RetainedInkProbe.swift › verifyOnboardingPresentation`, `verifyOptionalSetupFlow` (`TRACE_ONBOARDING_PROBE=1`) |
| Shortcut rows in Setup | `RetainedInkProbe.swift › verifyGlobalShortcutSetupUI` |
| Keychain-only storage, env precedence | Gap — manual review |
