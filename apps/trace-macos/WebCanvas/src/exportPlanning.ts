export interface LogicalBounds {
  x: number
  y: number
  width: number
  height: number
}

export interface TraceImageExportPlan {
  logicalBounds: LogicalBounds
  requestedPixelRatio: number
  effectivePixelRatio: number
  pixelWidth: number
  pixelHeight: number
  didOverflowBase: boolean
  didReduceResolution: boolean
}

export const TRACE_EXPORT_PADDING = 24
export const TRACE_EXPORT_MAX_PIXEL_SIDE = 8192
export const TRACE_EXPORT_MAX_PIXEL_AREA = 12_000_000

const BOUNDS_COMPARISON_EPSILON = 1e-6

export function planTraceImageExport(
  baseBounds: LogicalBounds,
  contributorBounds: readonly LogicalBounds[],
  requestedPixelRatio: number,
): TraceImageExportPlan {
  assertBounds(baseBounds, 'base bounds', true)
  if (
    !Number.isFinite(requestedPixelRatio)
    || requestedPixelRatio <= 0
  ) {
    throw new Error('Trace export pixel ratio must be positive and finite')
  }

  let contentBounds: LogicalBounds | null = null
  for (const bounds of contributorBounds) {
    assertBounds(bounds, 'contributor bounds', false)
    contentBounds = contentBounds
      ? unionBounds(contentBounds, bounds)
      : { ...bounds }
  }
  let didOverflowBase = false
  let logicalBounds = { ...baseBounds }
  if (
    contentBounds !== null
    && !boundsFitWithin(contentBounds, baseBounds)
  ) {
    didOverflowBase = true
    logicalBounds = expandBounds(
      unionBounds(baseBounds, contentBounds),
      TRACE_EXPORT_PADDING,
    )
  }
  const raster = planRasterSize(
    logicalBounds.width,
    logicalBounds.height,
    requestedPixelRatio,
  )

  return {
    logicalBounds,
    requestedPixelRatio,
    effectivePixelRatio: raster.effectivePixelRatio,
    pixelWidth: raster.pixelWidth,
    pixelHeight: raster.pixelHeight,
    didOverflowBase,
    didReduceResolution:
      raster.effectivePixelRatio < requestedPixelRatio,
  }
}

function planRasterSize(
  logicalWidth: number,
  logicalHeight: number,
  requestedPixelRatio: number,
): {
  effectivePixelRatio: number
  pixelWidth: number
  pixelHeight: number
} {
  const areaRatio = Math.sqrt(TRACE_EXPORT_MAX_PIXEL_AREA)
    / Math.sqrt(logicalWidth)
    / Math.sqrt(logicalHeight)
  let effectivePixelRatio = Math.min(
    requestedPixelRatio,
    TRACE_EXPORT_MAX_PIXEL_SIDE / logicalWidth,
    TRACE_EXPORT_MAX_PIXEL_SIDE / logicalHeight,
    areaRatio,
  )
  if (
    !Number.isFinite(effectivePixelRatio)
    || effectivePixelRatio <= 0
  ) {
    throw new Error(
      'Trace export bounds cannot be represented at a positive pixel ratio',
    )
  }

  let dimensions = rasterDimensions(
    logicalWidth,
    logicalHeight,
    effectivePixelRatio,
  )
  if (!rasterFitsBudget(dimensions)) {
    let lower = 0
    let upper = effectivePixelRatio
    for (let iteration = 0; iteration < 80; iteration += 1) {
      const candidate = lower + (upper - lower) / 2
      if (candidate === lower || candidate === upper) break
      const candidateDimensions = rasterDimensions(
        logicalWidth,
        logicalHeight,
        candidate,
      )
      if (rasterFitsBudget(candidateDimensions)) {
        lower = candidate
      } else {
        upper = candidate
      }
    }
    effectivePixelRatio = lower
    if (effectivePixelRatio <= 0) {
      throw new Error(
        'Trace export bounds cannot fit the output pixel budget',
      )
    }
    dimensions = rasterDimensions(
      logicalWidth,
      logicalHeight,
      effectivePixelRatio,
    )
  }

  return {
    effectivePixelRatio,
    ...dimensions,
  }
}

function rasterDimensions(
  logicalWidth: number,
  logicalHeight: number,
  pixelRatio: number,
): {
  pixelWidth: number
  pixelHeight: number
} {
  return {
    pixelWidth: Math.max(1, Math.ceil(logicalWidth * pixelRatio)),
    pixelHeight: Math.max(1, Math.ceil(logicalHeight * pixelRatio)),
  }
}

function rasterFitsBudget(dimensions: {
  pixelWidth: number
  pixelHeight: number
}): boolean {
  return dimensions.pixelWidth <= TRACE_EXPORT_MAX_PIXEL_SIDE
    && dimensions.pixelHeight <= TRACE_EXPORT_MAX_PIXEL_SIDE
    && dimensions.pixelWidth * dimensions.pixelHeight
      <= TRACE_EXPORT_MAX_PIXEL_AREA
}

function boundsFitWithin(
  inner: LogicalBounds,
  outer: LogicalBounds,
): boolean {
  return inner.x >= outer.x - BOUNDS_COMPARISON_EPSILON
    && inner.y >= outer.y - BOUNDS_COMPARISON_EPSILON
    && maxX(inner) <= maxX(outer) + BOUNDS_COMPARISON_EPSILON
    && maxY(inner) <= maxY(outer) + BOUNDS_COMPARISON_EPSILON
}

function unionBounds(
  first: LogicalBounds,
  second: LogicalBounds,
): LogicalBounds {
  const x = Math.min(first.x, second.x)
  const y = Math.min(first.y, second.y)
  const right = Math.max(maxX(first), maxX(second))
  const bottom = Math.max(maxY(first), maxY(second))
  return {
    x,
    y,
    width: right - x,
    height: bottom - y,
  }
}

function expandBounds(
  bounds: LogicalBounds,
  padding: number,
): LogicalBounds {
  return {
    x: bounds.x - padding,
    y: bounds.y - padding,
    width: bounds.width + padding * 2,
    height: bounds.height + padding * 2,
  }
}

function maxX(bounds: LogicalBounds): number {
  return bounds.x + bounds.width
}

function maxY(bounds: LogicalBounds): number {
  return bounds.y + bounds.height
}

function assertBounds(
  bounds: LogicalBounds,
  label: string,
  requirePositiveSize: boolean,
): void {
  const values = [
    bounds.x,
    bounds.y,
    bounds.width,
    bounds.height,
  ]
  if (values.some((value) => !Number.isFinite(value))) {
    throw new Error(`Trace export ${label} must be finite`)
  }
  const invalidSize = requirePositiveSize
    ? bounds.width <= 0 || bounds.height <= 0
    : bounds.width < 0 || bounds.height < 0
  if (invalidSize) {
    throw new Error(
      `Trace export ${label} must have valid dimensions`,
    )
  }
}
