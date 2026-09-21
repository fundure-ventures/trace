import { useCallback, useEffect, useRef } from 'react'
import { getAssetUrlsByImport } from '@tldraw/assets/imports.vite'
import { type Editor, Tldraw } from 'tldraw'
import { installTraceProductRenderer } from './productRenderer'
import { installTraceRenderer, reportTraceError } from './traceRenderer'
import { TraceAnnotationShapeUtil } from './traceAnnotationShape'

const importedAssetUrls = getAssetUrlsByImport()
const assetUrls = {
  ...importedAssetUrls,
  icons: Object.fromEntries(
    Object.keys(importedAssetUrls.icons).map((icon) => [
      icon,
      `./icon-sprite.svg#${icon}`,
    ]),
  ),
}
const shapeUtils = [TraceAnnotationShapeUtil]

// Product rendering is tldraw-only; production license provisioning is external.
export function App() {
  const uninstallBridgeRef = useRef<(() => void) | null>(null)
  const productMode = new URLSearchParams(window.location.search).get(
    'surface',
  ) === 'product'

  useEffect(() => {
    const handleError = (event: ErrorEvent) => {
      reportTraceError(event.error ?? event.message)
    }
    const handleUnhandledRejection = (event: PromiseRejectionEvent) => {
      reportTraceError(event.reason)
    }

    window.addEventListener('error', handleError)
    window.addEventListener('unhandledrejection', handleUnhandledRejection)

    return () => {
      window.removeEventListener('error', handleError)
      window.removeEventListener('unhandledrejection', handleUnhandledRejection)
      uninstallBridgeRef.current?.()
    }
  }, [])

  const handleMount = useCallback((editor: Editor) => {
    uninstallBridgeRef.current?.()
    uninstallBridgeRef.current = productMode
      ? installTraceProductRenderer(editor)
      : installTraceRenderer(editor)
  }, [productMode])

  return (
    <Tldraw
      assetUrls={assetUrls}
      hideUi={productMode}
      onMount={handleMount}
      shapeUtils={shapeUtils}
    />
  )
}
