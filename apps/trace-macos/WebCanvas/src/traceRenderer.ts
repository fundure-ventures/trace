import {
  type Editor,
  type TLEventInfo,
  type TLDrawShape,
  type TLShapeId,
  type TLDrawShapeSegment,
  b64Vecs,
  createShapeId,
} from 'tldraw'

export const TRACE_PAGE_WIDTH = 1024
export const TRACE_PAGE_HEIGHT = 720

export interface Point {
  x: number
  y: number
  pressure: number | null
  connectsToPrevious: boolean
}

export interface PenUpdatePayload {
  strokeId: string
  committed: Point[]
  predicted: Point[]
  replacement: Point[] | null
  isFinal: boolean
  sampleIds: string[]
}

export interface MousePredictionPayload {
  strokeId: string
  anchor: Point | null
  predicted: Point[]
  isFinal: boolean
  sampleIds: string[]
}

type MousePhase = 'began' | 'moved' | 'ended'

export interface TraceRendererBridge {
  clear(): void
  applyPenUpdate(payload: PenUpdatePayload): void
  applyMousePrediction(payload: MousePredictionPayload): void
  emitMouseEventForTesting(
    phase: MousePhase,
    x: number,
    y: number,
  ): void
  emitRenderedSampleForTesting(sampleId: string): void
  getShapeCount(): number
  getShapeSummaryForTesting(): Array<{
    id: string
    type: string
    locked: boolean
  }>
  getMousePredictionShapeCountForTesting(): number
  getDrawingSize(): { width: number; height: number }
  lockAllShapesForTesting(): void
  setCameraForTesting(
    camera: { x: number; y: number; z: number },
  ): void
  getShapeViewportOriginForTesting(
    strokeId: string,
  ): { x: number; y: number } | null
  getMousePredictionViewportOriginForTesting(
    strokeId: string,
  ): { x: number; y: number } | null
}

export type TraceRendererHostMessage =
  | { type: 'ready' }
  | { type: 'rendered'; sampleIds: string[] }
  | { type: 'product-ready' }
  | { type: 'product-rendered'; sampleIds: string[] }
  | {
      type: 'product-change'
      documentId: string
      snapshotJson: string
      timedShapes: Array<{
        id: string
        startedAtAppClockSeconds: number
        endedAtAppClockSeconds: number
        pathLength: number
      }>
    }
  | { type: 'product-edit'; documentId: string; count: number }
  | {
      type: 'product-tool-change'
      documentId: string
      tool: 'select' | 'pen' | 'highlighter' | 'rectangle'
    }
  | {
      type: 'product-tool-preview'
      documentId: string
      tool: 'select' | 'pen' | 'highlighter' | 'rectangle' | null
    }
  | {
      type: 'product-history'
      documentId: string
      canUndo: boolean
      canRedo: boolean
    }
  | {
      type: 'product-export-resolution'
      documentId: string
      requestedPixelRatio: number
      effectivePixelRatio: number
      bounds: {
        x: number
        y: number
        width: number
        height: number
      }
      pixelWidth: number
      pixelHeight: number
    }
  | {
      type: 'mouse'
      phase: MousePhase
      x: number
      y: number
      pressure: number | null
    }
  | { type: 'error'; message: string }

interface WebKitMessageHandler {
  postMessage(message: TraceRendererHostMessage): void
}

declare global {
  interface Window {
    traceRenderer?: TraceRendererBridge
    webkit?: {
      messageHandlers?: {
        traceRenderer?: WebKitMessageHandler
      }
    }
  }
}

type StoredPoint = Point
type PagePoint = {
  x: number
  y: number
  z: number
  connectsToPrevious: boolean
}

export function postToTraceHost(message: TraceRendererHostMessage): void {
  try {
    window.webkit?.messageHandlers?.traceRenderer?.postMessage(message)
  } catch (error) {
    console.error('Trace renderer host message failed', error)
  }
}

export function reportTraceError(error: unknown): void {
  const message = error instanceof Error ? error.message : String(error)
  postToTraceHost({ type: 'error', message })
}

export function installTraceRenderer(editor: Editor): () => void {
  const committedByStroke = new Map<string, StoredPoint[]>()
  const pendingAnimationFrames = new Set<number>()
  let activeMousePointerId: number | null = null
  let lastMousePoint: {
    x: number
    y: number
    pressure: number | null
  } | null = null
  let disposed = false

  const scheduleRendered = (sampleIds: string[]) => {
    const copiedSampleIds = [...sampleIds]
    const frameId = window.requestAnimationFrame(() => {
      pendingAnimationFrames.delete(frameId)
      if (!disposed) {
        postToTraceHost({ type: 'rendered', sampleIds: copiedSampleIds })
      }
    })
    pendingAnimationFrames.add(frameId)
  }

  const postMouseEvent = (
    phase: MousePhase,
    x: number,
    y: number,
    pressure: number | null = null,
  ) => {
    postToTraceHost({
      type: 'mouse',
      phase,
      x: clampUnit(x),
      y: clampUnit(y),
      pressure,
    })
  }

  const handleEditorEvent = (event: TLEventInfo) => {
    if (event.type === 'misc') {
      if (
        event.name !== 'tick'
        && activeMousePointerId !== null
        && lastMousePoint !== null
      ) {
        postMouseEvent(
          'ended',
          lastMousePoint.x,
          lastMousePoint.y,
          lastMousePoint.pressure,
        )
        activeMousePointerId = null
        lastMousePoint = null
      }
      return
    }
    if (event.type !== 'pointer' || event.isPen) {
      return
    }
    if (event.name === 'pointer_down') {
      if (event.button !== 0 || editor.getCurrentToolId() !== 'draw') {
        return
      }
      activeMousePointerId = event.pointerId
      lastMousePoint = postMousePoint(
        editor,
        event,
        'began',
        postMouseEvent,
      )
      return
    }
    if (event.pointerId !== activeMousePointerId) {
      return
    }
    if (event.name === 'pointer_move') {
      lastMousePoint = postMousePoint(
        editor,
        event,
        'moved',
        postMouseEvent,
      )
      return
    }
    if (event.name === 'pointer_up') {
      postMousePoint(editor, event, 'ended', postMouseEvent)
      activeMousePointerId = null
      lastMousePoint = null
    }
  }

  editor.on('event', handleEditorEvent)

  const bridge: TraceRendererBridge = {
    clear() {
      try {
        committedByStroke.clear()
        editor.run(
          () => {
            editor.deleteShapes([...editor.getCurrentPageShapeIds()])
          },
          { ignoreShapeLock: true },
        )
      } catch (error) {
        reportTraceError(error)
      }
    },

    applyPenUpdate(payload) {
      try {
        assertPenUpdatePayload(payload)

        const priorCommitted = committedByStroke.get(payload.strokeId) ?? []
        const nextCommitted =
          payload.replacement === null
            ? [...priorCommitted, ...copyPoints(payload.committed)]
            : copyPoints(payload.replacement)

        committedByStroke.set(payload.strokeId, nextCommitted)

        const visiblePoints = payload.isFinal
          ? nextCommitted
          : [...nextCommitted, ...copyPoints(payload.predicted)]

        upsertDrawShape(
          editor,
          createShapeId(`trace-renderer-${payload.strokeId}`),
          visiblePoints,
          payload.isFinal,
        )
        scheduleRendered(payload.sampleIds)
      } catch (error) {
        reportTraceError(error)
      }
    },

    applyMousePrediction(payload) {
      try {
        assertMousePredictionPayload(payload)
        updateMousePrediction(editor, payload)
        scheduleRendered(payload.sampleIds)
      } catch (error) {
        reportTraceError(error)
      }
    },

    emitMouseEventForTesting(phase, x, y) {
      editor.setCurrentTool('draw')
      const viewport = editor.getViewportScreenBounds()
      const point = {
        x: viewport.x + clampUnit(x) * TRACE_PAGE_WIDTH,
        y: viewport.y + clampUnit(y) * TRACE_PAGE_HEIGHT,
        z: 0.5,
      }
      handleEditorEvent({
        type: 'pointer',
        name:
          phase === 'began'
            ? 'pointer_down'
            : phase === 'moved'
              ? 'pointer_move'
              : 'pointer_up',
        point,
        pointerId: 9_999,
        button: 0,
        isPen: false,
        target: 'canvas',
        shiftKey: false,
        altKey: false,
        ctrlKey: false,
        metaKey: false,
        accelKey: false,
      })
    },

    emitRenderedSampleForTesting(sampleId) {
      postToTraceHost({
        type: 'rendered',
        sampleIds: [sampleId],
      })
    },

    getShapeCount() {
      return editor.getCurrentPageShapeIds().size
    },

    getShapeSummaryForTesting() {
      return editor.getCurrentPageShapes().map((shape) => ({
        id: String(shape.id),
        type: shape.type,
        locked: shape.isLocked,
      }))
    },

    getMousePredictionShapeCountForTesting() {
      return editor
        .getCurrentPageShapes()
        .filter((shape) =>
          String(shape.id).includes('trace-mouse-prediction-'),
        ).length
    },

    getDrawingSize() {
      return {
        width: TRACE_PAGE_WIDTH,
        height: TRACE_PAGE_HEIGHT,
      }
    },

    lockAllShapesForTesting() {
      editor.toggleLock([...editor.getCurrentPageShapeIds()])
    },

    setCameraForTesting(camera) {
      editor.setCamera(camera)
    },

    getShapeViewportOriginForTesting(strokeId) {
      return getShapeViewportOrigin(
        editor,
        createShapeId(`trace-renderer-${strokeId}`),
      )
    },

    getMousePredictionViewportOriginForTesting(strokeId) {
      return getShapeViewportOrigin(
        editor,
        createShapeId(`trace-mouse-prediction-${strokeId}`),
      )
    },
  }

  window.traceRenderer = bridge
  postToTraceHost({ type: 'ready' })

  return () => {
    disposed = true
    editor.off('event', handleEditorEvent)
    for (const frameId of pendingAnimationFrames) {
      window.cancelAnimationFrame(frameId)
    }
    pendingAnimationFrames.clear()

    if (window.traceRenderer === bridge) {
      delete window.traceRenderer
    }
  }
}

function getShapeViewportOrigin(
  editor: Editor,
  shapeId: TLShapeId,
): { x: number; y: number } | null {
  const shape = editor.getShape(shapeId)
  if (!shape) {
    return null
  }
  const viewport = editor.getViewportScreenBounds()
  const point = editor.pageToScreen({ x: shape.x, y: shape.y })
  return {
    x: point.x - viewport.x,
    y: point.y - viewport.y,
  }
}

function upsertDrawShape(
  editor: Editor,
  shapeId: TLShapeId,
  points: StoredPoint[],
  isFinal: boolean,
  styleSource?: TLDrawShape,
  isLocked = false,
): void {
  const existingShape = editor.getShape(shapeId)

  if (points.length === 0) {
    if (existingShape) {
      editor.deleteShape(existingShape)
    }
    return
  }

  if (existingShape && existingShape.type !== 'draw') {
    throw new Error(`Shape id collision for ${shapeId}`)
  }

  const viewport = editor.getViewportScreenBounds()
  const pagePoints = points.map((point) => {
    const pagePoint = editor.screenToPage({
      x: viewport.x + clampUnit(point.x) * TRACE_PAGE_WIDTH,
      y: viewport.y + clampUnit(point.y) * TRACE_PAGE_HEIGHT,
    })
    return {
      x: pagePoint.x,
      y: pagePoint.y,
      z: point.pressure ?? 0.5,
      connectsToPrevious: point.connectsToPrevious,
    }
  })

  const originX = Math.min(...pagePoints.map((point) => point.x))
  const originY = Math.min(...pagePoints.map((point) => point.y))
  const segments = makeSegments(pagePoints, originX, originY)

  const props: TLDrawShape['props'] = {
    color: styleSource?.props.color ?? 'black',
    fill: 'none',
    dash: styleSource?.props.dash ?? 'draw',
    size: styleSource?.props.size ?? 'm',
    segments,
    isComplete: isFinal,
    isClosed: false,
    isPen:
      styleSource?.props.isPen
      ?? points.some((point) => point.pressure !== null),
    scale: styleSource?.props.scale ?? 1,
    scaleX: styleSource?.props.scaleX ?? 1,
    scaleY: styleSource?.props.scaleY ?? 1,
  }

  if (existingShape) {
    editor.updateShape<TLDrawShape>({
      id: shapeId,
      type: 'draw',
      x: originX,
      y: originY,
      props,
    })
    return
  }

  editor.createShape<TLDrawShape>({
    id: shapeId,
    type: 'draw',
    x: originX,
    y: originY,
    isLocked,
    props,
  })
}

function postMousePoint(
  editor: Editor,
  event: Extract<TLEventInfo, { type: 'pointer' }>,
  phase: MousePhase,
  post: (
    phase: MousePhase,
    x: number,
    y: number,
    pressure: number | null,
  ) => void,
): {
  x: number
  y: number
  pressure: number | null
} {
  const viewport = editor.getViewportScreenBounds()
  const point = {
    x: (event.point.x - viewport.x) / TRACE_PAGE_WIDTH,
    y: (event.point.y - viewport.y) / TRACE_PAGE_HEIGHT,
    pressure: Number.isFinite(event.point.z)
      ? event.point.z ?? null
      : null,
  }
  post(
    phase,
    point.x,
    point.y,
    point.pressure,
  )
  return point
}

function updateMousePrediction(
  editor: Editor,
  payload: MousePredictionPayload,
): void {
  const shapeId = createShapeId(
    `trace-mouse-prediction-${payload.strokeId}`,
  )
  editor.run(
    () => {
      if (
        payload.isFinal
        || payload.anchor === null
        || payload.predicted.length === 0
      ) {
        const existing = editor.getShape(shapeId)
        if (existing) {
          editor.deleteShape(existing)
        }
        return
      }
      const styleSource = editor
        .getCurrentPageShapes()
        .filter((shape): shape is TLDrawShape => {
          const id = String(shape.id)
          return shape.type === 'draw'
            && shape.id !== shapeId
            && !id.includes('trace-renderer-')
            && !id.includes('trace-mouse-prediction-')
        })
        .at(-1)
      upsertDrawShape(
        editor,
        shapeId,
        [payload.anchor, ...copyPoints(payload.predicted)],
        false,
        styleSource,
        true,
      )
    },
    {
      history: 'ignore',
      ignoreShapeLock: true,
    },
  )
}

function makeSegments(
  points: PagePoint[],
  originX: number,
  originY: number,
): TLDrawShapeSegment[] {
  const pointGroups: Array<Array<{ x: number; y: number; z: number }>> = []

  for (const [index, point] of points.entries()) {
    if (index === 0 || !point.connectsToPrevious) {
      pointGroups.push([])
    }

    pointGroups.at(-1)!.push({
      x: point.x - originX,
      y: point.y - originY,
      z: point.z,
    })
  }

  return pointGroups.map((segmentPoints) => ({
    type: 'free',
    path: b64Vecs.encodePoints(segmentPoints),
  }))
}

function copyPoints(points: Point[]): StoredPoint[] {
  return points.map((point) => ({ ...point }))
}

function clampUnit(value: number): number {
  return Math.min(1, Math.max(0, value))
}

function assertPenUpdatePayload(payload: unknown): asserts payload is PenUpdatePayload {
  if (!isRecord(payload)) {
    throw new Error('Pen update payload must be an object')
  }

  assertString(payload.strokeId, 'strokeId')
  assertPointArray(payload.committed, 'committed')
  assertPointArray(payload.predicted, 'predicted')

  if (payload.replacement !== null) {
    assertPointArray(payload.replacement, 'replacement')
  }

  if (typeof payload.isFinal !== 'boolean') {
    throw new Error('isFinal must be a boolean')
  }

  if (!Array.isArray(payload.sampleIds)) {
    throw new Error('sampleIds must be an array')
  }

  payload.sampleIds.forEach((sampleId, index) => {
    assertString(sampleId, `sampleIds[${index}]`)
  })
}

function assertMousePredictionPayload(
  payload: unknown,
): asserts payload is MousePredictionPayload {
  if (!isRecord(payload)) {
    throw new Error('Mouse prediction payload must be an object')
  }
  assertString(payload.strokeId, 'strokeId')
  if (payload.anchor !== null) {
    assertPoint(payload.anchor, 'anchor')
  }
  assertPointArray(payload.predicted, 'predicted')
  if (typeof payload.isFinal !== 'boolean') {
    throw new Error('isFinal must be a boolean')
  }
  if (!Array.isArray(payload.sampleIds)) {
    throw new Error('sampleIds must be an array')
  }
  payload.sampleIds.forEach((sampleId, index) => {
    assertString(sampleId, `sampleIds[${index}]`)
  })
}

function assertPointArray(value: unknown, fieldName: string): asserts value is Point[] {
  if (!Array.isArray(value)) {
    throw new Error(`${fieldName} must be an array`)
  }

  value.forEach((point, index) => {
    assertPoint(point, `${fieldName}[${index}]`)
  })
}

function assertPoint(value: unknown, fieldName: string): asserts value is Point {
  if (!isRecord(value)) {
    throw new Error(`${fieldName} must be an object`)
  }
  if (!Number.isFinite(value.x) || !Number.isFinite(value.y)) {
    throw new Error(`${fieldName} x and y must be finite numbers`)
  }
  if (value.pressure !== null && !Number.isFinite(value.pressure)) {
    throw new Error(`${fieldName} pressure must be a finite number or null`)
  }
  if (typeof value.connectsToPrevious !== 'boolean') {
    throw new Error(`${fieldName} connectsToPrevious must be a boolean`)
  }
}

function assertFiniteNumber(value: unknown, fieldName: string): asserts value is number {
  if (typeof value !== 'number' || !Number.isFinite(value)) {
    throw new Error(`${fieldName} must be a finite number`)
  }
}

function assertString(value: unknown, fieldName: string): asserts value is string {
  if (typeof value !== 'string' || value.length === 0) {
    throw new Error(`${fieldName} must be a non-empty string`)
  }
}

function isRecord(value: unknown): value is Record<string, unknown> {
  return typeof value === 'object' && value !== null
}
