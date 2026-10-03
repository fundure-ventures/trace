export interface ImagePlacementBounds {
  x: number
  y: number
  width: number
  height: number
}

export function viewportImagePlacement(
  viewport: ImagePlacementBounds,
): ImagePlacementBounds {
  return {
    x: viewport.x + viewport.width * 0.2,
    y: viewport.y + viewport.height * 0.2,
    width: viewport.width * 0.6,
    height: viewport.height * 0.6,
  }
}
