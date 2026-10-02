import assert from 'node:assert/strict'
import test from 'node:test'
import { color, lint } from '@basiclines/rampa-sdk'
import {
  colorNameForStroke,
  deriveInkPalette,
  highlighterColorName,
  INK_ANCHORS,
  INK_NAMES,
  HARMONY_OFFSETS,
  HIGHLIGHTER_OPACITY,
  inkNameForColor,
  MAX_HUE_SHIFT,
  opacityForStroke,
} from '../src/inkPalette.ts'

const contrast = (foreground: string, background: string) =>
  Math.abs(lint(foreground, background).score)

const bestContrast = (background: string) =>
  Math.max(contrast('#000000', background), contrast('#ffffff', background))

const hueDistance = (a: string, b: string) => {
  const delta = Math.abs(color(a).oklch.h - color(b).oklch.h) % 360
  return Math.min(delta, 360 - delta)
}

for (const background of ['#ffffff', '#111111', '#2f8f4e', '#1e3a8a', '#fde68a']) {
  test(`inks stay legible on ${background}`, () => {
    const palette = deriveInkPalette(background)
    const target = Math.min(30, 0.6 * bestContrast(background))
    for (const name of INK_NAMES) {
      assert.ok(
        contrast(palette.ink[name], background) >= target - 0.5,
        `${name} ${palette.ink[name]} on ${background}`,
      )
    }
  })
}

test('inks blend toward the background while keeping their hue', () => {
  const background = '#fef3c7'
  const palette = deriveInkPalette(background)
  for (const name of INK_NAMES) {
    assert.notEqual(palette.ink[name], INK_ANCHORS[name])
    assert.ok(
      hueDistance(palette.ink[name], INK_ANCHORS[name]) < 25,
      `${name} hue drifted to ${palette.ink[name]}`,
    )
  }
})

for (const [background, direction] of [['#1e3a8a', 1], ['#2f8f4e', 1], ['#fde68a', -1]] as const) {
  test(`contrast fixes move lightness away from ${background}`, () => {
    const palette = deriveInkPalette(background)
    const moved = INK_NAMES.filter((name) => {
      const tinted = color(INK_ANCHORS[name]).mix(background, 0.15, 'oklab').oklch.l
      const shift = color(palette.ink[name]).oklch.l - tinted
      assert.ok(shift * direction >= -0.01, `${name} ${palette.ink[name]}`)
      return Math.abs(shift) > 0.02
    })
    assert.ok(moved.length > 0, 'expected at least one ink to need a lightness fix')
  })
}

const signedHueDelta = (from: number, to: number) => ((to - from + 540) % 360) - 180

for (const background of ['#2f8f4e', '#1e3a8a', '#fde68a', '#fbcfe8']) {
  test(`ink hues lean at most ${MAX_HUE_SHIFT}° toward a harmony of ${background}`, () => {
    const palette = deriveInkPalette(background)
    const pageHue = color(background).oklch.h
    for (const name of INK_NAMES) {
      const tintedHue = color(INK_ANCHORS[name]).mix(background, 0.15, 'oklab').oklch.h
      const harmonyDeltas = HARMONY_OFFSETS.map((offset) =>
        signedHueDelta(tintedHue, pageHue + offset),
      )
      const nearest = harmonyDeltas.reduce((best, delta) =>
        Math.abs(delta) < Math.abs(best) ? delta : best,
      )
      const expected = Math.sign(nearest) * Math.min(Math.abs(nearest), MAX_HUE_SHIFT)
      const actual = signedHueDelta(tintedHue, color(palette.ink[name]).oklch.h)
      assert.ok(
        Math.abs(actual - expected) < 1.5,
        `${name} ${palette.ink[name]} shifted ${actual.toFixed(1)}°, expected ${expected.toFixed(1)}°`,
      )
    }
  })
}

test('neutral backgrounds have no hue to harmonize with', () => {
  for (const background of ['#ffffff', '#111111', '#808080']) {
    const palette = deriveInkPalette(background)
    for (const name of INK_NAMES) {
      const tinted = color(INK_ANCHORS[name]).mix(background, 0.15, 'oklab').hex
      assert.ok(hueDistance(palette.ink[name], tinted) < 1.5, `${name} on ${background}`)
    }
  }
})

test('highlighter is a lightly tinted ink between the ink and the background', () => {
  const background = '#ffffff'
  const palette = deriveInkPalette(background)
  for (const name of INK_NAMES) {
    const ink = color(palette.ink[name]).oklch.l
    const highlighter = color(palette.highlighter[name]).oklch.l
    const page = color(background).oklch.l
    assert.match(palette.highlighter[name], /^#[0-9a-f]{6}$/)
    assert.ok(highlighter > ink && highlighter < page, `${name} ${palette.highlighter[name]}`)
    assert.ok(
      Math.abs(highlighter - (ink + (page - ink) * 0.25)) < 0.01,
      `${name} highlighter should sit 25% toward the page`,
    )
  }
})

test('missing background falls back to white', () => {
  assert.deepEqual(deriveInkPalette(null), deriveInkPalette('#ffffff'))
})

test('highlighter strokes use dedicated tldraw color names that map back to inks', () => {
  for (const name of INK_NAMES) {
    const highlighterName = highlighterColorName(name)
    assert.notEqual(highlighterName, name)
    assert.equal(inkNameForColor(highlighterName), name)
    assert.equal(inkNameForColor(name), name)
    assert.equal(colorNameForStroke(name, true), highlighterName)
    assert.equal(colorNameForStroke(name, false), name)
  }
  assert.equal(colorNameForStroke('black', true), 'black')
})

test('highlighter strokes are partly transparent so content shows through', () => {
  assert.ok(HIGHLIGHTER_OPACITY > 0.5 && HIGHLIGHTER_OPACITY < 1)
  assert.equal(opacityForStroke(true), HIGHLIGHTER_OPACITY)
  assert.equal(opacityForStroke(false), 1)
})
