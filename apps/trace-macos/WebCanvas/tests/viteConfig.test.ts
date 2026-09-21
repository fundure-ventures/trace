import assert from 'node:assert/strict'
import test from 'node:test'
import { fileURLToPath } from 'node:url'
import config from '../vite.config.ts'

test('loads Vite environment variables from the repository root', () => {
  assert.equal(typeof config, 'object')
  assert.equal(
    config.envDir,
    fileURLToPath(new URL('../../../../', import.meta.url)),
  )
})
