import AppKit
import NeoInput
import TraceCalibration
import TraceGeometry
import TraceStrokeProcessing

struct RefinementRenderMeasurement {
    let strokeID: UInt64
    let pointCount: Int
    let mappingNanoseconds: UInt64
    let drawNanoseconds: UInt64
    let readyToDrawNanoseconds: UInt64
}

struct CanvasDrawMeasurement {
    let retainedPointCount: Int
    let predictedPointCount: Int
    let acknowledgedSampleCount: Int
    let drawNanoseconds: UInt64
    let completedUptimeNanoseconds: UInt64
}

final class RawCanvasView: NSView {
    var onSamplesRendered: (([RawPenSample], UInt64) -> Void)?
    var onRefinementRendered: ((RefinementRenderMeasurement) -> Void)?
    var onCanvasDrawn: ((CanvasDrawMeasurement) -> Void)?
    var onMouseStrokeEvent: ((LabMouseStrokeEvent) -> Void)?
    var mouseDrawingEnabled = false
    var showsAnchors = false {
        didSet {
            needsDisplay = true
        }
    }

    private struct CanvasPoint {
        let render: RenderPoint
        let point: UnitPoint
        let nib: StrokeNibGeometry
    }

    private struct CanvasStroke {
        let id: UInt64
        var points: [CanvasPoint]
    }

    private var strokes: [CanvasStroke] = []
    private var predictedPoints: [CanvasPoint] = []
    private var pendingSamples: [RawPenSample] = []
    private var calibration: CalibratedSurface?
    private var isCalibrationActive = false
    private var isPagePriming = false
    private var calibrationCorner: CalibrationCorner?
    private var calibrationMessage: String?
    private var pendingRefinements: [(
        strokeID: UInt64,
        pointCount: Int,
        readyUptimeNanoseconds: UInt64,
        mappingNanoseconds: UInt64
    )] = []
    private let paperInk = NSColor(calibratedWhite: 0.08, alpha: 1)
    private let paperSecondaryInk = NSColor(calibratedWhite: 0.55, alpha: 1)
    private let strokeWidthPolicy = StrokeWidthPolicy()
    private let strokeNibPolicy = StrokeNibPolicy()
    private var mouseStrokeActive = false
    private var previousMouseCoalescingEnabled = true
    private var lastMouseSample: LabMouseSample?
#if DEBUG
    private(set) var presentationUpdateCountForTesting = 0
#endif

    override var isFlipped: Bool {
        true
    }

    override var acceptsFirstResponder: Bool {
        true
    }

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        wantsLayer = true
        setAccessibilityRole(.image)
        setAccessibilityLabel("Pen input canvas")
    }

    required init?(coder: NSCoder) {
        nil
    }

    func setCalibration(
        _ calibration: CalibratedSurface?,
        isActive: Bool,
        isPagePriming: Bool,
        corner: CalibrationCorner?,
        message: String?
    ) {
#if DEBUG
        presentationUpdateCountForTesting += 1
#endif
        self.calibration = calibration
        isCalibrationActive = isActive
        self.isPagePriming = isPagePriming
        calibrationCorner = corner
        calibrationMessage = message
        needsDisplay = true
    }

    func apply(
        _ update: LabRendererUpdate
    ) {
        if let replacement = update.replacement {
            let mappingStarted = DispatchTime.now().uptimeNanoseconds
            let replacementPoints = replacement.compactMap {
                canvasPoint($0)
            }
            if let index = strokes.firstIndex(where: {
                $0.id == update.strokeID
            }) {
                strokes[index].points = replacementPoints
            } else {
                strokes.append(
                    CanvasStroke(
                        id: update.strokeID,
                        points: replacementPoints
                    )
                )
            }
            predictedPoints.removeAll(keepingCapacity: true)
            if let refinementReadyUptimeNanoseconds =
                update.refinementReadyUptimeNanoseconds
            {
                pendingRefinements.append((
                    strokeID: update.strokeID,
                    pointCount: replacementPoints.count,
                    readyUptimeNanoseconds:
                        refinementReadyUptimeNanoseconds,
                    mappingNanoseconds:
                        DispatchTime.now().uptimeNanoseconds - mappingStarted
                ))
            }
        }
        let committed = update.committed.compactMap {
            canvasPoint($0)
        }
        if !committed.isEmpty {
            if strokes.last?.id == update.strokeID {
                strokes[strokes.count - 1].points.append(contentsOf: committed)
            } else {
                strokes.append(CanvasStroke(id: update.strokeID, points: committed))
            }
        }
        predictedPoints = update.predicted.compactMap {
            canvasPoint($0)
        }
        pendingSamples.append(contentsOf: update.sourceSamples)
        needsDisplay = true
    }

    func clear() {
        strokes.removeAll(keepingCapacity: true)
        predictedPoints.removeAll(keepingCapacity: true)
        pendingSamples.removeAll(keepingCapacity: true)
        pendingRefinements.removeAll(keepingCapacity: true)
        needsDisplay = true
    }

    override func draw(_ dirtyRect: NSRect) {
        let drawStarted = DispatchTime.now().uptimeNanoseconds
        let acknowledgedSampleCount = pendingSamples.count
        let retainedPointCount = strokes.reduce(0) {
            $0 + $1.points.count
        }
        let predictedPointCount = predictedPoints.count
        super.draw(dirtyRect)
        NSColor.windowBackgroundColor.setFill()
        bounds.fill()

        let paperRect = fittedPaperRect()
        NSColor(calibratedWhite: 0.985, alpha: 1).setFill()
        paperRect.fill()
        NSColor(calibratedWhite: 0.78, alpha: 1).setStroke()
        NSBezierPath(rect: paperRect).stroke()

        if isCalibrationActive || isPagePriming {
            drawCalibration(
                in: paperRect,
                corner: calibrationCorner,
                message: calibrationMessage,
                showCorners: isCalibrationActive
            )
        } else {
            NSGraphicsContext.saveGraphicsState()
            NSBezierPath(rect: paperRect).addClip()
            drawStrokes(in: paperRect)
            NSGraphicsContext.restoreGraphicsState()
        }

        let drawCompleted = DispatchTime.now().uptimeNanoseconds
        if acknowledgedSampleCount > 0 {
            onCanvasDrawn?(
                CanvasDrawMeasurement(
                    retainedPointCount: retainedPointCount,
                    predictedPointCount: predictedPointCount,
                    acknowledgedSampleCount: acknowledgedSampleCount,
                    drawNanoseconds: drawCompleted - drawStarted,
                    completedUptimeNanoseconds: drawCompleted
                )
            )
        }
        if !pendingRefinements.isEmpty {
            let renderedRefinements = pendingRefinements
            pendingRefinements.removeAll(keepingCapacity: true)
            for pendingRefinement in renderedRefinements {
                onRefinementRendered?(
                    RefinementRenderMeasurement(
                        strokeID: pendingRefinement.strokeID,
                        pointCount: pendingRefinement.pointCount,
                        mappingNanoseconds:
                            pendingRefinement.mappingNanoseconds,
                        drawNanoseconds: drawCompleted - drawStarted,
                        readyToDrawNanoseconds:
                            drawCompleted
                                - pendingRefinement.readyUptimeNanoseconds
                    )
                )
            }
        }

        guard !pendingSamples.isEmpty else {
            return
        }
        let rendered = pendingSamples
        pendingSamples.removeAll(keepingCapacity: true)
        onSamplesRendered?(rendered, DispatchTime.now().uptimeNanoseconds)
    }

    private func fittedPaperRect() -> NSRect {
        LabPaperLayout.drawingRect(in: bounds)
    }

#if DEBUG
    var drawingRectForTesting: NSRect {
        fittedPaperRect()
    }
#endif

    override func acceptsFirstMouse(for event: NSEvent?) -> Bool {
        true
    }

    override func mouseDown(with event: NSEvent) {
        guard mouseDrawingEnabled,
              let sample = mouseSample(from: event)
        else {
            super.mouseDown(with: event)
            return
        }
        window?.makeFirstResponder(self)
        mouseStrokeActive = true
        previousMouseCoalescingEnabled = NSEvent.isMouseCoalescingEnabled
        NSEvent.isMouseCoalescingEnabled = false
        lastMouseSample = sample
        onMouseStrokeEvent?(.began(sample))
    }

    override func mouseDragged(with event: NSEvent) {
        guard mouseDrawingEnabled,
              mouseStrokeActive,
              let sample = mouseSample(from: event)
        else {
            super.mouseDragged(with: event)
            return
        }
        lastMouseSample = sample
        onMouseStrokeEvent?(.moved(sample))
    }

    override func mouseUp(with event: NSEvent) {
        guard mouseDrawingEnabled, mouseStrokeActive else {
            super.mouseUp(with: event)
            return
        }
        mouseStrokeActive = false
        defer {
            NSEvent.isMouseCoalescingEnabled =
                previousMouseCoalescingEnabled
            lastMouseSample = nil
        }
        if let sample = mouseSample(from: event) ?? lastMouseSample {
            onMouseStrokeEvent?(.ended(sample))
        }
    }

    private func mouseSample(from event: NSEvent) -> LabMouseSample? {
        let paperRect = fittedPaperRect()
        let location = convert(event.locationInWindow, from: nil)
        guard paperRect.width > 0,
              paperRect.height > 0,
              paperRect.contains(location)
        else {
            return nil
        }
        let pressure = Double(event.pressure)
        return LabMouseSample(
            point: UnitPoint(
                x: min(
                    1,
                    max(0, (location.x - paperRect.minX) / paperRect.width)
                ),
                y: min(
                    1,
                    max(0, (location.y - paperRect.minY) / paperRect.height)
                )
            ),
            pressure: pressure > 0 && pressure < 1
                ? pressure
                : nil,
            wallClockMilliseconds: UInt64(
                Date().timeIntervalSince1970 * 1_000
            ),
            uptimeNanoseconds:
                DispatchTime.now().uptimeNanoseconds
        )
    }

    private func drawStrokes(in paperRect: NSRect) {
        NSGraphicsContext.current?.shouldAntialias = true

        for stroke in strokes {
            draw(points: stroke.points, in: paperRect)
        }

        guard !predictedPoints.isEmpty,
              let previous = strokes.last?.points.last
        else {
            return
        }
        draw(
            points: predictedPoints,
            in: paperRect,
            initialPrevious: previous,
            forcePredictedStyle: true
        )
    }

    private func draw(
        points: [CanvasPoint],
        in paperRect: NSRect,
        initialPrevious: CanvasPoint? = nil,
        forcePredictedStyle: Bool = false
    ) {
        var previous = initialPrevious
        for (index, sample) in points.enumerated() {
            let point = map(sample.point, into: paperRect)
            if let previous,
               sample.render.connectsToPrevious
            {
                let previousPoint = map(previous.point, into: paperRect)
                let kind = forcePredictedStyle
                    ? RenderPointKind.predicted
                    : segmentKind(previous.render.kind, sample.render.kind)
                drawConnector(
                    from: previousPoint,
                    previousNib: previous.nib,
                    to: point,
                    nib: sample.nib,
                    kind: kind
                )
            }

            if sample.render.marksGap {
                NSColor.systemOrange.setStroke()
                let ring = nibPath(
                    at: point,
                    geometry: sample.nib,
                    expansion: 1
                )
                ring.lineWidth = 1
                ring.stroke()
            }
            let hasNext = index < points.count - 1
            let isEndpoint = StrokePathTopology.isEndpoint(
                hasPrevious: previous != nil,
                connectsToPrevious: sample.render.connectsToPrevious,
                hasNext: hasNext,
                nextConnectsToPrevious: hasNext
                    && points[index + 1].render.connectsToPrevious
            )
            if !forcePredictedStyle && isEndpoint {
                fillColor(sample.render.kind).setFill()
                nibPath(at: point, geometry: sample.nib).fill()
            }
            if showsAnchors {
                drawAnchor(
                    at: point,
                    kind: forcePredictedStyle
                        ? .predicted
                        : sample.render.kind
                )
            }
            previous = sample
        }
    }

    private func drawConnector(
        from start: NSPoint,
        previousNib: StrokeNibGeometry,
        to end: NSPoint,
        nib: StrokeNibGeometry,
        kind: RenderPointKind
    ) {
        let directionX = Double(end.x - start.x)
        let directionY = Double(end.y - start.y)
        let startWidth = previousNib.sweptWidth(
            directionX: directionX,
            directionY: directionY
        )
        let endWidth = nib.sweptWidth(
            directionX: directionX,
            directionY: directionY
        )
        strokeColor(kind).setStroke()
        if kind == .predicted {
            drawConnectorSegment(
                from: start,
                to: end,
                width: (startWidth + endWidth) / 2,
                dashed: true
            )
            return
        }

        let midpoint = NSPoint(
            x: (start.x + end.x) / 2,
            y: (start.y + end.y) / 2
        )
        drawConnectorSegment(
            from: start,
            to: midpoint,
            width: startWidth * 0.75 + endWidth * 0.25,
            dashed: false
        )
        drawConnectorSegment(
            from: midpoint,
            to: end,
            width: startWidth * 0.25 + endWidth * 0.75,
            dashed: false
        )
    }

    private func drawConnectorSegment(
        from start: NSPoint,
        to end: NSPoint,
        width: Double,
        dashed: Bool
    ) {
        let path = NSBezierPath()
        path.move(to: start)
        path.line(to: end)
        path.lineCapStyle = .round
        path.lineJoinStyle = .round
        path.lineWidth = CGFloat(width)
        if dashed {
            path.setLineDash([4, 3], count: 2, phase: 0)
        }
        path.stroke()
    }

    private func drawAnchor(
        at point: NSPoint,
        kind: RenderPointKind
    ) {
        let marker = NSBezierPath(
            ovalIn: NSRect(
                x: point.x - 3,
                y: point.y - 3,
                width: 6,
                height: 6
            )
        )
        NSColor.white.withAlphaComponent(0.92).setFill()
        marker.fill()
        strokeColor(kind).setStroke()
        marker.lineWidth = 1.4
        marker.stroke()
    }

    private func canvasPoint(
        _ point: LabRenderPoint
    ) -> CanvasPoint? {
        let render = point.render
        let baseWidth = strokeWidthPolicy.width(for: render.pressure)
        return CanvasPoint(
            render: render,
            point: point.normalized,
            nib: strokeNibPolicy.geometry(
                baseWidth: baseWidth,
                tiltX: render.tiltX,
                tiltY: render.tiltY,
                twistDegrees: render.twistDegrees
            )
        )
    }

    private func segmentKind(
        _ first: RenderPointKind,
        _ second: RenderPointKind
    ) -> RenderPointKind {
        if first == .predicted || second == .predicted {
            return .predicted
        }
        if first == .refined || second == .refined {
            return .refined
        }
        if first == .interpolated || second == .interpolated {
            return .interpolated
        }
        return .raw
    }

    private func strokeColor(_ kind: RenderPointKind) -> NSColor {
        switch kind {
        case .raw:
            return paperInk
        case .interpolated:
            return NSColor.systemBlue
        case .predicted:
            return NSColor.systemPurple
        case .refined:
            return NSColor.systemTeal
        }
    }

    private func fillColor(_ kind: RenderPointKind) -> NSColor {
        strokeColor(kind)
    }

    private func drawCalibration(
        in rect: NSRect,
        corner: CalibrationCorner?,
        message: String?,
        showCorners: Bool
    ) {
        let positions: [(CalibrationCorner, NSPoint)] = [
            (.topLeft, NSPoint(x: rect.minX + 24, y: rect.minY + 24)),
            (.topRight, NSPoint(x: rect.maxX - 24, y: rect.minY + 24)),
            (.bottomRight, NSPoint(x: rect.maxX - 24, y: rect.maxY - 24)),
            (.bottomLeft, NSPoint(x: rect.minX + 24, y: rect.maxY - 24)),
        ]

        if showCorners {
            for (candidate, point) in positions {
                let radius: CGFloat = candidate == corner ? 8 : 5
                let color: NSColor = candidate == corner
                    ? .controlAccentColor
                    : paperSecondaryInk
                color.setFill()
                NSBezierPath(
                    ovalIn: NSRect(
                        x: point.x - radius,
                        y: point.y - radius,
                        width: radius * 2,
                        height: radius * 2
                    )
                ).fill()
            }
        }

        if corner == nil {
            NSColor.controlAccentColor.setStroke()
            let registrationTarget = NSBezierPath(
                ovalIn: NSRect(
                    x: rect.midX - 14,
                    y: rect.midY - 50,
                    width: 28,
                    height: 28
                )
            )
            registrationTarget.lineWidth = 3
            registrationTarget.stroke()
        }

        let text = message ?? "Calibrating paper surface"
        let attributes: [NSAttributedString.Key: Any] = [
            .font: NSFont.systemFont(ofSize: 20, weight: .medium),
            .foregroundColor: paperInk,
        ]
        let size = text.size(withAttributes: attributes)
        text.draw(
            at: NSPoint(
                x: rect.midX - size.width / 2,
                y: rect.midY + 2
            ),
            withAttributes: attributes
        )
    }

    private func map(_ point: UnitPoint, into rect: NSRect) -> NSPoint {
        NSPoint(
            x: rect.minX + point.x * rect.width,
            y: rect.minY + point.y * rect.height
        )
    }

    private func nibPath(
        at point: NSPoint,
        geometry: StrokeNibGeometry,
        expansion: CGFloat = 0
    ) -> NSBezierPath {
        let width = CGFloat(geometry.majorAxis) + expansion * 2
        let height = CGFloat(geometry.minorAxis) + expansion * 2
        let path = NSBezierPath(
            ovalIn: NSRect(
                x: -width / 2,
                y: -height / 2,
                width: width,
                height: height
            )
        )
        var transform = AffineTransform()
        transform.translate(x: point.x, y: point.y)
        transform.rotate(byRadians: CGFloat(geometry.rotationRadians))
        path.transform(using: transform)
        return path
    }
}

extension RawCanvasView: LabRendererSurface {
    var view: NSView { self }
    var childViewControllers: [NSViewController] { [] }
    var unavailableReason: String? { nil }

    func updatePresentation(_ presentation: LabRendererPresentation) {
        setCalibration(
            presentation.calibration,
            isActive: presentation.calibrationActive,
            isPagePriming: presentation.pagePriming,
            corner: presentation.calibrationCorner,
            message: presentation.message
        )
    }

    func activate() {
        isHidden = false
        mouseDrawingEnabled = true
    }

    func deactivate() {
        mouseDrawingEnabled = false
        isHidden = true
    }
}
