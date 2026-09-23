import {
  Box,
  DefaultColorStyle,
  DefaultFillStyle,
  DefaultSizeStyle,
  STROKE_SIZES,
  type Editor,
  type TLDefaultColorStyle,
  type TLDrawShape,
  type TLFrameShape,
  type TLGeoShape,
  type TLImageAsset,
  type TLImageShape,
  type TLShape,
  type TLShapeId,
  type TLEventInfo,
  b64Vecs,
  createShapeId,
  getSvgAsImage,
  Vec,
} from 'tldraw'
import {
  DefaultColorThemePalette,
  GeoShapeGeoStyle,
} from '@tldraw/editor'
import { AssetRecordType } from '@tldraw/tlschema'
import { postToTraceHost, reportTraceError } from './traceRenderer'
import {
  TRACE_ANNOTATION_SHAPE_TYPE,
  type TraceAnnotationShape,
} from './traceAnnotationShape'
import {
  planTraceImageExport,
  type LogicalBounds,
  type TraceImageExportPlan,
} from './exportPlanning'

export type ProductBrush = 'pen' | 'highlighter'
export type ProductCanvasTool =
  | 'select'
  | 'pen'
  | 'highlighter'
  | 'rectangle'
export type ProductGrid =
  | 'none'
  | 'dots'
  | 'square'
  | 'horizontal'
  | 'vertical'

export interface ProductPoint {
  x: number
  y: number
  pressure: number | null
  connectsToPrevious: boolean
}

export interface ProductStroke {
  id: string
  color: TLDefaultColorStyle
  brush: ProductBrush
  width: number
  annotationId: number | null
  annotationDiameter: number
  points: ProductPoint[]
}

export interface ProductTool {
  tool: ProductCanvasTool
  color: TLDefaultColorStyle
  brush: ProductBrush
  width: number
  gridStyle: ProductGrid
  gridSpacing: number
}

export interface ProductTimedShape {
  id: string
  startedAtAppClockSeconds: number
  endedAtAppClockSeconds: number
  pathLength: number
}

export interface ProductShapeAnnotation {
  shapeId: string
  annotationId: number
  diameter: number
}

export interface ProductDocument {
  id: string
  pageKind: 'blank' | 'screenshot'
  backgroundColor: string
  width: number
  height: number
  backgroundDataUrl: string
  snapshotJson: string | null
  strokes: ProductStroke[]
  shapeAnnotations: ProductShapeAnnotation[]
}

export interface ProductAnnotationUpdate {
  strokeId: string
  color: TLDefaultColorStyle
  brush: ProductBrush
  width: number
  committed: ProductPoint[]
  predicted: ProductPoint[]
  replacement: ProductPoint[] | null
  isFinal: boolean
  sampleIds: string[]
}

export interface ProductImage {
  dataUrl: string
  name: string
  mimeType: string
  width: number
  height: number
}

export interface TraceProductRendererBridge {
  setDocument(document: ProductDocument): void
  frameDocument(viewportWidth: number, viewportHeight: number): void
  syncStrokes(
    strokes: ProductStroke[],
    shapeAnnotations: ProductShapeAnnotation[],
  ): void
  setTool(tool: ProductTool): void
  setBackground(color: string): void
  applyAnnotationUpdate(update: ProductAnnotationUpdate): void
  insertImage(image: ProductImage): void
  insertImages(images: ProductImage[]): void
  waitForIdle(): Promise<void>
  getSnapshot(): {
    documentId: string
    snapshotJson: string
    timedShapes: ProductTimedShape[]
  }
  getSnapshotJson(): string
  exportPng(
    pixelRatio: number,
    expectedDocumentId: string,
  ): Promise<{
    documentId: string
    dataUrl: string
  }>
  undo(): void
  redo(): void
  clearUserContent(): void
  emitPointerForTesting(
    phase: 'began' | 'moved' | 'ended',
    x: number,
    y: number,
  ): void
  setZoomForTesting(zoom: number): void
  setTimingFinalizationDelayForTesting(
    delayMilliseconds: number,
  ): void
  selectFirstUserShapeForTesting(): boolean
  setFirstUserImagePositionForTesting(
    x: number,
    y: number,
  ): boolean
  setExportFixtureForTesting(
    fixture: 'none' | 'masked' | 'rotated',
  ): void
  clearSelectionForTesting(): void
  deleteSelectionForTesting(): void
  getStateForTesting(): {
    hideUi: true
    uiElementCount: number
    shapeCount: number
    backgroundCount: number
    backgroundLocked: boolean
    userImageCount: number
    selectedUserImageCount: number
    userImageBounds: Array<{
      x: number
      y: number
      width: number
      height: number
    }>
    annotationCount: number
    annotationCenter: {
      x: number
      y: number
      width: number
      height: number
      text: string
      fill: string
      textColor: string
      fontFamily: string
      opacity: number
    } | null
    annotationIsTopmost: boolean
    lockedPenCount: number
    derivedLayersAtBack: boolean
    exportIncludesGrid: boolean
    backgroundSource: string | null
    renderedBackgroundColor: string
    productTool: ProductCanvasTool
    rectangleCount: number
    zoom: number
    viewportWidth: number
    viewportHeight: number
    viewportCenterX: number
    viewportCenterY: number
    pageWidth: number
    pageHeight: number
    selectedShapeCount: number
    timedShapeCount: number
    timedAnnotationCount: number
    timedAnnotationTexts: string[]
    selectedTool: string
    color: TLDefaultColorStyle
    opacity: number
    width: number
    gridStyle: ProductGrid
    gridSpacing: number
    drawWidths: number[]
    drawOpacities: number[]
    drawColors: TLDefaultColorStyle[]
    lastExportPlan: TraceImageExportPlan | null
  }
}

declare global {
  interface Window {
    traceProductRenderer?: TraceProductRendererBridge
  }
}

const BACKGROUND_SHAPE_PREFIX = 'trace-background-'
const GRID_SHAPE_PREFIX = 'trace-grid-'
const PEN_SHAPE_PREFIX = 'trace-product-stroke-'
const ANNOTATION_SHAPE_PREFIX = 'trace-annotation-'
const USER_ANNOTATION_SHAPE_PREFIX = 'trace-annotation-user-'
const KEYBOARD_ZOOM_INCREMENT = 0.25
const MIN_KEYBOARD_ZOOM = 0.05
const MAX_KEYBOARD_ZOOM = 8
const USER_IMAGE_PREFIX = 'trace-image-'
const CAPTURE_IMAGE_PREFIX = `${USER_IMAGE_PREFIX}capture-`
const CAPTURE_IMAGE_MIGRATED_META_KEY =
  'traceCaptureImageMigrated'
const TIMING_STARTED_META_KEY =
  'traceStartedAtAppClockSeconds'
const TIMING_ENDED_META_KEY =
  'traceEndedAtAppClockSeconds'

export function installTraceProductRenderer(editor: Editor): () => void {
  const committedByStroke = new Map<string, ProductPoint[]>()
  let pageWidth = 1024
  let pageHeight = 720
  let exportBaseWidth = 1024
  let exportBaseHeight = 720
  let currentDocumentId = 'document'
  let currentPageKind: ProductDocument['pageKind'] = 'blank'
  let currentBackgroundColor = '#ffffff'
  let pendingDropCount = 0
  let dropIdleResolvers: Array<() => void> = []
  let pendingTimingCount = 0
  let timingIdleResolvers: Array<() => void> = []
  let suppressUserEdit = false
  let userEditPending = false
  let lastExportPlan: TraceImageExportPlan | null = null
  let temporarySelectActive = false
  let temporaryDrawActive = false
  let commandSelectHeld = false
  let lastDrawingTool: Exclude<ProductCanvasTool, 'select'> = 'pen'
  let activeTimedGesture: {
    documentId: string
    shapeType: 'draw' | 'geo'
    startedAtAppClockSeconds: number
  } | null = null
  let recentlyCompletedGesture: {
    documentId: string
    shapeType: 'draw' | 'geo'
    startedAtAppClockSeconds: number
    endedAtAppClockSeconds: number
    expiresAtAppClockSeconds: number
  } | null = null
  const explicitlyReportedRecordIds = new Set<string>()
  const knownUserTimedShapeIds = new Set<TLShapeId>()
  const pendingShapeStarts = new Map<
    TLShapeId,
    {
      documentId: string
      shapeType: 'draw' | 'geo'
      startedAtAppClockSeconds: number
    }
  >()
  let currentTool: ProductTool = {
    tool: 'pen',
    color: 'red',
    brush: 'pen',
    width: 5.25,
    gridStyle: 'none',
    gridSpacing: 8,
  }
  let timingFinalizationDelayMilliseconds = 0
  let hostMutationDepth = 0
  let changeTimer: number | null = null

  const runHostMutation = (work: () => void) => {
    hostMutationDepth += 1
    try {
      editor.run(work, {
        history: 'ignore',
        ignoreShapeLock: true,
      })
    } finally {
      hostMutationDepth -= 1
    }
  }

  const postDocumentChange = (userEdit = false) => {
    if (hostMutationDepth > 0) return
    postHistory()
    if (
      userEdit
      && !suppressUserEdit
      && !userEditPending
    ) {
      userEditPending = true
      postToTraceHost({
        type: 'product-edit',
        documentId: currentDocumentId,
        count: 1,
      })
    }
    const documentId = currentDocumentId
    if (changeTimer !== null) {
      window.clearTimeout(changeTimer)
    }
    changeTimer = window.setTimeout(() => {
      changeTimer = null
      if (documentId !== currentDocumentId) return
      userEditPending = false
      explicitlyReportedRecordIds.clear()
      postToTraceHost({
        type: 'product-change',
        documentId,
        snapshotJson: snapshotJson(editor),
        timedShapes: collectTimedShapes(editor),
      })
    }, 120)
  }

  const flushPendingDocumentChange = () => {
    if (changeTimer === null) return
    window.clearTimeout(changeTimer)
    changeTimer = null
    userEditPending = false
    explicitlyReportedRecordIds.clear()
    postToTraceHost({
      type: 'product-change',
      documentId: currentDocumentId,
      snapshotJson: snapshotJson(editor),
      timedShapes: collectTimedShapes(editor),
    })
    postHistory()
  }

  const postHistory = () => {
    postToTraceHost({
      type: 'product-history',
      documentId: currentDocumentId,
      canUndo: editor.getCanUndo(),
      canRedo: editor.getCanRedo(),
    })
  }

  const postTemporaryTool = (
    tool: ProductCanvasTool | null,
  ) => {
    postToTraceHost({
      type: 'product-tool-preview',
      documentId: currentDocumentId,
      tool,
    })
  }

  const activateTemporarySelect = () => {
    if (temporarySelectActive) return
    temporarySelectActive = true
    editor.setCurrentTool('select')
    postTemporaryTool('select')
  }

  const releaseTemporarySelect = (clearSelection = false) => {
    if (!temporarySelectActive) return
    temporarySelectActive = false
    runHostMutation(() => {
      if (clearSelection) {
        editor.selectNone()
      }
      applyTool(editor, currentTool)
    })
    postTemporaryTool(null)
  }

  const reconcileTemporarySelect = () => {
    if (
      !temporarySelectActive
      || commandSelectHeld
      || editor.getSelectedShapeIds().length > 0
    ) {
      return
    }
    releaseTemporarySelect()
  }

  // The inverse of activateTemporarySelect/releaseTemporarySelect: when the
  // persistent tool is select, holding Cmd temporarily switches to whichever
  // drawing tool was last used, so Cmd always toggles select<>draw.
  const temporaryDrawTool = (): ProductTool => ({
    ...currentTool,
    tool: lastDrawingTool,
    brush: lastDrawingTool === 'highlighter' ? 'highlighter' : 'pen',
  })

  const activateTemporaryDraw = () => {
    if (temporaryDrawActive) return
    temporaryDrawActive = true
    runHostMutation(() => {
      editor.selectNone()
      applyTool(editor, temporaryDrawTool())
    })
    postTemporaryTool(lastDrawingTool)
  }

  const releaseTemporaryDraw = () => {
    if (!temporaryDrawActive) return
    temporaryDrawActive = false
    runHostMutation(() => {
      applyTool(editor, currentTool)
    })
    postTemporaryTool(null)
  }

  const reconcileTemporaryDraw = () => {
    if (!temporaryDrawActive || editor.inputs.getIsPointing()) return
    if (commandSelectHeld) {
      // The rectangle (geo) tool reverts to select after each shape; while
      // Cmd is still held, re-arm it so consecutive shapes keep working.
      if (lastDrawingTool === 'rectangle') {
        runHostMutation(() => {
          editor.selectNone()
          applyTool(editor, temporaryDrawTool())
        })
      }
      return
    }
    releaseTemporaryDraw()
  }

  const restorePersistentRectangleTool = () => {
    if (
      temporarySelectActive
      || currentTool.tool !== 'rectangle'
    ) {
      return
    }
    runHostMutation(() => {
      editor.selectNone()
      applyTool(editor, currentTool)
    })
  }

  const selectProductTool = (
    tool: ProductCanvasTool,
    notifyHost: boolean,
  ) => {
    currentTool = {
      ...currentTool,
      tool,
      brush:
        tool === 'highlighter'
          ? 'highlighter'
          : tool === 'pen' || tool === 'rectangle'
            ? 'pen'
            : currentTool.brush,
    }
    if (tool !== 'select') {
      lastDrawingTool = tool
    }
    runHostMutation(() => {
      // Manually switching to a drawing tool must clear the current
      // selection: otherwise a selected shape (e.g. an image) keeps
      // intercepting pointer events instead of letting the user draw.
      if (tool !== 'select') {
        editor.selectNone()
      }
      applyTool(
        editor,
        currentTool,
        !temporarySelectActive && !temporaryDrawActive,
      )
    })
    if (notifyHost) {
      postToTraceHost({
        type: 'product-tool-change',
        documentId: currentDocumentId,
        tool,
      })
    }
  }

  const waitForDropIdle = async () => {
    if (pendingDropCount === 0) return
    await new Promise<void>((resolve) => {
      dropIdleResolvers.push(resolve)
    })
  }

  const finishDropWork = () => {
    pendingDropCount = Math.max(0, pendingDropCount - 1)
    if (pendingDropCount !== 0) return
    const resolvers = dropIdleResolvers
    dropIdleResolvers = []
    for (const resolve of resolvers) resolve()
  }

  const waitForTimingIdle = async () => {
    if (pendingTimingCount === 0) return
    await new Promise<void>((resolve) => {
      timingIdleResolvers.push(resolve)
    })
  }

  const finishTimingWork = () => {
    pendingTimingCount = Math.max(0, pendingTimingCount - 1)
    if (pendingTimingCount !== 0) return
    const resolvers = timingIdleResolvers
    timingIdleResolvers = []
    for (const resolve of resolvers) resolve()
  }

  const removeStoreListener = editor.store.listen(
    (entry) => {
      const now = Date.now() / 1000
      for (const shape of editor
        .getCurrentPageShapes()
        .filter(isUserTimedShape)
        .filter((shape) => !knownUserTimedShapeIds.has(shape.id))) {
        const shapeType = shape.type
        const active = activeTimedGesture
        const completed = recentlyCompletedGesture
        if (
          active
          && active.documentId === currentDocumentId
          && active.shapeType === shapeType
        ) {
          pendingShapeStarts.set(shape.id, {
            documentId: active.documentId,
            shapeType,
            startedAtAppClockSeconds:
              active.startedAtAppClockSeconds,
          })
          knownUserTimedShapeIds.add(shape.id)
        } else if (
          completed
          && completed.documentId === currentDocumentId
          && completed.shapeType === shapeType
          && now <= completed.expiresAtAppClockSeconds
        ) {
          pendingShapeStarts.set(shape.id, {
            documentId: completed.documentId,
            shapeType,
            startedAtAppClockSeconds:
              completed.startedAtAppClockSeconds,
          })
          knownUserTimedShapeIds.add(shape.id)
        } else if (
          editor.inputs.getIsPointing()
          && editor.getCurrentToolId() === shapeType
        ) {
          pendingShapeStarts.set(shape.id, {
            documentId: currentDocumentId,
            shapeType,
            startedAtAppClockSeconds: now,
          })
          knownUserTimedShapeIds.add(shape.id)
        }
      }
      const changedIds = [
        ...Object.keys(entry.changes.added),
        ...Object.keys(entry.changes.updated),
        ...Object.keys(entry.changes.removed),
      ]
      const explicitlyReported =
        changedIds.length > 0
        && changedIds.every((id) =>
          explicitlyReportedRecordIds.has(id),
        )
      const hostOwned =
        changedIds.length > 0
        && changedIds.every(isHostOwnedRecordId)
      if (!explicitlyReported && !hostOwned) {
        postDocumentChange(true)
      }
    },
    {
      scope: 'document',
      source: 'user',
    },
  )
  const removeSessionListener = editor.store.listen(
    reconcileTemporarySelect,
    { scope: 'session' },
  )
  const handleEditorEvent = (event: TLEventInfo) => {
    if (event.type !== 'pointer' || event.isPen) return
    if (
      event.name === 'pointer_down'
      && event.button === 0
      && (
        editor.getCurrentToolId() === 'draw'
        || editor.getCurrentToolId() === 'geo'
      )
    ) {
      const startedAtAppClockSeconds = Date.now() / 1000
      const shapeType = editor.getCurrentToolId() as 'draw' | 'geo'
      for (const shape of editor
        .getCurrentPageShapes()
        .filter(isUserTimedShape)
        .filter(
          (shape) =>
            shape.type === shapeType
            && !knownUserTimedShapeIds.has(shape.id),
        )) {
        pendingShapeStarts.set(shape.id, {
          documentId: currentDocumentId,
          shapeType,
          startedAtAppClockSeconds,
        })
        knownUserTimedShapeIds.add(shape.id)
      }
      activeTimedGesture = {
        documentId: currentDocumentId,
        shapeType,
        startedAtAppClockSeconds,
      }
      return
    }
    if (event.name === 'pointer_up') {
      const gesture = activeTimedGesture
      activeTimedGesture = null
      if (gesture) {
        const endedAtAppClockSeconds = Date.now() / 1000
        recentlyCompletedGesture = {
          ...gesture,
          endedAtAppClockSeconds,
          expiresAtAppClockSeconds:
            endedAtAppClockSeconds + 1,
        }
        pendingTimingCount += 1
        let attempts = 0
        let finished = false
        const finish = () => {
          if (finished) return
          finished = true
          finishTimingWork()
        }
        const finalizeGesture = () => {
          try {
            if (gesture.documentId !== currentDocumentId) {
              finish()
              return
            }
            for (const shape of editor
              .getCurrentPageShapes()
              .filter(isUserTimedShape)
              .filter(
                (shape) =>
                  shape.type === gesture.shapeType
                  && !knownUserTimedShapeIds.has(shape.id),
              )) {
              pendingShapeStarts.set(shape.id, {
                documentId: gesture.documentId,
                shapeType: gesture.shapeType,
                startedAtAppClockSeconds:
                  gesture.startedAtAppClockSeconds,
              })
              knownUserTimedShapeIds.add(shape.id)
            }
            const selectedCompletedShapes = editor
              .getSelectedShapes()
              .filter(
                (shape) =>
                  isUserTimedShape(shape)
                  && shape.type === gesture.shapeType
                  && typeof shape.meta[TIMING_STARTED_META_KEY]
                    !== 'number',
              )
            for (const shape of selectedCompletedShapes) {
              if (!pendingShapeStarts.has(shape.id)) {
                pendingShapeStarts.set(shape.id, {
                  documentId: gesture.documentId,
                  shapeType: gesture.shapeType,
                  startedAtAppClockSeconds:
                    gesture.startedAtAppClockSeconds,
                })
                knownUserTimedShapeIds.add(shape.id)
              }
            }
            const createdShapes = [...pendingShapeStarts]
              .filter(([, timing]) =>
                timing.documentId === gesture.documentId
                && timing.shapeType === gesture.shapeType
                && timing.startedAtAppClockSeconds
                  >= gesture.startedAtAppClockSeconds - 0.25
                && timing.startedAtAppClockSeconds
                  <= endedAtAppClockSeconds + 0.25,
              )
              .flatMap(([id]) => {
                const shape = editor.getShape(id)
                return shape && isUserTimedShape(shape)
                  ? [shape]
                  : []
              })
            if (createdShapes.length === 0) {
              if (attempts < 10) {
                attempts += 1
                window.setTimeout(finalizeGesture, 25)
              } else {
                finish()
              }
              return
            }
            runHostMutation(() => {
              editor.updateShapes(
                createdShapes.map((shape) => {
                  const timing = pendingShapeStarts.get(shape.id)
                  return {
                    id: shape.id,
                    type: shape.type,
                    meta: {
                      ...shape.meta,
                      [TIMING_STARTED_META_KEY]:
                        timing?.startedAtAppClockSeconds
                        ?? gesture.startedAtAppClockSeconds,
                      [TIMING_ENDED_META_KEY]:
                        endedAtAppClockSeconds,
                    },
                  }
                }),
              )
            })
            for (const shape of createdShapes) {
              pendingShapeStarts.delete(shape.id)
            }
            postDocumentChange()
            finish()
          } catch (error) {
            finish()
            reportTraceError(error)
          }
        }
        window.setTimeout(
          finalizeGesture,
          timingFinalizationDelayMilliseconds,
        )
      }
      queueMicrotask(() => {
        reconcileTemporarySelect()
        reconcileTemporaryDraw()
        restorePersistentRectangleTool()
      })
    }
  }
  editor.on('event', handleEditorEvent)

  const removeBeforeCreate = editor.sideEffects.registerBeforeCreateHandler(
    'shape',
    (shape, source) => {
      if (
        hostMutationDepth > 0
        || source !== 'user'
        || shape.type !== 'draw'
      ) {
        return shape
      }
      return {
        ...shape,
        opacity: opacityForProductTool(currentTool),
        props: {
          ...shape.props,
          color: currentTool.color,
          size: 'm',
          scale: scaleForWidth(currentTool.width),
        },
      }
    },
  )

  const insertUserImages = (images: ProductImage[]) => {
    if (images.length === 0) return
    const placements = images.length > 1
      ? batchImagePlacements(
          images.length,
          pageWidth,
          pageHeight,
        )
      : [undefined]
    editor.run(() => {
      images.forEach((image, index) => {
        const stableId =
          `${USER_IMAGE_PREFIX}${crypto.randomUUID()}`
        const shapeId = createShapeId(stableId)
        explicitlyReportedRecordIds.add(shapeId)
        explicitlyReportedRecordIds.add(
          AssetRecordType.createId(stableId),
        )
        insertImage(
          editor,
          image,
          pageWidth,
          pageHeight,
          false,
          stableId,
          placements[index],
          false,
        )
      })
    })
    editor.selectNone()
    selectProductTool('pen', true)
    userEditPending = true
    postToTraceHost({
      type: 'product-edit',
      documentId: currentDocumentId,
      count: 1,
    })
    postDocumentChange()
  }

  const bridge: TraceProductRendererBridge = {
    setDocument(document) {
      if (changeTimer !== null) {
        window.clearTimeout(changeTimer)
        changeTimer = null
      }
      userEditPending = false
      commandSelectHeld = false
      temporarySelectActive = false
      temporaryDrawActive = false
      activeTimedGesture = null
      recentlyCompletedGesture = null
      explicitlyReportedRecordIds.clear()
      knownUserTimedShapeIds.clear()
      pendingShapeStarts.clear()
      const previousPageWidth = pageWidth
      const previousPageHeight = pageHeight
      const resizesCurrentDocument =
        currentDocumentId === document.id
      pageWidth = positive(document.width, 1024)
      pageHeight = positive(document.height, 720)
      exportBaseWidth = document.width
      exportBaseHeight = document.height
      lastExportPlan = null
      currentDocumentId = document.id
      currentPageKind = document.pageKind
      currentBackgroundColor = document.backgroundColor
      setCanvasBackground(
        editor,
        currentBackgroundColor,
      )
      runHostMutation(() => {
        committedByStroke.clear()
        for (const stroke of document.strokes) {
          committedByStroke.set(
            stroke.id,
            stroke.points.map((point) => ({ ...point })),
          )
        }
        if (document.snapshotJson) {
          editor.loadSnapshot(JSON.parse(document.snapshotJson))
        } else {
          editor.selectNone()
          editor.deleteShapes([...editor.getCurrentPageShapeIds()])
          editor.deleteAssets(editor.getAssets())
          clearCaptureImageMigration(editor)
        }
        if (
          resizesCurrentDocument
          && (
            previousPageWidth !== pageWidth
            || previousPageHeight !== pageHeight
          )
        ) {
          preserveUserShapePlacement(
            editor,
            previousPageWidth,
            previousPageHeight,
            pageWidth,
            pageHeight,
          )
        }
        removeBackground(editor, currentDocumentId)
        if (currentPageKind === 'screenshot') {
          migrateCaptureImage(
            editor,
            currentDocumentId,
            document.backgroundDataUrl,
            pageWidth,
            pageHeight,
          )
        }
        removeGrid(editor, currentDocumentId)
        syncPenStrokes(
          editor,
          document.strokes,
          pageWidth,
          pageHeight,
        )
        syncShapeAnnotations(
          editor,
          document.shapeAnnotations,
          pageWidth,
          pageHeight,
        )
        editor.selectNone()
        applyTool(editor, currentTool)
        editor.clearHistory()
        for (const shape of editor
          .getCurrentPageShapes()
          .filter(isUserTimedShape)) {
          knownUserTimedShapeIds.add(shape.id)
        }
      })
      postHistory()
      postDocumentChange()
    },

    frameDocument(viewportWidth, viewportHeight) {
      editor.updateViewportScreenBounds(
        new Box(
          0,
          0,
          positive(viewportWidth, 1),
          positive(viewportHeight, 1),
        ),
      )
      editor.zoomToBounds(
        new Box(0, 0, pageWidth, pageHeight),
        {
          inset: 0,
          animation: { duration: 0 },
        },
      )
    },

    syncStrokes(strokes, shapeAnnotations) {
      committedByStroke.clear()
      for (const stroke of strokes) {
        committedByStroke.set(
          stroke.id,
          stroke.points.map((point) => ({ ...point })),
        )
      }
      runHostMutation(() => {
        syncPenStrokes(
          editor,
          strokes,
          pageWidth,
          pageHeight,
        )
        syncShapeAnnotations(
          editor,
          shapeAnnotations,
          pageWidth,
          pageHeight,
        )
      })
      postDocumentChange()
    },

    setTool(tool) {
      currentTool = {
        tool: tool.tool,
        color: tool.color,
        brush: tool.brush,
        width: positive(tool.width, 5.25),
        gridStyle: tool.gridStyle,
        gridSpacing: positive(tool.gridSpacing, 8),
      }
      if (tool.tool !== 'select') {
        lastDrawingTool = tool.tool
      }
      runHostMutation(() => {
        // Manually switching to a drawing tool must clear the current
        // selection so a selected shape can't keep blocking drawing.
        if (tool.tool !== 'select') {
          editor.selectNone()
        }
        applyTool(
          editor,
          currentTool,
          !temporarySelectActive && !temporaryDrawActive,
        )
      })
      postDocumentChange()
    },

    setBackground(color) {
      currentBackgroundColor = color
      setCanvasBackground(editor, color)
    },

    applyAnnotationUpdate(update) {
      runHostMutation(() => {
        const shapeId = createShapeId(
          `${PEN_SHAPE_PREFIX}${update.strokeId}`,
        )
        const previous =
          committedByStroke.get(update.strokeId) ?? []
        const committed = update.replacement
          ?? [...previous, ...update.committed]
        committedByStroke.set(update.strokeId, committed)
        const visible = update.isFinal
          ? committed
          : [...committed, ...update.predicted]
        if (visible.length === 0) {
          const existing = editor.getShape(shapeId)
          if (existing) editor.deleteShape(existing)
          return
        }
        upsertProductStroke(
          editor,
          {
            id: update.strokeId,
            color: update.color,
            brush: update.brush,
            width: update.width,
            annotationId: null,
            annotationDiameter: 0,
            points: visible,
          },
          pageWidth,
          pageHeight,
          true,
          update.isFinal,
        )
      })
      postToTraceHost({
        type: 'product-rendered',
        sampleIds: update.sampleIds,
      })
      if (update.isFinal) {
        postDocumentChange()
      }
    },

    insertImage(image) {
      insertUserImages([image])
    },

    insertImages(images) {
      insertUserImages(images)
    },

    getSnapshotJson() {
      return snapshotJson(editor)
    },

    async waitForIdle() {
      await Promise.all([
        waitForDropIdle(),
        waitForTimingIdle(),
      ])
    },

    getSnapshot() {
      return {
        documentId: currentDocumentId,
        snapshotJson: snapshotJson(editor),
        timedShapes: collectTimedShapes(editor),
      }
    },

    async exportPng(pixelRatio, expectedDocumentId) {
      await waitForDropIdle()
      if (currentDocumentId !== expectedDocumentId) {
        throw new Error('Trace document changed before tldraw export')
      }
      const shapes = exportableShapes(editor)
      const plan = planTraceImageExport(
        {
          x: 0,
          y: 0,
          width: exportBaseWidth,
          height: exportBaseHeight,
        },
        exportContributorBounds(editor, shapes),
        pixelRatio,
      )
      lastExportPlan = plan
      if (plan.didReduceResolution) {
        postToTraceHost({
          type: 'product-export-resolution',
          documentId: currentDocumentId,
          requestedPixelRatio: plan.requestedPixelRatio,
          effectivePixelRatio: plan.effectivePixelRatio,
          bounds: plan.logicalBounds,
          pixelWidth: plan.pixelWidth,
          pixelHeight: plan.pixelHeight,
        })
      }
      const blob = await renderExportPng(
        editor,
        shapes,
        currentBackgroundColor,
        plan,
      )
      if (currentDocumentId !== expectedDocumentId) {
        throw new Error('Trace document changed during tldraw export')
      }
      return {
        documentId: currentDocumentId,
        dataUrl: await blobToDataUrl(blob),
      }
    },

    undo() {
      suppressUserEdit = true
      try {
        editor.undo()
      } finally {
        window.setTimeout(() => {
          suppressUserEdit = false
        }, 50)
      }
      userEditPending = false
      postDocumentChange()
      postHistory()
    },

    redo() {
      suppressUserEdit = true
      try {
        editor.redo()
      } finally {
        window.setTimeout(() => {
          suppressUserEdit = false
        }, 50)
      }
      userEditPending = false
      postDocumentChange()
      postHistory()
    },

    clearUserContent() {
      committedByStroke.clear()
      editor.run(
        () => {
          const ids = editor
            .getCurrentPageShapes()
            .filter((shape) => !isBackgroundShape(shape.id))
            .map((shape) => shape.id)
          editor.deleteShapes(ids)
        },
        { ignoreShapeLock: true },
      )
    },

    emitPointerForTesting(phase, x, y) {
      const viewport = editor.getViewportScreenBounds()
      editor.dispatch({
        type: 'pointer',
        name:
          phase === 'began'
            ? 'pointer_down'
            : phase === 'moved'
              ? 'pointer_move'
              : 'pointer_up',
        point: new Vec(
          viewport.x + clampUnit(x) * viewport.width,
          viewport.y + clampUnit(y) * viewport.height,
        ),
        pointerId: 8_888,
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

    setZoomForTesting(zoom) {
      const camera = editor.getCamera()
      editor.setCamera({
        x: camera.x,
        y: camera.y,
        z: positive(zoom, 1),
      })
    },

    setTimingFinalizationDelayForTesting(delayMilliseconds) {
      timingFinalizationDelayMilliseconds = Math.max(
        0,
        delayMilliseconds,
      )
    },

    selectFirstUserShapeForTesting() {
      const shape = editor
        .getCurrentPageShapes()
        .find((candidate) =>
          String(candidate.id).includes(USER_IMAGE_PREFIX),
        )
      if (!shape) return false
      editor.select(shape.id)
      return true
    },

    setFirstUserImagePositionForTesting(x, y) {
      const shape = editor
        .getCurrentPageShapes()
        .find(
          (candidate): candidate is TLImageShape =>
            candidate.type === 'image'
            && String(candidate.id).includes(USER_IMAGE_PREFIX),
        )
      if (!shape || !Number.isFinite(x) || !Number.isFinite(y)) {
        return false
      }
      editor.updateShape<TLImageShape>({
        id: shape.id,
        type: 'image',
        x,
        y,
      })
      return true
    },

    setExportFixtureForTesting(fixture) {
      const frameId = createShapeId('trace-export-test-frame')
      const childId = createShapeId('trace-export-test-child')
      const rotatedId = createShapeId('trace-export-test-rotated')
      runHostMutation(() => {
        editor.deleteShapes(
          [frameId, childId, rotatedId].filter(
            (id) => editor.getShape(id) !== undefined,
          ),
        )
        if (fixture === 'masked') {
          editor.createShape<TLFrameShape>({
            id: frameId,
            type: 'frame',
            x: 800,
            y: 100,
            props: {
              ...editor.getShapeUtil<TLFrameShape>('frame')
                .getDefaultProps(),
              w: 100,
              h: 100,
            },
          })
          editor.createShape<TLGeoShape>({
            id: childId,
            type: 'geo',
            parentId: frameId,
            x: 50,
            y: 0,
            props: {
              ...editor.getShapeUtil<TLGeoShape>('geo')
                .getDefaultProps(),
              w: 500,
              h: 50,
            },
          })
        } else if (fixture === 'rotated') {
          editor.createShape<TLGeoShape>({
            id: rotatedId,
            type: 'geo',
            x: 10,
            y: 10,
            rotation: -Math.PI / 4,
            props: {
              ...editor.getShapeUtil<TLGeoShape>('geo')
                .getDefaultProps(),
              w: 100,
              h: 100,
            },
          })
        }
      })
    },

    clearSelectionForTesting() {
      editor.selectNone()
      reconcileTemporarySelect()
    },

    deleteSelectionForTesting() {
      editor.deleteShapes(editor.getSelectedShapeIds())
    },

    getStateForTesting() {
      const viewportScreenBounds = editor.getViewportScreenBounds()
      const viewportCenter = editor.screenToPage(
        editor.getViewportScreenCenter(),
      )
      const drawShapes = editor
        .getCurrentPageShapes()
        .filter((shape): shape is TLDrawShape => shape.type === 'draw')
      const backgrounds = editor
        .getCurrentPageShapes()
        .filter((shape) => isBackgroundShape(shape.id))
      const userImages = editor
        .getCurrentPageShapes()
        .filter(
          (shape) =>
            shape.type === 'image'
            && String(shape.id).includes(USER_IMAGE_PREFIX),
        )
      const sortedShapes = editor.getCurrentPageShapesSorted()
      const annotationShapes = sortedShapes.filter(
        (shape): shape is TraceAnnotationShape =>
          shape.type === TRACE_ANNOTATION_SHAPE_TYPE
          && String(shape.id).includes(ANNOTATION_SHAPE_PREFIX),
      )
      const timedShapes = collectTimedShapes(editor)
      const timedAnnotationCount = sortedShapes.filter((shape) =>
        String(shape.id).includes(USER_ANNOTATION_SHAPE_PREFIX),
      )
      const firstAnnotation = annotationShapes[0]
      const annotationLabel = editor.getContainer()
        .querySelector<SVGTextElement>(
          '[data-trace-annotation-label="true"]',
        )
      const annotationBounds = firstAnnotation
        ? editor.getShapePageBounds(firstAnnotation)
        : null
      const backgroundShape = backgrounds.find(
        (shape): shape is TLImageShape =>
          shape.type === 'image'
          && String(shape.id).includes(BACKGROUND_SHAPE_PREFIX),
      )
      const backgroundAsset = backgroundShape?.props.assetId
        ? editor.getAsset<TLImageAsset>(
            backgroundShape.props.assetId,
          )
        : null
      const captureShape = userImages.find(
        (shape): shape is TLImageShape =>
          shape.type === 'image'
          && isCaptureImage(shape.id),
      )
      const captureAsset = captureShape?.props.assetId
        ? editor.getAsset<TLImageAsset>(
            captureShape.props.assetId,
          )
        : null
      const firstContentIndex = sortedShapes.findIndex(
        (shape) => !isBackgroundShape(shape.id),
      )
      let lastDerivedIndex = -1
      sortedShapes.forEach((shape, index) => {
        if (isBackgroundShape(shape.id)) {
          lastDerivedIndex = index
        }
      })
      return {
        hideUi: true,
        uiElementCount: document.querySelectorAll(
          '.tlui-layout, .tlui-toolbar, .tlui-menu-zone',
        ).length,
        shapeCount: editor.getCurrentPageShapeIds().size,
        backgroundCount: backgrounds.length,
        backgroundLocked: backgrounds.every(
          (shape) => shape.isLocked,
        ),
        userImageCount: userImages.length,
        selectedUserImageCount: userImages.filter((shape) =>
          editor.getSelectedShapeIds().includes(shape.id),
        ).length,
        userImageBounds: userImages.flatMap((shape) => {
          const bounds = editor.getShapePageBounds(shape)
          return bounds
            ? [{
                x: bounds.x,
                y: bounds.y,
                width: bounds.width,
                height: bounds.height,
              }]
            : []
        }),
        annotationCount: annotationShapes.length,
        annotationCenter:
          firstAnnotation && annotationBounds
            ? {
                x: annotationBounds.x + annotationBounds.width / 2,
                y: annotationBounds.y + annotationBounds.height / 2,
                width: annotationBounds.width,
                height: annotationBounds.height,
                text: firstAnnotation.props.label,
                fill: firstAnnotation.props.fill,
                textColor: firstAnnotation.props.textColor,
                fontFamily:
                  annotationLabel?.getAttribute('font-family') ?? '',
                opacity: firstAnnotation.opacity,
              }
            : null,
        annotationIsTopmost:
          annotationShapes.length > 0
          && sortedShapes.at(-1)?.id
            === annotationShapes.at(-1)?.id,
        lockedPenCount: editor
          .getCurrentPageShapes()
          .filter((shape) =>
            String(shape.id).includes(PEN_SHAPE_PREFIX)
            && shape.isLocked,
          ).length,
        derivedLayersAtBack:
          backgrounds.length === 0
          || (
            String(sortedShapes[0]?.id ?? '')
              .includes(BACKGROUND_SHAPE_PREFIX)
            && (
              firstContentIndex < 0
              || lastDerivedIndex < firstContentIndex
            )
          ),
        exportIncludesGrid: exportableShapes(editor).some(
          (shape) => String(shape.id).includes(GRID_SHAPE_PREFIX),
        ),
        backgroundSource:
          currentPageKind === 'blank'
            ? currentBackgroundColor
            : captureAsset?.props.src
              ?? backgroundAsset?.props.src
              ?? null,
        renderedBackgroundColor: getComputedStyle(
          editor
            .getContainer()
            .querySelector<HTMLElement>('.tl-background')
            ?? editor.getContainer(),
        ).backgroundColor,
        productTool: currentTool.tool,
        rectangleCount: editor
          .getCurrentPageShapes()
          .filter(
            (shape) =>
              shape.type === 'geo'
              && shape.props.geo === 'rectangle',
          ).length,
        zoom: editor.getZoomLevel(),
        viewportWidth: viewportScreenBounds.width,
        viewportHeight: viewportScreenBounds.height,
        viewportCenterX: viewportCenter.x,
        viewportCenterY: viewportCenter.y,
        pageWidth,
        pageHeight,
        selectedShapeCount: editor.getSelectedShapeIds().length,
        timedShapeCount: timedShapes.length,
        timedAnnotationCount: timedAnnotationCount.length,
        timedAnnotationTexts: timedAnnotationCount
          .filter(
            (shape): shape is TraceAnnotationShape =>
              shape.type === TRACE_ANNOTATION_SHAPE_TYPE,
          )
          .map((shape) => shape.props.label),
        selectedTool: editor.getCurrentToolId(),
        color: currentTool.color,
        opacity: opacityForProductTool(currentTool),
        width: currentTool.width,
        gridStyle: currentTool.gridStyle,
        gridSpacing: currentTool.gridSpacing,
        drawWidths: drawShapes.map(
          (shape) =>
            (STROKE_SIZES[shape.props.size] + 1)
              * shape.props.scale,
        ),
        drawOpacities: drawShapes.map((shape) => shape.opacity),
        drawColors: drawShapes.map((shape) => shape.props.color),
        lastExportPlan,
      }
    },
  }

  const container = editor.getContainer()
  const handleDragOver = (event: DragEvent) => {
    if (
      Array.from(event.dataTransfer?.items ?? [])
        .some((item) => item.type.startsWith('image/'))
    ) {
      event.preventDefault()
      event.stopImmediatePropagation()
    }
  }
  const handleDrop = async (event: DragEvent) => {
    const files = Array.from(event.dataTransfer?.files ?? [])
      .filter((file) => file.type.startsWith('image/'))
    if (files.length === 0) return
    event.preventDefault()
    event.stopImmediatePropagation()
    const dropDocumentId = currentDocumentId
    pendingDropCount += 1
    try {
      const images: ProductImage[] = []
      for (const file of files) {
        let bitmap: ImageBitmap | null = null
        try {
          bitmap = await createImageBitmap(file)
          const dataUrl = await blobToDataUrl(file)
          if (currentDocumentId !== dropDocumentId) {
            continue
          }
          images.push({
            dataUrl,
            name: file.name || 'Dropped image',
            mimeType: file.type || 'image/png',
            width: bitmap.width,
            height: bitmap.height,
          })
        } catch (error) {
          reportTraceError(error)
        } finally {
          bitmap?.close()
        }
      }
      if (
        currentDocumentId === dropDocumentId
        && images.length > 0
      ) {
        bridge.insertImages(images)
      }
    } finally {
      finishDropWork()
    }
  }
  const handlePointerUp = () => {
    flushPendingDocumentChange()
    queueMicrotask(() => {
      reconcileTemporarySelect()
      reconcileTemporaryDraw()
    })
  }
  const isEditableTarget = (target: EventTarget | null) => {
    if (!(target instanceof HTMLElement)) return false
    return target.isContentEditable
      || target instanceof HTMLInputElement
      || target instanceof HTMLTextAreaElement
  }
  const changeZoom = (delta: number) => {
    const point = editor.getViewportScreenCenter()
    const { x: cx, y: cy, z: currentZoom } = editor.getCamera()
    const zoom = clamp(
      Math.round(
        (currentZoom + delta) * 100,
      ) / 100,
      MIN_KEYBOARD_ZOOM,
      MAX_KEYBOARD_ZOOM,
    )
    if (zoom === currentZoom) return
    editor.setCamera(
      new Vec(
        cx
          + (point.x / zoom - point.x)
          - (point.x / currentZoom - point.x),
        cy
          + (point.y / zoom - point.y)
          - (point.y / currentZoom - point.y),
        zoom,
      ),
      { animation: { duration: 0 } },
    )
  }
  const handleKeyDown = (event: KeyboardEvent) => {
    if (event.code === 'Space') {
      event.preventDefault()
      return
    }
    if (
      event.metaKey
      && !event.ctrlKey
      && !event.altKey
      && event.key === '0'
    ) {
      event.preventDefault()
      event.stopImmediatePropagation()
      editor.resetZoom(editor.getViewportScreenCenter(), {
        animation: { duration: 0 },
      })
      return
    }
    if (
      event.metaKey
      && !event.ctrlKey
      && !event.altKey
      && (
        event.key === '-'
        || event.code === 'Minus'
        || event.key === '+'
        || event.key === '='
        || event.code === 'Equal'
      )
    ) {
      event.preventDefault()
      event.stopImmediatePropagation()
      changeZoom(
        event.key === '-' || event.code === 'Minus'
          ? -KEYBOARD_ZOOM_INCREMENT
          : KEYBOARD_ZOOM_INCREMENT,
      )
      return
    }
    if (isEditableTarget(event.target)) return
    if (event.key === 'Meta') {
      commandSelectHeld = true
      if (
        temporarySelectActive
        && currentTool.tool !== 'select'
      ) {
        releaseTemporarySelect(true)
      } else if (currentTool.tool === 'select') {
        activateTemporaryDraw()
      } else {
        activateTemporarySelect()
      }
      return
    }
    if (
      event.repeat
      || event.metaKey
      || event.ctrlKey
      || event.altKey
    ) {
      return
    }
    const tool = {
      v: 'select',
      d: 'pen',
      h: 'highlighter',
      r: 'rectangle',
    }[event.key.toLowerCase()] as ProductCanvasTool | undefined
    if (!tool) return
    event.preventDefault()
    event.stopImmediatePropagation()
    selectProductTool(tool, true)
  }
  const handleKeyUp = (event: KeyboardEvent) => {
    if (event.code === 'Space') {
      event.preventDefault()
      return
    }
    if (event.key !== 'Meta') return
    commandSelectHeld = false
    reconcileTemporarySelect()
    reconcileTemporaryDraw()
  }
  const handleBlur = () => {
    commandSelectHeld = false
    reconcileTemporarySelect()
    reconcileTemporaryDraw()
  }
  container.addEventListener('dragover', handleDragOver, true)
  container.addEventListener('drop', handleDrop, true)
  container.addEventListener('pointerup', handlePointerUp)
  container.addEventListener('pointercancel', handlePointerUp)
  window.addEventListener('keydown', handleKeyDown, true)
  window.addEventListener('keyup', handleKeyUp, true)
  window.addEventListener('blur', handleBlur)

  window.traceProductRenderer = bridge
  postToTraceHost({ type: 'product-ready' })

  return () => {
    if (changeTimer !== null) {
      window.clearTimeout(changeTimer)
    }
    removeStoreListener()
    removeSessionListener()
    editor.off('event', handleEditorEvent)
    removeBeforeCreate()
    container.removeEventListener('dragover', handleDragOver, true)
    container.removeEventListener('drop', handleDrop, true)
    container.removeEventListener('pointerup', handlePointerUp)
    container.removeEventListener('pointercancel', handlePointerUp)
    window.removeEventListener('keydown', handleKeyDown, true)
    window.removeEventListener('keyup', handleKeyUp, true)
    window.removeEventListener('blur', handleBlur)
    if (window.traceProductRenderer === bridge) {
      delete window.traceProductRenderer
    }
  }
}

function applyTool(
  editor: Editor,
  tool: ProductTool,
  selectTool = true,
): void {
  editor.setStyleForNextShapes(DefaultColorStyle, tool.color, {
    history: 'ignore',
  })
  editor.setStyleForNextShapes(DefaultFillStyle, 'none', {
    history: 'ignore',
  })
  editor.setStyleForNextShapes(DefaultSizeStyle, 'm', {
    history: 'ignore',
  })
  editor.setOpacityForNextShapes(opacityForProductTool(tool), {
    history: 'ignore',
  })
  editor.setStyleForSelectedShapes(DefaultColorStyle, tool.color)
  editor.setStyleForSelectedShapes(DefaultSizeStyle, 'm')
  editor.setOpacityForSelectedShapes(opacityForProductTool(tool))
  const scale = scaleForWidth(tool.width)
  const selectedDrawShapes = editor
    .getSelectedShapes()
    .filter((shape): shape is TLDrawShape => shape.type === 'draw')
  if (selectedDrawShapes.length > 0) {
    editor.updateShapes(
      selectedDrawShapes.map((shape) => ({
        id: shape.id,
        type: 'draw' as const,
        props: {
          scale,
        },
      })),
    )
  }
  if (selectTool) {
    setEditorTool(editor, tool.tool)
  }
}

function setEditorTool(
  editor: Editor,
  tool: ProductCanvasTool,
): void {
  switch (tool) {
    case 'select':
      editor.setCurrentTool('select')
      break
    case 'rectangle':
      editor.setStyleForNextShapes(
        GeoShapeGeoStyle,
        'rectangle',
        { history: 'ignore' },
      )
      editor.setCurrentTool('geo')
      break
    case 'pen':
    case 'highlighter':
      editor.setCurrentTool('draw')
      break
  }
}

function upsertProductStroke(
  editor: Editor,
  stroke: ProductStroke,
  pageWidth: number,
  pageHeight: number,
  locked: boolean,
  complete = true,
): void {
  const id = createShapeId(`${PEN_SHAPE_PREFIX}${stroke.id}`)
  const pagePoints = stroke.points.map((point) => ({
    x: clampUnit(point.x) * pageWidth,
    y: clampUnit(point.y) * pageHeight,
    z: point.pressure ?? 0.5,
    connectsToPrevious: point.connectsToPrevious,
  }))
  if (pagePoints.length === 0) {
    const existing = editor.getShape(id)
    if (existing) editor.deleteShape(existing)
    return
  }

  const originX = Math.min(...pagePoints.map((point) => point.x))
  const originY = Math.min(...pagePoints.map((point) => point.y))
  const props: TLDrawShape['props'] = {
    color: stroke.color,
    fill: 'none',
    dash: 'draw',
    size: 'm',
    segments: makeSegments(pagePoints, originX, originY),
    isComplete: complete,
    isClosed: false,
    isPen: stroke.points.some((point) => point.pressure !== null),
    scale: scaleForWidth(stroke.width),
    scaleX: 1,
    scaleY: 1,
  }
  const existing = editor.getShape(id)
  if (existing) {
    editor.updateShape<TLDrawShape>({
      id,
      type: 'draw',
      x: originX,
      y: originY,
      opacity: opacityForBrush(stroke.brush),
      isLocked: locked,
      props,
    })
  } else {
    editor.createShape<TLDrawShape>({
      id,
      type: 'draw',
      x: originX,
      y: originY,
      opacity: opacityForBrush(stroke.brush),
      isLocked: locked,
      props,
    })
  }
  syncAnnotation(
    editor,
    stroke,
    pageWidth,
    pageHeight,
  )
}

type UserTimedShape = TLDrawShape | TLGeoShape

interface UserTimedShapeGeometry {
  start: { x: number; y: number }
  direction: { x: number; y: number }
  pathLength: number
  color: TLDefaultColorStyle
}

function isUserTimedShape(shape: TLShape): shape is UserTimedShape {
  return !shape.isLocked
    && (shape.type === 'draw' || shape.type === 'geo')
    && !String(shape.id).includes(PEN_SHAPE_PREFIX)
    && !String(shape.id).includes(ANNOTATION_SHAPE_PREFIX)
}

function preserveUserShapePlacement(
  editor: Editor,
  previousWidth: number,
  previousHeight: number,
  nextWidth: number,
  nextHeight: number,
) {
  const updates = editor
    .getCurrentPageShapes()
    .filter(
      (shape) =>
        !shape.isLocked
        && !String(shape.id).includes(PEN_SHAPE_PREFIX)
        && !String(shape.id).includes(ANNOTATION_SHAPE_PREFIX),
    )
    .flatMap((shape) => {
      const bounds = editor.getShapePageBounds(shape)
      if (!bounds) return []
      const centerX = bounds.x + bounds.width / 2
      const centerY = bounds.y + bounds.height / 2
      const nextCenterX =
        centerX / positive(previousWidth, nextWidth) * nextWidth
      const nextCenterY =
        centerY / positive(previousHeight, nextHeight) * nextHeight
      return [{
        id: shape.id,
        type: shape.type,
        x: shape.x + nextCenterX - centerX,
        y: shape.y + nextCenterY - centerY,
      }]
    })
  if (updates.length > 0) {
    editor.updateShapes(updates)
  }
}

function userTimedShapeGeometry(
  editor: Editor,
  shape: UserTimedShape,
): UserTimedShapeGeometry | null {
  const transform = editor.getShapePageTransform(shape)
  if (shape.type === 'geo') {
    const scale = positive(shape.props.scale, 1)
    const width = positive(shape.props.w, 1) * scale
    const height = positive(shape.props.h, 1) * scale
    const start = transform.applyToPoint({
      x: 0,
      y: height / 2,
    })
    const next = transform.applyToPoint({
      x: width,
      y: height / 2,
    })
    const direction = normalizedDirection(start, next)
    return {
      start,
      direction,
      pathLength: 2 * (width + height),
      color: shape.props.color,
    }
  }

  const scaleX =
    positive(shape.props.scale, 1) * shape.props.scaleX
  const scaleY =
    positive(shape.props.scale, 1) * shape.props.scaleY
  let start: { x: number; y: number } | null = null
  let direction = { x: 0, y: 0 }
  let pathLength = 0
  for (const segment of shape.props.segments) {
    const points = b64Vecs.decodePoints(segment.path).map((point) =>
      transform.applyToPoint({
        x: point.x * scaleX,
        y: point.y * scaleY,
      }),
    )
    if (!start && points[0]) {
      start = points[0]
      for (const point of points.slice(1)) {
        direction = normalizedDirection(start, point)
        if (direction.x !== 0 || direction.y !== 0) break
      }
    }
    for (let index = 1; index < points.length; index += 1) {
      pathLength += Math.hypot(
        points[index].x - points[index - 1].x,
        points[index].y - points[index - 1].y,
      )
    }
  }
  if (!start) return null
  return {
    start,
    direction,
    pathLength,
    color: shape.props.color,
  }
}

function normalizedDirection(
  start: { x: number; y: number },
  end: { x: number; y: number },
) {
  const dx = end.x - start.x
  const dy = end.y - start.y
  const length = Math.hypot(dx, dy)
  if (length <= 0.01) return { x: 0, y: 0 }
  return { x: dx / length, y: dy / length }
}

function collectTimedShapes(editor: Editor): ProductTimedShape[] {
  return editor
    .getCurrentPageShapes()
    .filter(isUserTimedShape)
    .flatMap((shape) => {
      const startedAt =
        shape.meta[TIMING_STARTED_META_KEY]
      const endedAt = shape.meta[TIMING_ENDED_META_KEY]
      const geometry = userTimedShapeGeometry(editor, shape)
      if (
        typeof startedAt !== 'number'
        || typeof endedAt !== 'number'
        || !Number.isFinite(startedAt)
        || !Number.isFinite(endedAt)
        || endedAt < startedAt
        || !geometry
      ) {
        return []
      }
      return [{
        id: shape.id,
        startedAtAppClockSeconds: startedAt,
        endedAtAppClockSeconds: endedAt,
        pathLength: geometry.pathLength,
      }]
    })
}

function syncPenStrokes(
  editor: Editor,
  strokes: ProductStroke[],
  pageWidth: number,
  pageHeight: number,
): void {
  const expected = new Set(
    strokes.map((stroke) =>
      createShapeId(`${PEN_SHAPE_PREFIX}${stroke.id}`),
    ),
  )
  const obsolete = editor
    .getCurrentPageShapes()
    .filter(
      (shape) =>
        String(shape.id).includes(PEN_SHAPE_PREFIX)
        && !expected.has(shape.id),
    )
    .map((shape) => shape.id)
  if (obsolete.length > 0) {
    editor.deleteShapes(obsolete)
  }
  const expectedAnnotations = new Set(
    strokes
      .filter((stroke) => stroke.annotationId !== null)
      .map((stroke) =>
        createShapeId(`${ANNOTATION_SHAPE_PREFIX}${stroke.id}`),
      ),
  )
  const obsoleteAnnotations = editor
    .getCurrentPageShapes()
    .filter(
      (shape) =>
        String(shape.id).includes(ANNOTATION_SHAPE_PREFIX)
        && !String(shape.id).includes(
          USER_ANNOTATION_SHAPE_PREFIX,
        )
        && !expectedAnnotations.has(shape.id),
    )
    .map((shape) => shape.id)
  if (obsoleteAnnotations.length > 0) {
    editor.deleteShapes(obsoleteAnnotations)
  }
  for (const stroke of strokes) {
    upsertProductStroke(
      editor,
      stroke,
      pageWidth,
      pageHeight,
      true,
    )
  }
}

function syncAnnotation(
  editor: Editor,
  stroke: ProductStroke,
  pageWidth: number,
  pageHeight: number,
): void {
  const id = createShapeId(
    `${ANNOTATION_SHAPE_PREFIX}${stroke.id}`,
  )
  if (
    stroke.annotationId === null
    || stroke.points.length === 0
    || stroke.annotationDiameter <= 0
  ) {
    const existing = editor.getShape(id)
    if (existing) editor.deleteShape(existing)
    return
  }
  const first = stroke.points[0]
  const start = {
    x: clampUnit(first.x) * pageWidth,
    y: clampUnit(first.y) * pageHeight,
  }
  let direction = { x: 0, y: 0 }
  for (let index = 1; index < stroke.points.length; index += 1) {
    const point = stroke.points[index]
    if (!point.connectsToPrevious) break
    direction = normalizedDirection(start, {
      x: clampUnit(point.x) * pageWidth,
      y: clampUnit(point.y) * pageHeight,
    })
    if (direction.x !== 0 || direction.y !== 0) break
  }
  upsertAnnotationCircle(
    editor,
    id,
    stroke.annotationId,
    stroke.annotationDiameter,
    stroke.color,
    start,
    direction,
    pageWidth,
    pageHeight,
  )
}

function syncShapeAnnotations(
  editor: Editor,
  annotations: ProductShapeAnnotation[],
  pageWidth: number,
  pageHeight: number,
): void {
  const expected = new Set(
    annotations.map((annotation) =>
      createShapeId(
        `${USER_ANNOTATION_SHAPE_PREFIX}${annotation.shapeId}`,
      ),
    ),
  )
  const obsolete = editor
    .getCurrentPageShapes()
    .filter(
      (shape) =>
        String(shape.id).includes(USER_ANNOTATION_SHAPE_PREFIX)
        && !expected.has(shape.id),
    )
    .map((shape) => shape.id)
  if (obsolete.length > 0) {
    editor.deleteShapes(obsolete)
  }
  for (const annotation of annotations) {
    const target = editor.getShape(
      annotation.shapeId as TLShapeId,
    )
    if (!target || !isUserTimedShape(target)) continue
    const geometry = userTimedShapeGeometry(editor, target)
    if (!geometry) continue
    upsertAnnotationCircle(
      editor,
      createShapeId(
        `${USER_ANNOTATION_SHAPE_PREFIX}${annotation.shapeId}`,
      ),
      annotation.annotationId,
      annotation.diameter,
      geometry.color,
      geometry.start,
      geometry.direction,
      pageWidth,
      pageHeight,
    )
  }
}

function upsertAnnotationCircle(
  editor: Editor,
  id: TLShapeId,
  annotationId: number,
  diameter: number,
  color: TLDefaultColorStyle,
  start: { x: number; y: number },
  direction: { x: number; y: number },
  pageWidth: number,
  pageHeight: number,
): void {
  const radius = diameter / 2
  const centerX = clamp(
    start.x - direction.x * diameter * 0.62,
    radius,
    pageWidth - radius,
  )
  const centerY = clamp(
    start.y - direction.y * diameter * 0.62,
    radius,
    pageHeight - radius,
  )
  const props: TraceAnnotationShape['props'] = {
    w: diameter,
    h: diameter,
    fill: DefaultColorThemePalette.lightMode[color].solid,
    textColor: '#ffffff',
    label: String(annotationId),
  }
  const shape: Partial<TraceAnnotationShape> & {
    id: TraceAnnotationShape['id']
    type: typeof TRACE_ANNOTATION_SHAPE_TYPE
  } = {
    id,
    type: TRACE_ANNOTATION_SHAPE_TYPE,
    x: centerX - radius,
    y: centerY - radius,
    opacity: 1,
    isLocked: true,
    props,
  }
  const existing = editor.getShape(id)
  if (existing?.type === TRACE_ANNOTATION_SHAPE_TYPE) {
    editor.updateShape<TraceAnnotationShape>(shape)
  } else {
    if (existing) editor.deleteShape(existing)
    editor.createShape<TraceAnnotationShape>(shape)
  }
  editor.bringToFront([id])
}

function setCanvasBackground(
  editor: Editor,
  color: string | null,
): void {
  const container = editor.getContainer()
  if (color) {
    container.style.setProperty('--tl-color-background', color)
  } else {
    container.style.removeProperty('--tl-color-background')
  }
}

function removeBackground(
  editor: Editor,
  documentId: string,
): void {
  removeImageShape(
    editor,
    createShapeId(`${BACKGROUND_SHAPE_PREFIX}${documentId}`),
  )
}

function removeGrid(
  editor: Editor,
  documentId: string,
): void {
  removeImageShape(
    editor,
    createShapeId(`${GRID_SHAPE_PREFIX}${documentId}`),
  )
}

function removeImageShape(
  editor: Editor,
  shapeId: TLShapeId,
): void {
  const existing = editor.getShape<TLImageShape>(shapeId)
  if (!existing) return
  editor.deleteShape(existing)
  if (existing.props.assetId) {
    editor.deleteAssets([existing.props.assetId])
  }
}

function clearCaptureImageMigration(editor: Editor): void {
  const page = editor.getCurrentPage()
  const {
    [CAPTURE_IMAGE_MIGRATED_META_KEY]: _migration,
    ...meta
  } = page.meta
  editor.updatePage({
    id: page.id,
    meta,
  })
}

function migrateCaptureImage(
  editor: Editor,
  documentId: string,
  dataUrl: string,
  width: number,
  height: number,
): void {
  const page = editor.getCurrentPage()
  if (page.meta[CAPTURE_IMAGE_MIGRATED_META_KEY] === true) {
    return
  }
  const stableId = `${CAPTURE_IMAGE_PREFIX}${documentId}`
  const shapeId = insertImage(
    editor,
    {
      dataUrl,
      name: 'Captured screenshot',
      mimeType: 'image/png',
      width,
      height,
    },
    width,
    height,
    false,
    stableId,
    { x: 0, y: 0, width, height },
    false,
  )
  editor.sendToBack([shapeId])
  editor.updatePage({
    id: page.id,
    meta: {
      ...page.meta,
      [CAPTURE_IMAGE_MIGRATED_META_KEY]: true,
    },
  })
}

interface ProductImagePlacement {
  x: number
  y: number
  width: number
  height: number
}

function batchImagePlacements(
  count: number,
  pageWidth: number,
  pageHeight: number,
): ProductImagePlacement[] {
  const margin = Math.max(
    0,
    Math.min(32, pageWidth / 10, pageHeight / 10),
  )
  const aspectRatio = pageWidth / Math.max(1, pageHeight)
  const columns = Math.min(
    count,
    Math.max(1, Math.round(Math.sqrt(count * aspectRatio))),
  )
  const rows = Math.ceil(count / columns)
  const gap = Math.max(
    0,
    Math.min(
      24,
      columns > 1
        ? (pageWidth - margin * 2) / (columns * 4)
        : 24,
      rows > 1
        ? (pageHeight - margin * 2) / (rows * 4)
        : 24,
    ),
  )
  const cellWidth = Math.max(
    1,
    (pageWidth - margin * 2 - gap * (columns - 1)) / columns,
  )
  const cellHeight = Math.max(
    1,
    (pageHeight - margin * 2 - gap * (rows - 1)) / rows,
  )
  return Array.from({ length: count }, (_, index) => {
    const column = index % columns
    const row = Math.floor(index / columns)
    return {
      x: margin + column * (cellWidth + gap),
      y: margin + row * (cellHeight + gap),
      width: cellWidth,
      height: cellHeight,
    }
  })
}

function insertImage(
  editor: Editor,
  image: ProductImage,
  pageWidth: number,
  pageHeight: number,
  locked: boolean,
  stableId = `${USER_IMAGE_PREFIX}${crypto.randomUUID()}`,
  placement?: ProductImagePlacement,
  selectAfterInsert = true,
): TLShapeId {
  const assetId = AssetRecordType.createId(stableId)
  const shapeId = createShapeId(stableId)
  const sourceWidth = positive(image.width, 1)
  const sourceHeight = positive(image.height, 1)
  const scale = locked
    ? Math.min(pageWidth / sourceWidth, pageHeight / sourceHeight)
    : Math.min(
        1,
        (placement?.width ?? pageWidth * 0.6) / sourceWidth,
        (placement?.height ?? pageHeight * 0.6) / sourceHeight,
      )
  const width = sourceWidth * scale
  const height = sourceHeight * scale
  const x = locked
    ? 0
    : placement
      ? placement.x + (placement.width - width) / 2
      : (pageWidth - width) / 2
  const y = locked
    ? 0
    : placement
      ? placement.y + (placement.height - height) / 2
      : (pageHeight - height) / 2
  const asset: TLImageAsset = {
    id: assetId,
    typeName: 'asset',
    type: 'image',
    props: {
      name: image.name,
      src: image.dataUrl,
      w: sourceWidth,
      h: sourceHeight,
      mimeType: image.mimeType,
      isAnimated: false,
      fileSize: image.dataUrl.length,
    },
    meta: {},
  }
  editor.createAssets([asset])
  editor.createShape<TLImageShape>({
    id: shapeId,
    type: 'image',
    x,
    y,
    isLocked: locked,
    props: {
      w: locked ? pageWidth : width,
      h: locked ? pageHeight : height,
      playing: true,
      url: '',
      assetId,
      crop: null,
      flipX: false,
      flipY: false,
      altText: image.name,
    },
  })
  if (!locked && selectAfterInsert) {
    editor.select(shapeId)
    editor.setCurrentTool('select')
  }
  return shapeId
}

function makeSegments(
  points: Array<{
    x: number
    y: number
    z: number
    connectsToPrevious: boolean
  }>,
  originX: number,
  originY: number,
) {
  const groups: Array<Array<{ x: number; y: number; z: number }>> = []
  for (const [index, point] of points.entries()) {
    if (index === 0 || !point.connectsToPrevious) {
      groups.push([])
    }
    groups.at(-1)!.push({
      x: point.x - originX,
      y: point.y - originY,
      z: point.z,
    })
  }
  return groups.map((points) => ({
    type: 'free' as const,
    path: b64Vecs.encodePoints(points),
  }))
}

function opacityForBrush(brush: ProductBrush): number {
  return brush === 'highlighter' ? 0.5 : 1
}

function opacityForProductTool(tool: ProductTool): number {
  return tool.tool === 'highlighter' ? 0.5 : 1
}

function scaleForWidth(width: number): number {
  return positive(width, 5.25) / (STROKE_SIZES.m + 1)
}

function isBackgroundShape(id: TLShapeId): boolean {
  const value = String(id)
  return value.includes(BACKGROUND_SHAPE_PREFIX)
    || value.includes(GRID_SHAPE_PREFIX)
}

function isTraceBackgroundShape(id: TLShapeId): boolean {
  return String(id).includes(BACKGROUND_SHAPE_PREFIX)
}

function isCaptureImage(id: TLShapeId): boolean {
  return String(id).includes(CAPTURE_IMAGE_PREFIX)
}

function isHostOwnedRecordId(id: string): boolean {
  return id.includes(PEN_SHAPE_PREFIX)
    || id.includes(ANNOTATION_SHAPE_PREFIX)
    || id.includes(BACKGROUND_SHAPE_PREFIX)
    || id.includes(GRID_SHAPE_PREFIX)
}

function isTransientShape(id: TLShapeId): boolean {
  return String(id).includes('trace-mouse-prediction-')
}

function exportableShapes(editor: Editor) {
  return editor
    .getCurrentPageShapes()
    .filter(
      (shape) =>
        !isTransientShape(shape.id)
        && !String(shape.id).includes(GRID_SHAPE_PREFIX),
    )
}

function exportContributorBounds(
  editor: Editor,
  shapes: readonly TLShape[],
): LogicalBounds[] {
  const bounds: LogicalBounds[] = []
  for (const shape of shapes) {
    if (
      isTraceBackgroundShape(shape.id)
      || editor.isShapeHidden(shape.id)
    ) {
      continue
    }
    const maskedBounds = editor.getShapeMaskedPageBounds(shape)
    if (!maskedBounds) continue
    bounds.push({
      x: maskedBounds.x,
      y: maskedBounds.y,
      width: maskedBounds.width,
      height: maskedBounds.height,
    })
  }
  return bounds
}

function snapshotJson(editor: Editor): string {
  const ignoredIds = new Set<string>()
  for (const shape of editor.getCurrentPageShapes()) {
    if (!isBackgroundShape(shape.id)) continue
    ignoredIds.add(shape.id)
    if (shape.type === 'image' && shape.props.assetId) {
      ignoredIds.add(shape.props.assetId)
    }
  }
  const snapshot = JSON.parse(
    JSON.stringify(editor.getSnapshot()),
  ) as {
    document?: {
      store?: Record<string, unknown>
    }
  }
  const store = snapshot.document?.store
  if (store) {
    for (const id of ignoredIds) {
      delete store[id]
    }
  }
  return JSON.stringify(snapshot)
}

function positive(value: number, fallback: number): number {
  return Number.isFinite(value) && value > 0 ? value : fallback
}

function clampUnit(value: number): number {
  return Math.min(1, Math.max(0, value))
}

function clamp(
  value: number,
  lower: number,
  upper: number,
): number {
  if (lower > upper) return (lower + upper) / 2
  return Math.min(upper, Math.max(lower, value))
}

function blobToDataUrl(blob: Blob): Promise<string> {
  return new Promise((resolve, reject) => {
    const reader = new FileReader()
    reader.onerror = () => reject(reader.error)
    reader.onload = () => resolve(String(reader.result))
    reader.readAsDataURL(blob)
  })
}

async function renderExportPng(
  editor: Editor,
  shapes: TLShape[],
  color: string,
  plan: TraceImageExportPlan,
): Promise<Blob> {
  const bounds = plan.logicalBounds
  const exported = await editor.getSvgElement(shapes, {
    bounds: new Box(
      bounds.x,
      bounds.y,
      bounds.width,
      bounds.height,
    ),
    padding: 0,
    pixelRatio: plan.effectivePixelRatio,
    background: false,
    darkMode: false,
  })
  const svg = exported?.svg ?? createEmptyExportSvg(bounds)
  addExportBackground(svg, bounds, color)
  svg.setAttribute('width', String(plan.pixelWidth))
  svg.setAttribute('height', String(plan.pixelHeight))
  svg.setAttribute(
    'viewBox',
    `${bounds.x} ${bounds.y} ${bounds.width} ${bounds.height}`,
  )
  const blob = await getSvgAsImage(
    new XMLSerializer().serializeToString(svg),
    {
      type: 'png',
      width: plan.pixelWidth / plan.effectivePixelRatio,
      height: plan.pixelHeight / plan.effectivePixelRatio,
      pixelRatio: plan.effectivePixelRatio,
    },
  )
  if (!blob) {
    throw new Error('Trace could not encode the image export')
  }
  return blob
}

function createEmptyExportSvg(
  bounds: LogicalBounds,
): SVGSVGElement {
  const svg = document.createElementNS(
    'http://www.w3.org/2000/svg',
    'svg',
  )
  svg.setAttribute('xmlns', 'http://www.w3.org/2000/svg')
  svg.setAttribute(
    'viewBox',
    `${bounds.x} ${bounds.y} ${bounds.width} ${bounds.height}`,
  )
  return svg
}

function addExportBackground(
  svg: SVGSVGElement,
  bounds: LogicalBounds,
  color: string,
): void {
  const background = document.createElementNS(
    'http://www.w3.org/2000/svg',
    'rect',
  )
  background.setAttribute('x', String(bounds.x))
  background.setAttribute('y', String(bounds.y))
  background.setAttribute('width', String(bounds.width))
  background.setAttribute('height', String(bounds.height))
  background.setAttribute('fill', color)
  const firstRenderedChild = Array.from(svg.children)
    .find((child) => child.localName !== 'defs')
  svg.insertBefore(background, firstRenderedChild ?? null)
}
