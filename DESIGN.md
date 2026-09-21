---
name: Trace Native Surfaces
description: A menu-bar capture instrument and its measured pen-input lab
colors:
  paper: "#FBFBFB"
  paper-ink: "#141414"
typography:
  body:
    fontFamily: "-apple-system, BlinkMacSystemFont, sans-serif"
    fontSize: "12px"
    fontWeight: 400
    lineHeight: 1.2
  measurement:
    fontFamily: "SF Mono, ui-monospace, monospace"
    fontSize: "11px"
    fontWeight: 400
    lineHeight: 1.2
spacing:
  status-inset: "14px"
  status-gap: "8px"
  canvas-inset: "24px"
components:
  status-bar:
    height: "42px"
    padding: "{spacing.status-inset}"
---

# Design System: Trace

## Overview

**Creative North Star: "The Invisible Capture Instrument"**

Trace normally exists as one menu-bar glyph. Physical contact pulls a selected
window out of the desktop, briefly presses it into metal, then leaves only the
captured window and one floating tool pill. There is no title bar, traffic
light cluster, or permanent frame chrome.

## Colors

- The app chrome uses semantic AppKit system colors and follows the current
  macOS appearance.
- The product board uses the captured screenshot as its entire color field. A
  compact graphite floating toolbar is the only persistent product chrome.
- Product annotation colors are red, blue, yellow, and green.

## Typography

- System UI text uses San Francisco through AppKit system fonts.
- Measurement values use monospaced system digits at 11 pt.
- Annotation digits use the system sans-serif stack with tabular numerals.

## Layout

- The window minimum preserves that complete canvas, its 24 pt inset, the
  status bar, and PaperKit's toolbar rather than scaling the drawing area down.
- The floating toolbar sits 10 pt above the screenshot and consumes no
  screenshot pixels. Board sizing reserves that toolbar band before fitting.
- Empty toolbar chrome drags the parent board; interactive controls retain
  their events. Empty drawing content never drags the window.\*

## Do's and Don'ts

- Do use native controls and semantic system state colors.
- Do not hardcode paper dimensions.
- Do preserve source-window 1:1 point size whenever screen bounds permit.
- Do keep grids and selection bounds out of exported pixels.
- Do keep the menu agent alive after every transient window closes.
- Do treat HDMI and AirPlay screens identically after macOS exposes them
- Do not add traffic lights, a title bar, reserved toolbar rows, permanent
  bezels, or a conventional app shell
