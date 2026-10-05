# Pen calibration

**Tag:** `#pen`

## Problem
Pen coordinates on paper must map exactly onto the screenshot, or marks land in
the wrong place.

## Solution
A guided corner-tapping calibration in [Setup](setup.md), stored per paper
profile and applied to compatible pages.

## Touchpoints
- [Setup](setup.md) → Start calibration / Calibration
- Required by [Neo pen](neo-pen.md) drawing and [Pen hover cursor](pen-hover-cursor.md)

## Rules
- Calibration can be cancelled at any time (**Cancel calibration**).
- Calibration is per paper profile and survives restarts.
- Pages map aspect-fit; the exact page is kept.

## FAQ
- **Marks are offset.** Recalibrate from Setup.
- **Do I recalibrate each launch?** No, it is saved.

## Encoded enforcement
| Rule | Guard |
| --- | --- |
| Mapping math | `swift run trace-calibration-tests`, `swift run trace-geometry-tests` |
| App integration | `RetainedInkProbe.swift › verifyCompatiblePageCalibrationIntegration` |
