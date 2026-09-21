import assert from 'node:assert/strict'
import test from 'node:test'
import {
  planTraceImageExport,
  type LogicalBounds,
} from '../src/exportPlanning.ts'

const base: LogicalBounds = {
  x: 0,
  y: 0,
  width: 900,
  height: 650,
}

test('exports the exact base for absent, inside, and touching content', () => {
  for (const contributors of [
    [],
    [{ x: 10, y: 20, width: 100, height: 200 }],
    [{ x: 0, y: 0, width: 900, height: 650 }],
    [{ x: 900, y: 650, width: 0, height: 0 }],
  ]) {
    const plan = planTraceImageExport(base, contributors, 2)
    assert.deepEqual(plan.logicalBounds, base)
    assert.equal(plan.didOverflowBase, false)
    assert.equal(plan.pixelWidth, 1800)
    assert.equal(plan.pixelHeight, 1300)
  }
})

test('adds symmetric 24-unit padding for one-side overflow', () => {
  const plan = planTraceImageExport(
    base,
    [{ x: 850, y: 100, width: 100, height: 50 }],
    1,
  )

  assert.deepEqual(plan.logicalBounds, {
    x: -24,
    y: -24,
    width: 998,
    height: 698,
  })
  assert.equal(plan.didOverflowBase, true)
})

test('unions negative, fractional, and multi-side overflow before padding', () => {
  const plan = planTraceImageExport(
    base,
    [
      { x: -10.25, y: 20, width: 5, height: 5 },
      { x: 100, y: -4.5, width: 10, height: 2 },
      { x: 899.75, y: 640, width: 20.5, height: 30.25 },
    ],
    1,
  )

  assert.deepEqual(plan.logicalBounds, {
    x: -34.25,
    y: -28.5,
    width: 978.5,
    height: 722.75,
  })
  assert.equal(plan.pixelWidth, 979)
  assert.equal(plan.pixelHeight, 723)
})

test('uses a tiny epsilon only when deciding whether content overflows', () => {
  const touching = planTraceImageExport(
    base,
    [{ x: -5e-7, y: 0, width: 900.000001, height: 650 }],
    1,
  )
  assert.deepEqual(touching.logicalBounds, base)

  const overflowing = planTraceImageExport(
    base,
    [{ x: -2e-6, y: 0, width: 900, height: 650 }],
    1,
  )
  assert.equal(overflowing.didOverflowBase, true)
})

test('keeps 1x and 2x output unchanged while under budget', () => {
  const oneX = planTraceImageExport(base, [], 1)
  assert.equal(oneX.effectivePixelRatio, 1)
  assert.equal(oneX.pixelWidth, 900)
  assert.equal(oneX.pixelHeight, 650)

  const twoX = planTraceImageExport(base, [], 2)
  assert.equal(twoX.effectivePixelRatio, 2)
  assert.equal(twoX.pixelWidth, 1800)
  assert.equal(twoX.pixelHeight, 1300)
})

test('reduces ratio for the side limit using ceiled dimensions', () => {
  const plan = planTraceImageExport(
    { x: 0, y: 0, width: 4096.25, height: 100 },
    [],
    2,
  )

  assert.equal(plan.pixelWidth, 8192)
  assert.ok(plan.pixelHeight <= 200)
  assert.ok(plan.effectivePixelRatio < 2)
  assert.equal(plan.didReduceResolution, true)
})

test('reduces ratio for the 12MP area limit', () => {
  const plan = planTraceImageExport(
    { x: 0, y: 0, width: 4096, height: 4096 },
    [],
    2,
  )

  assert.ok(plan.pixelWidth * plan.pixelHeight <= 12_000_000)
  assert.equal(plan.pixelWidth, plan.pixelHeight)
  assert.ok(plan.effectivePixelRatio < 1)
  assert.equal(plan.didReduceResolution, true)
})

test('handles extreme finite aspect ratios without dropping the thin axis', () => {
  const plan = planTraceImageExport(
    { x: -1e9, y: 0, width: 1e9, height: 0.001 },
    [],
    2,
  )

  assert.equal(plan.pixelWidth, 8192)
  assert.equal(plan.pixelHeight, 1)
  assert.ok(plan.effectivePixelRatio > 0)
})

test('rejects invalid base, contributor, and requested ratios', () => {
  assert.throws(
    () => planTraceImageExport(
      { x: 0, y: 0, width: Number.NaN, height: 10 },
      [],
      1,
    ),
    /base bounds/,
  )
  assert.throws(
    () => planTraceImageExport(
      base,
      [{ x: 0, y: 0, width: -1, height: 10 }],
      1,
    ),
    /contributor bounds/,
  )
  assert.throws(
    () => planTraceImageExport(base, [], 0),
    /pixel ratio/,
  )
})
