# Trace app guide

## How do I start a trace?
Choose **New Screenshot trace** or **New Blank trace** from Trace's menu-bar
menu, or use the matching global shortcut. See [Blank trace](#blank-trace) and
[Screenshot capture](#screenshot-capture).

## How do I add an existing image?
Open an image in Finder with Trace, drag it onto a board, paste it, or use
[`traceapp`](CLI.md) to insert it. See [Image import](#image-import).

## How do I talk while annotating?
Use the Dictation control on the board after configuring a key and microphone
access in Setup. See [Dictation](#dictation).

## How do I copy or save a trace?
With nothing selected, press `⌘C` or use the toolbar Copy action. Traces
autosave as `.traceboard` packages. See [Copy trace](#copy-trace) and
[Traceboard documents](#traceboard-documents).

## How do I use a Neo pen?
Connect a supported Neo Smartpen and calibrate compatible Ncode paper in
Setup. See [Neo pen](#neo-pen) and [Pen calibration](#pen-calibration).

## How do I change app permissions or shortcuts?
Open **Setup** from the menu-bar menu. See [Setup](#setup) and
[Global shortcuts](#global-shortcuts).

## Feature glossary

### App settings
**What it does:** Configures pen, Copy, Dictation, and launch behavior.
**Where:** Trace menu bar menu.

### Blank trace
**What it does:** Opens an empty page for drawing or collecting images.
**Where:** Menu bar → New Blank trace; global shortcut.

### Board window
**What it does:** Shows the trace canvas and its floating toolbar.
**Where:** Opens when a trace is created or reopened.

### Canvas grid
**What it does:** Adds an adaptive reference grid that is not exported.
**Where:** Floating toolbar grid control.

### Command-line tool
**What it does:** Starts captures, imports images, copies traces, and exports files from Terminal.
**Where:** Setup → Command-line tool; see [CLI guide](CLI.md).

### Copy trace
**What it does:** Copies the whole trace image, narration, or PDF.
**Where:** `⌘C` with nothing selected; toolbar Copy and Copy options.
**Note:** Whole-trace images crop around visible content with 8 canvas units
of background on every side. Empty traces keep their page dimensions.
Active Dictation does not delay the first copy or closing the board. It has
up to 3 seconds to finish, then updates the clipboard only if nothing else
has been copied. The image stays frozen; already-pasted content does not
change. On timeout or API error, the first copy stays and recorded audio is saved.

### Device screenshots
**What it does:** Captures Android or paired iOS device screens directly into Trace.
**Where:** Menu bar → New Screenshot trace → device.

### Dictation
**What it does:** Records narration while annotating.
**Where:** Board Dictation control; requires microphone access and an OpenRouter key.

### Drawing tools
**What it does:** Selects, draws, highlights, creates rectangles, and adds text.
**Where:** Floating toolbar; keyboard shortcuts.

### Global shortcuts
**What it does:** Starts a blank trace or captures the frontmost app from anywhere.
**Where:** Setup → Keyboard shortcuts.

### Image import
**What it does:** Opens, drops, or pastes images onto a canvas.
**Where:** Finder → Open With → Trace; board drop; Edit → Paste image.

### Ink colors
**What it does:** Provides four legible annotation colors.
**Where:** Floating toolbar color control.

### Menu bar agent
**What it does:** Keeps Trace available from the menu bar without a Dock icon or app shell.
**Where:** macOS menu bar.

### Neo pen
**What it does:** Draws on compatible Ncode paper with a Neo Smartpen.
**Where:** Bluetooth pen input.

### Page background
**What it does:** Changes the page color for blank traces.
**Where:** Floating toolbar page controls.

### Pen calibration
**What it does:** Maps the paper's coordinates onto the trace page.
**Where:** Setup → Pen → Calibration.

### Pen hover cursor
**What it does:** Shows where a hovering pen will land.
**Where:** On the board while a connected pen hovers.

### Projection
**What it does:** Mirrors or projects a trace on an external display.
**Where:** Trace menu bar menu.

### Screenshot capture
**What it does:** Captures a frontmost app window into a trace.
**Where:** Menu bar → New Screenshot trace; global shortcut.

### Setup
**What it does:** Shows optional permissions, pen, Dictation, shortcut, and CLI setup.
**Where:** Menu bar → Setup.

### Timed annotations
**What it does:** Matches numbered marks to words in the narration.
**Where:** Dictation and board annotations.

### Tool sizes
**What it does:** Sets independent Pen, Highlighter, and Text sizes.
**Where:** Floating toolbar size control.

### Traceboard documents
**What it does:** Autosaves and reopens editable `.traceboard` packages.
**Where:** File → Open traces; `~/Documents/Trace`.
