import {
  atom,
  DefaultColorThemePalette,
  DrawShapeUtil,
  GeoShapeUtil,
  TextShapeUtil,
  useValue,
  type TLDrawShape,
  type TLGeoShape,
  type TLTextShape,
} from 'tldraw'
import {
  highlighterColorName,
  INK_NAMES,
  type InkPalette,
} from './inkPalette'

// tldraw resolves color names through this shared palette for both canvas
// rendering and exports; the version atom makes mounted shapes repaint.
const inkPaletteVersion = atom('trace ink palette version', 0)

export function applyInkPalette(palette: InkPalette): void {
  const theme = DefaultColorThemePalette.lightMode
  for (const name of INK_NAMES) {
    theme[name].solid = palette.ink[name]
    theme[highlighterColorName(name)].solid = palette.highlighter[name]
  }
  inkPaletteVersion.update((version) => version + 1)
}

function useInkPaletteVersion(): void {
  useValue(inkPaletteVersion)
}

export class TraceDrawShapeUtil extends DrawShapeUtil {
  override component(shape: TLDrawShape) {
    useInkPaletteVersion()
    return super.component(shape)
  }
}

export class TraceGeoShapeUtil extends GeoShapeUtil {
  override component(shape: TLGeoShape) {
    useInkPaletteVersion()
    return super.component(shape)
  }
}

export class TraceTextShapeUtil extends TextShapeUtil {
  override component(shape: TLTextShape) {
    useInkPaletteVersion()
    return super.component(shape)
  }
}
