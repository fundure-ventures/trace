import assert from 'node:assert/strict'
import test from 'node:test'
import { viewportImagePlacement } from '../src/imagePlacement.ts'

test('device images fit and center in a panned, zoomed viewport, not the original page', () => {
  const viewport = { x: -2400, y: 1300, width: 400, height: 300 }
  const placement = viewportImagePlacement(viewport)
  assert.deepEqual(placement, { x: -2320, y: 1360, width: 240, height: 180 })
  assert.equal(placement.x + placement.width / 2, viewport.x + viewport.width / 2)
  assert.equal(placement.y + placement.height / 2, viewport.y + viewport.height / 2)
})

test('device placement follows a zoomed-out viewport without changing its bounds', () => {
  const viewport = { x: 1800, y: -900, width: 2000, height: 1500 }
  const original = { ...viewport }
  assert.deepEqual(
    viewportImagePlacement(viewport),
    { x: 2200, y: -600, width: 1200, height: 900 },
  )
  assert.deepEqual(viewport, original)
})
