import { copyFileSync } from 'node:fs'
import { fileURLToPath } from 'node:url'
import { defineConfig } from 'vite'
import react from '@vitejs/plugin-react'
import { viteSingleFile } from 'vite-plugin-singlefile'

const iconSpriteSource = fileURLToPath(
  new URL(
    './node_modules/@tldraw/assets/icons/icon/0_merged.svg',
    import.meta.url,
  ),
)
const iconSpriteOutput = fileURLToPath(
  new URL('./dist/icon-sprite.svg', import.meta.url),
)
const repositoryRoot = fileURLToPath(new URL('../../../', import.meta.url))

export default defineConfig({
  base: './',
  envDir: repositoryRoot,
  plugins: [
    react(),
    viteSingleFile(),
    {
      name: 'copy-tldraw-icon-sprite',
      closeBundle() {
        copyFileSync(iconSpriteSource, iconSpriteOutput)
      },
    },
  ],
  build: {
    assetsInlineLimit: Number.MAX_SAFE_INTEGER,
    chunkSizeWarningLimit: 2500,
  },
})
