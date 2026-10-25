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

test('exports the exact page only when there is no content', () => {
  const plan = planTraceImageExport(base, [], 2)
  assert.deepEqual(plan.logicalBounds, base)
  assert.equal(plan.didOverflowBase, false)
  assert.equal(plan.pixelWidth, 1800)
  assert.equal(plan.pixelHeight, 1300)
})

test('crops an inside sketch with 8 units of breathing room on every side', () => {
  const plan = planTraceImageExport(
    base,
    [{ x: 10, y: 20, width: 100, height: 200 }],
    2,
  )
  assert.deepEqual(plan.logicalBounds, {
    x: 2, y: 12, width: 116, height: 216,
  })
  assert.equal(plan.pixelWidth, 232)
  assert.equal(plan.pixelHeight, 432)
})

test('pads a full-page screenshot without cropping its internal whitespace', () => {
  const plan = planTraceImageExport(base, [base], 1)
  assert.deepEqual(plan.logicalBounds, {
    x: -8, y: -8, width: 916, height: 666,
  })
})

test('moving a screenshot moves the frame without retaining the original page', () => {
  for (const position of [
    { x: 100, y: 50 },
    { x: -100, y: -50 },
    { x: 2000, y: 3000 },
  ]) {
    const plan = planTraceImageExport(
      base,
      [{ ...base, ...position }],
      1,
    )
    assert.deepEqual(plan.logicalBounds, {
      x: position.x - 8,
      y: position.y - 8,
      width: 916,
      height: 666,
    })
  }
})

test('includes only current content bounds for one-side overflow', () => {
  const plan = planTraceImageExport(
    base,
    [{ x: 850, y: 100, width: 100, height: 50 }],
    1,
  )

  assert.deepEqual(plan.logicalBounds, {
    x: 842,
    y: 92,
    width: 116,
    height: 66,
  })
  assert.equal(plan.didOverflowBase, true)
})

test('preserves distances between separated negative and fractional marks', () => {
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
    x: -18.25,
    y: -12.5,
    width: 946.5,
    height: 690.75,
  })
  assert.equal(plan.pixelWidth, 947)
  assert.equal(plan.pixelHeight, 691)
})

test('resized screenshots use their current size rather than the page size', () => {
  const plan = planTraceImageExport(
    base,
    [{ x: 300, y: 200, width: 450, height: 325 }],
    1,
  )
  assert.deepEqual(plan.logicalBounds, {
    x: 292, y: 192, width: 466, height: 341,
  })
})

test('zero-size marks still receive breathing room', () => {
  const plan = planTraceImageExport(
    base,
    [{ x: 900, y: 650, width: 0, height: 0 }],
    1,
  )
  assert.deepEqual(plan.logicalBounds, {
    x: 892, y: 642, width: 16, height: 16,
  })
})

test('content framing is independent of the document page dimensions', () => {
  const content = [{ x: 100, y: 200, width: 300, height: 400 }]
  assert.deepEqual(
    planTraceImageExport(base, content, 2).logicalBounds,
    planTraceImageExport(
      { x: -500, y: -500, width: 2000, height: 2000 },
      content,
      2,
    ).logicalBounds,
  )
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

test('reduces resolution without cropping large content or its padding', () => {
  const plan = planTraceImageExport(
    base,
    [{ x: 10000, y: -500, width: 10000, height: 10000 }],
    2,
  )
  assert.deepEqual(plan.logicalBounds, {
    x: 9992, y: -508, width: 10016, height: 10016,
  })
  assert.ok(plan.pixelWidth * plan.pixelHeight <= 12_000_000)
  assert.ok(plan.effectivePixelRatio < 2)
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
