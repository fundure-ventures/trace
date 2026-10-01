import { forwardRef } from 'react'
import {
  atom,
  DefaultColorThemePalette,
  DefaultShapeWrapper,
  DrawShapeUtil,
  GeoShapeUtil,
  TextShapeUtil,
  useValue,
  type SvgExportContext,
  type TLDrawShape,
  type TLShape,
  type TLShapeWrapperProps,
  type TLGeoShape,
  type TLTextShape,
} from 'tldraw'
import {
  type HighlighterBlend,
  highlighterColorName,
  INK_NAMES,
  type InkPalette,
  isHighlighterColor,
} from './inkPalette'

// tldraw resolves color names through this shared palette for both canvas
// rendering and exports; the version atom makes mounted shapes repaint.
const inkPaletteVersion = atom('trace ink palette version', 0)
const highlighterBlend = atom<HighlighterBlend>(
  'trace highlighter blend',
  'multiply',
)

export function applyInkPalette(palette: InkPalette): void {
  const theme = DefaultColorThemePalette.lightMode
  for (const name of INK_NAMES) {
    theme[name].solid = palette.ink[name]
    theme[highlighterColorName(name)].solid = palette.highlighter[name]
  }
  highlighterBlend.set(palette.highlighterBlend)
  inkPaletteVersion.update((version) => version + 1)
}

function useInkPaletteVersion(): void {
  useValue(inkPaletteVersion)
}

function blendForShape(shape: TLShape): HighlighterBlend | undefined {
  return shape.type === 'draw' && isHighlighterColor((shape as TLDrawShape).props.color)
    ? highlighterBlend.get()
    : undefined
}

// Shapes share one stacking context, so the blend reaches screenshots and
// other shapes below a highlighter but never the page background.
export const TraceShapeWrapper = forwardRef<HTMLDivElement, TLShapeWrapperProps>(
  function TraceShapeWrapper(props, ref) {
    const blend = useValue('trace shape blend', () => blendForShape(props.shape), [props.shape])
    return (
      <DefaultShapeWrapper
        ref={ref}
        {...props}
        style={{ ...props.style, mixBlendMode: blend }}
      />
    )
  },
)

export class TraceDrawShapeUtil extends DrawShapeUtil {
  override component(shape: TLDrawShape) {
    useInkPaletteVersion()
    return super.component(shape)
  }

  override toSvg(shape: TLDrawShape, ctx: SvgExportContext) {
    const svg = super.toSvg(shape, ctx)
    const blend = blendForShape(shape)
    return blend ? <g style={{ mixBlendMode: blend }}>{svg}</g> : svg
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
