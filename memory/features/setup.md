# Setup

**Tag:** `#app`

## Problem
Trace depends on macOS permissions, an optional pen, an optional Dictation key,
and global shortcuts. Discovering missing pieces mid-annotation is frustrating.

## Solution
A single **Trace Setup** panel lists every prerequisite with its status and one
action: pen connection and [calibration](pen-calibration.md), Screen
Recording and Microphone permissions, the OpenRouter key for
[Dictation](dictation.md), [Global shortcuts](global-shortcuts.md), and the
optional [command-line tool](command-line-tool.md). It
opens on first launch (onboarding) and later from the menu bar.

## Touchpoints
- [Menu bar agent](menu-bar-agent.md) → **Setup**
- Toolbar Dictation button when Dictation is not configured ([Dictation](dictation.md))
- Leads into [Pen calibration](pen-calibration.md) and [Global shortcuts](global-shortcuts.md)
- Installs [Command-line tool](command-line-tool.md)

## Rules
- Every item is optional except what the chosen workflow needs; the pen is never required.
- Externally supplied keys (env / `.env`) take precedence over the key saved in Setup.
- The personal OpenRouter key is stored only in macOS Keychain and can be replaced or removed.
- Onboarding disables board resizing.
- `./tools/trace --clear` repeats onboarding without deleting saved traces.
- Command-line installation is optional and never blocks Setup readiness.
- Pending setup checks use a muted outlined checkmark, not a warning icon.
- The command-line row reads “Use traceapp from the terminal” before installation
  and “traceapp” after installation, without a subtitle or install path.
- Command-line documentation is linked inline beside the row label as “· docs”.
- Closing a trace while Setup is open closes the canvas, toolbar, and Setup
  panel together. Background status updates do not reopen them.
- Installing or reinstalling `traceapp` can replace a symlink, but never
  overwrites an existing regular file or directory at the install path.

## FAQ
- **Do I need a Neo pen?** No; mouse/trackpad tools work without it.
- **Where is my API key stored?** Only in the macOS Keychain.
- **Why does Dictation say setup required?** No OpenRouter key is available.
- **How do I see onboarding again?** `./tools/trace --clear` (debug product).
- **Can I use Trace from Terminal?** Install `traceapp` from the final Setup section.

## Acceptance criteria
- Users can reach Setup from the status-bar menu and see statuses and
  actions for the pen, permissions, Dictation key, global shortcuts, and
  optional command-line installation.
- Users without a pen can complete the setup needed for mouse-driven use.
- Pending checks appear muted; completed checks remain green.
- Closing a trace with Setup open leaves no floating Setup panel or orphan
  canvas, including after permission or device statuses refresh.
- The command-line row shows a single label with Install or Uninstall, without
  repeating instructions or displaying the installation location.
- Users can save, replace, or remove their personal OpenRouter key; it is
  kept only in Keychain, and an externally supplied key takes precedence.
- The onboarding board cannot be resized.
- Repeating debug onboarding leaves saved traces intact.
- A missing, current, broken, or conflicting `traceapp` link is explained
  with an appropriate install, uninstall, or reinstall action; CLI setup does
  not prevent other Setup tasks.
- If another executable already occupies the install path, Install or
  Reinstall reports the conflict and preserves that file unchanged.
