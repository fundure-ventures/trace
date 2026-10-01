import { color, lint } from '@basiclines/rampa-sdk'
import type { TLDefaultColorStyle } from 'tldraw'

export const INK_NAMES = ['red', 'yellow', 'green', 'blue'] as const
export type InkName = (typeof INK_NAMES)[number]

// tldraw 4.5 light-mode solids: the hues users picked the swatches for.
export const INK_ANCHORS: Record<InkName, string> = {
  red: '#e03131',
  yellow: '#f1ac4b',
  green: '#099268',
  blue: '#4465e9',
}

// Highlighter strokes borrow palette slots Trace never exposes, so each
// ink can render a separate opaque highlighter color.
const HIGHLIGHTER_COLOR_NAMES: Record<InkName, TLDefaultColorStyle> = {
  red: 'light-red',
  yellow: 'orange',
  green: 'light-green',
  blue: 'light-blue',
}

const BACKGROUND_TINT = 0.15
const MIN_CONTRAST = 30
const RELATIVE_CONTRAST = 0.6
const HIGHLIGHTER_MIX = 0.6
const LIGHTNESS_STEP = 0.01

export interface InkPalette {
  ink: Record<InkName, string>
  highlighter: Record<InkName, string>
}

export function deriveInkPalette(background: string | null): InkPalette {
  const page = background ?? '#ffffff'
  const contrast = (foreground: string) =>
    Math.abs(lint(foreground, page).score)
  const blackContrast = contrast('#000000')
  const whiteContrast = contrast('#ffffff')
  const direction = blackContrast >= whiteContrast ? -1 : 1
  const target = Math.min(
    MIN_CONTRAST,
    RELATIVE_CONTRAST * Math.max(blackContrast, whiteContrast),
  )
  const palette: InkPalette = {
    ink: { ...INK_ANCHORS },
    highlighter: { ...INK_ANCHORS },
  }
  for (const name of INK_NAMES) {
    const tinted = color(INK_ANCHORS[name]).mix(page, BACKGROUND_TINT, 'oklab')
    const lightness = tinted.oklch.l
    let ink = tinted.hex
    for (
      let shift = LIGHTNESS_STEP;
      contrast(ink) < target && shift <= 1;
      shift += LIGHTNESS_STEP
    ) {
      ink = tinted.set({
        lightness: clamp(lightness + direction * shift),
      }).hex
    }
    palette.ink[name] = ink
    palette.highlighter[name] = color(ink).mix(page, HIGHLIGHTER_MIX, 'oklab').hex
  }
  return palette
}

export function highlighterColorName(ink: InkName): TLDefaultColorStyle {
  return HIGHLIGHTER_COLOR_NAMES[ink]
}

export function colorNameForStroke(
  color: TLDefaultColorStyle,
  isHighlighter: boolean,
): TLDefaultColorStyle {
  return isHighlighter && isInkName(color) ? highlighterColorName(color) : color
}

function isInkName(name: string): name is InkName {
  return (INK_NAMES as readonly string[]).includes(name)
}

export function inkNameForColor(name: TLDefaultColorStyle): TLDefaultColorStyle {
  const ink = INK_NAMES.find((candidate) => HIGHLIGHTER_COLOR_NAMES[candidate] === name)
  return ink ?? name
}

function clamp(lightness: number): number {
  return Math.min(1, Math.max(0, lightness))
}
