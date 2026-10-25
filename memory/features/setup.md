# Setup

`#app`

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

Experimental debug builds also include **iPad and Apple Pencil**. Setup
looks for iPads on the local network, offers the detected device, and walks
through one instruction and action at a time. If wireless discovery is not
available yet, the flow starts with USB instead.

## Touchpoints
- [Menu bar agent](menu-bar-agent.md) → **Setup**
- Toolbar Dictation button when Dictation is not configured ([Dictation](dictation.md))
- Leads into [Pen calibration](pen-calibration.md) and [Global shortcuts](global-shortcuts.md)
- Installs [Command-line tool](command-line-tool.md)

## Rules
```text
Setup requirements
├─ Chosen workflow → require only what it needs; pen never required
├─ Command-line installation → optional; never blocks readiness
└─ Pending check → muted outlined checkmark; never warning icon
Dictation key
├─ External key (env / .env) → takes precedence over saved key
└─ Personal key → macOS Keychain only; can replace or remove
Onboarding
├─ Board resizing → disabled
└─ ./tools/trace --clear → repeat onboarding; preserve saved traces
Command-line row
├─ Before installation → "Use traceapp from the terminal"
├─ After installation → "traceapp"
└─ Presentation → inline "· docs" link; no subtitle or install path
Install or reinstall traceapp
├─ Existing symlink → may replace
└─ Existing regular file or directory → never overwrite
Close trace with Setup open
└─ Close canvas, toolbar, and Setup together
   └─ Background status updates → never reopen them
Experimental iPad setup (debug builds only)
├─ Open Setup → look for iPads on the local network
├─ Multiple iPads → user chooses which one to configure
├─ No advertising iPad → offer USB setup; never claim a device is ready
├─ Configure
│  ├─ Trust → guide USB connection, Finder trust, and iPad approval as needed
│  ├─ Wireless → enable only after user chooses the action
│  ├─ Verify → require USB unplugged and a trusted Wi-Fi log connection
│  ├─ Screen Recording missing → offer permission action
│  └─ Pencil check → attach, pick up, return; no automatic captures during check
├─ Completed → remember iPad and expose default-on automation setting
├─ Failure → show current problem and a retry action; never mark complete
└─ Close Setup → stop setup checks; do not reopen the window
```

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
- In experimental debug builds, opening Setup searches the local network
  and offers an identified iPad for configuration. Multiple iPads can be
  selected explicitly; without a reachable iPad, users get a USB instruction.
- Users finish iPad setup without entering identifiers or commands. Each step
  shows the current instruction and one primary action, with separate steps
  for trusting the Mac and enabling wireless access.
- Setup cannot complete its wireless check while the selected iPad is still
  connected by USB. It confirms actual wireless trust and Pencil pickup/return
  before saving a new configuration.
- Pencil gestures used for setup do not create screenshot boards. After
  completion, the remembered automation preference controls normal pickup.
- Closing Setup stops its discovery or verification work without reopening
  it or discarding an already saved iPad configuration.
