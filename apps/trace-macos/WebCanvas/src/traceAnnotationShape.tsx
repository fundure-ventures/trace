import {
  BaseBoxShapeUtil,
  DefaultColorThemePalette,
  Ellipse2d,
  SVGContainer,
  T,
  type TLShape,
} from 'tldraw'

export const TRACE_ANNOTATION_SHAPE_TYPE = 'trace-annotation'
export const TRACE_ANNOTATION_FONT_FAMILY =
  '-apple-system, BlinkMacSystemFont, sans-serif'

declare module '@tldraw/tlschema' {
  interface TLGlobalShapePropsMap {
    'trace-annotation': {
      w: number
      h: number
      fill: string
      textColor: string
      label: string
    }
  }
}

export type TraceAnnotationShape =
  TLShape<typeof TRACE_ANNOTATION_SHAPE_TYPE>

export class TraceAnnotationShapeUtil
  extends BaseBoxShapeUtil<TraceAnnotationShape> {
  static override type = TRACE_ANNOTATION_SHAPE_TYPE
  static override props = {
    w: T.number,
    h: T.number,
    fill: T.string,
    textColor: T.string,
    label: T.string,
  }

  override canBind() {
    return false
  }

  override canEdit() {
    return false
  }

  override canResize() {
    return false
  }

  override isAspectRatioLocked() {
    return true
  }

  override getDefaultProps(): TraceAnnotationShape['props'] {
    return {
      w: 16,
      h: 16,
      fill: DefaultColorThemePalette.lightMode.red.solid,
      textColor: '#ffffff',
      label: '1',
    }
  }

  override getGeometry(shape: TraceAnnotationShape) {
    return new Ellipse2d({
      width: shape.props.w,
      height: shape.props.h,
      isFilled: true,
    })
  }

  override component(shape: TraceAnnotationShape) {
    return (
      <SVGContainer>
        {annotationCircle(shape)}
      </SVGContainer>
    )
  }

  override indicator(shape: TraceAnnotationShape) {
    return (
      <circle
        cx={shape.props.w / 2}
        cy={shape.props.h / 2}
        r={Math.min(shape.props.w, shape.props.h) / 2}
      />
    )
  }

  override toSvg(shape: TraceAnnotationShape) {
    return annotationCircle(shape)
  }
}

function annotationCircle(shape: TraceAnnotationShape) {
  const { w, h, fill, textColor, label } = shape.props
  const fontSize = Math.max(8, w * 0.5)
  return (
    <g>
      <circle
        cx={w / 2}
        cy={h / 2}
        r={Math.min(w, h) / 2}
        fill={fill}
      />
      <text
        data-trace-annotation-label="true"
        x={w / 2}
        y={h / 2}
        fill={textColor}
        fontFamily={TRACE_ANNOTATION_FONT_FAMILY}
        fontSize={fontSize}
        fontWeight={600}
        fontVariant="tabular-nums"
        textAnchor="middle"
        dominantBaseline="central"
      >
        {label}
      </text>
    </g>
  )
}
