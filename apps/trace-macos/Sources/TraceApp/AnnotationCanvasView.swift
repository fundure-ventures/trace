import AppKit
import TraceAppCore
import TraceStrokeProcessing

final class AnnotationCanvasView: NSView {
    var onDocumentEdited: ((
        [TraceDrawingStroke],
        [TraceDrawingStroke]
    ) -> Void)?
    var onSelectionModeChanged: ((Bool) -> Void)?

    private var document: TraceDrawingSession?
    private var screenshotRepresentation: NSBitmapImageRep?
    private var predictedStroke: TraceDrawingStroke?
    private var activeStrokeID: UInt64?
    private var selectedStrokeIDs: Set<UInt64> = []
    private var dragStartPoint: NSPoint?
    private var dragStartStrokes: [TraceDrawingStroke]?
    private var didMoveSelectedStroke = false
    private var transcriptAnnotationScale:
        TraceTranscriptAnnotationScale = .medium
    private let widthPolicy = StrokeWidthPolicy()
    private let nibPolicy = StrokeNibPolicy()
#if DEBUG
    private(set) var renderCount = 0
#endif

    override var isFlipped: Bool {
        true
    }

    override var acceptsFirstResponder: Bool {
        true
    }

    override var mouseDownCanMoveWindow: Bool {
        false
    }

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        wantsLayer = true
        setAccessibilityRole(.image)
        setAccessibilityLabel(
            "Captured window annotation canvas. Click a stroke to select it, "
                + "drag to move it, or press Delete to remove it."
        )
    }

    required init?(coder: NSCoder) {
        nil
    }

    func setDocument(_ document: TraceDrawingSession) {
        self.document = document
        screenshotRepresentation = bitmapRepresentation(
            of: document.screenshot
        )
        predictedStroke = nil
        activeStrokeID = nil
        setSelection([])
        needsDisplay = true
    }

    func apply(_ update: TraceAnnotationUpdate) {
        if !selectedStrokeIDs.isEmpty {
            setSelection([])
            dragStartPoint = nil
            dragStartStrokes = nil
            didMoveSelectedStroke = false
        }
        if update.isFinal {
            activeStrokeID = nil
            predictedStroke = nil
        } else {
            activeStrokeID = update.strokeID
            if update.predicted.isEmpty {
                predictedStroke = nil
            } else {
                predictedStroke = TraceDrawingStroke(
                    id: update.strokeID,
                    color: update.style.color,
                    brush: update.style.brush,
                    width: update.style.width,
                    points: update.predicted
                )
            }
        }

        needsDisplay = true
    }

    func clearPrediction() {
        predictedStroke = nil
        needsDisplay = true
    }

    func refreshDocumentGeometry() {
        needsDisplay = true
    }

    func refreshAfterHistoryChange() {
        activeStrokeID = nil
        predictedStroke = nil
        dragStartPoint = nil
        dragStartStrokes = nil
        didMoveSelectedStroke = false
        setSelection([])
        needsDisplay = true
    }

    func refreshTranscriptAnnotations() {
        needsDisplay = true
    }

    @discardableResult
    func setTranscriptAnnotationScale(
        _ scale: TraceTranscriptAnnotationScale
    ) -> Bool {
        guard transcriptAnnotationScale != scale else {
            return false
        }
        transcriptAnnotationScale = scale
        needsDisplay = true
        return true
    }

#if DEBUG
    func selectStrokesForPreview(_ strokeIDs: Set<UInt64>) {
        setSelection(strokeIDs)
        needsDisplay = true
    }

    func moveSelectedStrokesForPreview(delta: TracePoint) {
        guard let document, !selectedStrokeIDs.isEmpty else {
            return
        }
        let before = document.manifest.strokes
        document.manifest.strokes = TraceStrokeEditing.translatedStrokes(
            document.manifest.strokes,
            selectedIDs: selectedStrokeIDs,
            requestedDelta: delta
        )
        needsDisplay = true
        onDocumentEdited?(before, document.manifest.strokes)
    }

    func deleteSelectedStrokesForPreview() {
        deleteSelectedStroke()
    }

    func resetRenderCountForTesting() {
        renderCount = 0
    }

    func brushAlphaForTesting(
        _ brush: TraceBrushKind
    ) -> CGFloat {
        brushAlpha(brush)
    }

    func renderStrokeForTesting(
        _ stroke: TraceDrawingStroke,
        predictedPoints: [TraceDrawingPoint],
        size: NSSize
    ) -> Data? {
        guard let representation = renderStrokeRepresentationForTesting(
            stroke,
            predictedPoints: predictedPoints,
            size: size
        ),
        let bitmapData = representation.bitmapData else {
            return nil
        }
        return Data(
            bytes: bitmapData,
            count: representation.bytesPerRow
                * representation.pixelsHigh
        )
    }

    func renderStrokeRepresentationForTesting(
        _ stroke: TraceDrawingStroke,
        predictedPoints: [TraceDrawingPoint] = [],
        size: NSSize,
        exportCoordinates: Bool = false,
        widthScale: Double = 1
    ) -> NSBitmapImageRep? {
        guard let representation = NSBitmapImageRep(
            bitmapDataPlanes: nil,
            pixelsWide: Int(size.width),
            pixelsHigh: Int(size.height),
            bitsPerSample: 8,
            samplesPerPixel: 4,
            hasAlpha: true,
            isPlanar: false,
            colorSpaceName: .deviceRGB,
            bitmapFormat: [],
            bytesPerRow: 0,
            bitsPerPixel: 0
        ),
        let context = NSGraphicsContext(bitmapImageRep: representation)
        else {
            return nil
        }
        representation.size = size
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = context
        context.cgContext.clear(
            NSRect(origin: .zero, size: size)
        )
        if exportCoordinates {
            context.cgContext.translateBy(x: 0, y: size.height)
            context.cgContext.scaleBy(x: 1, y: -1)
        }
        draw(
            stroke: stroke,
            in: NSRect(origin: .zero, size: size),
            widthScale: widthScale,
            predictedPoints: predictedPoints,
            flipAnnotationText: exportCoordinates
        )
        context.flushGraphics()
        NSGraphicsContext.restoreGraphicsState()
        return representation
    }

    func transcriptAnnotationDiameterForTesting(
        _ stroke: TraceDrawingStroke,
        size: NSSize,
        widthScale: Double
    ) -> CGFloat? {
        transcriptAnnotationDiameter(
            for: stroke,
            in: NSRect(origin: .zero, size: size),
            widthScale: widthScale
        )
    }
#endif

    var imageRectOnScreen: NSRect? {
        guard window != nil else {
            return nil
        }
        let windowRect = convert(fittedImageRect(), to: nil)
        return window?.convertToScreen(windowRect)
    }

    func compositeImage() -> NSImage? {
        guard let document else {
            return nil
        }
        let viewport = resolvedViewport()
        let pixelWidth: Int
        let pixelHeight: Int
        if document.manifest.pageKind == .blank {
            pixelWidth = document.manifest.screenshotPixelWidth
            pixelHeight = document.manifest.screenshotPixelHeight
        } else {
            pixelWidth = max(
                1,
                Int(
                    (
                        Double(document.manifest.screenshotPixelWidth)
                            * viewport.width
                    ).rounded()
                )
            )
            pixelHeight = max(
                1,
                Int(
                    (
                        Double(document.manifest.screenshotPixelHeight)
                            * viewport.height
                    ).rounded()
                )
            )
        }
        guard let representation = NSBitmapImageRep(
            bitmapDataPlanes: nil,
            pixelsWide: pixelWidth,
            pixelsHigh: pixelHeight,
            bitsPerSample: 8,
            samplesPerPixel: 4,
            hasAlpha: true,
            isPlanar: false,
            colorSpaceName: .deviceRGB,
            bytesPerRow: 0,
            bitsPerPixel: 0
        ) else {
            return nil
        }
        let size = NSSize(width: pixelWidth, height: pixelHeight)
        representation.size = size
        guard let context = NSGraphicsContext(
            bitmapImageRep: representation
        ) else {
            return nil
        }
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = context
        let rect = NSRect(origin: .zero, size: size)
        NSColor(
            document.manifest.backgroundColor
                ?? TraceRGBAColor(red: 1, green: 1, blue: 1)
        ).setFill()
        rect.fill()
        if document.manifest.pageKind != .blank {
            let sourceSize = document.screenshot.size
            let sourceRect = NSRect(
                x: sourceSize.width * viewport.x,
                y: sourceSize.height
                    * (1 - viewport.y - viewport.height),
                width: sourceSize.width * viewport.width,
                height: sourceSize.height * viewport.height
            )
            document.screenshot.draw(
                in: rect,
                from: sourceRect,
                operation: .sourceOver,
                fraction: 1,
                respectFlipped: false,
                hints: [.interpolation: NSImageInterpolation.none]
            )
        }
        context.cgContext.translateBy(x: 0, y: size.height)
        context.cgContext.scaleBy(x: 1, y: -1)
        draw(
            strokes: document.manifest.strokes,
            in: rect,
            widthScale: exportWidthScale(document.manifest),
            flipAnnotationText: true
        )
        context.flushGraphics()
        NSGraphicsContext.restoreGraphicsState()

        let image = NSImage(size: size)
        image.addRepresentation(representation)
        return image
    }

    fileprivate func drawCompletedStrokes() {
        guard let document else {
            return
        }
        let imageRect = fittedImageRect()
        NSGraphicsContext.saveGraphicsState()
        NSBezierPath(rect: imageRect).addClip()
        let widthScale = displayWidthScale(
            document.manifest,
            imageRect: imageRect
        )
        for stroke in document.manifest.strokes where
            stroke.id != activeStrokeID
        {
            draw(
                stroke: stroke,
                in: imageRect,
                widthScale: widthScale
            )
        }
        NSGraphicsContext.restoreGraphicsState()
    }

    override func draw(_ dirtyRect: NSRect) {
        super.draw(dirtyRect)
#if DEBUG
        renderCount += 1
#endif
        NSGraphicsContext.current?.cgContext.clear(bounds)

        guard let document else {
            return
        }
        let imageRect = fittedImageRect()
        NSGraphicsContext.saveGraphicsState()
        NSBezierPath(rect: imageRect).addClip()
        let liveWidthScale = displayWidthScale(
            document.manifest,
            imageRect: imageRect
        )
        if selectedStrokeIDs.isEmpty {
            if let activeStrokeID,
               let stroke = activeStroke(
                   with: activeStrokeID,
                   in: document.manifest.strokes
               )
            {
                draw(
                    stroke: stroke,
                    in: imageRect,
                    widthScale: liveWidthScale,
                    predictedPoints: predictedStroke?.points ?? []
                )
            }
        } else {
            draw(
                strokes: document.manifest.strokes,
                in: imageRect,
                widthScale: liveWidthScale,
                predictedStroke: predictedStroke
            )
        }
        drawSelection(in: imageRect, widthScale: liveWidthScale)
        NSGraphicsContext.restoreGraphicsState()
    }

    override func acceptsFirstMouse(for event: NSEvent?) -> Bool {
        true
    }

    override func mouseDown(with event: NSEvent) {
        guard let document else {
            return
        }
        window?.makeFirstResponder(self)
        let location = convert(event.locationInWindow, from: nil)
        let imageRect = fittedImageRect()
        guard imageRect.contains(location) else {
            if !event.modifierFlags.contains(.shift) {
                setSelection([])
            }
            needsDisplay = true
            return
        }
        let localPoint = TracePoint(
            x: (location.x - imageRect.minX) / imageRect.width,
            y: (location.y - imageRect.minY) / imageRect.height
        )
        let normalized = TracePageViewport.unmap(
            localPoint,
            through: resolvedViewport()
        )
        let hitStrokeID = TraceStrokeEditing.selectStroke(
            at: normalized,
            strokes: document.manifest.strokes,
            surface: sourcePointSize(),
            tolerance: 8
        )
        let extending = event.modifierFlags.contains(.shift)
        setSelection(
            TraceStrokeEditing.updatedSelection(
                current: selectedStrokeIDs,
                hitStrokeID: hitStrokeID,
                extending: extending
            )
        )
        guard let hitStrokeID,
              selectedStrokeIDs.contains(hitStrokeID)
        else {
            dragStartPoint = nil
            dragStartStrokes = nil
            needsDisplay = true
            return
        }
        dragStartPoint = location
        dragStartStrokes = document.manifest.strokes
        didMoveSelectedStroke = false
        needsDisplay = true
    }

    override func mouseDragged(with event: NSEvent) {
        guard let document,
              !selectedStrokeIDs.isEmpty,
              let dragStartPoint,
              let dragStartStrokes
        else {
            return
        }
        let imageRect = fittedImageRect()
        guard imageRect.width > 0, imageRect.height > 0 else {
            return
        }
        let location = convert(event.locationInWindow, from: nil)
        document.manifest.strokes =
            TraceStrokeEditing.translatedStrokes(
                dragStartStrokes,
                selectedIDs: selectedStrokeIDs,
                requestedDelta: TracePoint(
                    x: (
                        (location.x - dragStartPoint.x) / imageRect.width
                    ) * resolvedViewport().width,
                    y: (
                        (location.y - dragStartPoint.y) / imageRect.height
                    ) * resolvedViewport().height
                )
            )
        predictedStroke = nil
        didMoveSelectedStroke = true
        needsDisplay = true
    }

    override func mouseUp(with event: NSEvent) {
        if didMoveSelectedStroke,
           let before = dragStartStrokes,
           let after = document?.manifest.strokes
        {
            onDocumentEdited?(before, after)
        }
        dragStartPoint = nil
        dragStartStrokes = nil
        didMoveSelectedStroke = false
    }

    override func keyDown(with event: NSEvent) {
        if event.keyCode == 51 || event.keyCode == 117 {
            deleteSelectedStroke()
            return
        }
        if event.keyCode == 53 {
            setSelection([])
            needsDisplay = true
            return
        }
        super.keyDown(with: event)
    }

    private func fittedImageRect() -> NSRect {
        bounds
    }

    private func draw(
        strokes: [TraceDrawingStroke],
        in rect: NSRect,
        widthScale: Double,
        predictedStroke: TraceDrawingStroke? = nil,
        flipAnnotationText: Bool = false
    ) {
        for stroke in strokes {
            draw(
                stroke: stroke,
                in: rect,
                widthScale: widthScale,
                predictedPoints: predictedStroke?.id == stroke.id
                    ? predictedStroke?.points ?? []
                    : [],
                flipAnnotationText: flipAnnotationText
            )
        }
    }

    private func draw(
        stroke: TraceDrawingStroke,
        in rect: NSRect,
        widthScale: Double,
        predictedPoints: [TraceDrawingPoint] = [],
        flipAnnotationText: Bool = false
    ) {
        let color = NSColor(stroke.color)
            .withAlphaComponent(brushAlpha(stroke.brush))
        drawAsUnifiedStroke(color: color) { inkColor in
            draw(
                points: stroke.points,
                stroke: stroke,
                in: rect,
                widthScale: widthScale,
                color: inkColor,
                initialPrevious: nil,
                hasFollowingPoint:
                    predictedPoints.first?.connectsToPrevious == true
            )
            if !predictedPoints.isEmpty {
                draw(
                    points: predictedPoints,
                    stroke: stroke,
                    in: rect,
                    widthScale: widthScale,
                    color: inkColor,
                    initialPrevious: stroke.points.last,
                    hasFollowingPoint: false
                )
            }
        }
        drawTranscriptAnnotation(
            for: stroke,
            in: rect,
            widthScale: widthScale,
            flipTextVertically: flipAnnotationText
        )
    }

    private func drawTranscriptAnnotation(
        for stroke: TraceDrawingStroke,
        in rect: NSRect,
        widthScale: Double,
        flipTextVertically: Bool
    ) {
        guard let annotation = stroke.transcriptAnnotation,
              let first = stroke.points.first
        else {
            return
        }
        let mappedPoints = stroke.points.map { map($0, into: rect) }
        guard let diameter = transcriptAnnotationDiameter(
            for: stroke,
            in: rect,
            widthScale: widthScale
        ) else {
            return
        }
        let start = map(first, into: rect)
        let direction = initialDirection(in: mappedPoints, stroke: stroke)
        let proposedCenter = NSPoint(
            x: start.x - direction.dx * diameter * 0.62,
            y: start.y - direction.dy * diameter * 0.62
        )
        let radius = diameter / 2
        let center = NSPoint(
            x: clamped(
                proposedCenter.x,
                lower: rect.minX + radius,
                upper: rect.maxX - radius
            ),
            y: clamped(
                proposedCenter.y,
                lower: rect.minY + radius,
                upper: rect.maxY - radius
            )
        )
        let circle = NSRect(
            x: center.x - radius,
            y: center.y - radius,
            width: diameter,
            height: diameter
        )
        NSColor(stroke.color).setFill()
        NSBezierPath(ovalIn: circle).fill()

        let text = String(annotation.id) as NSString
        let attributes: [NSAttributedString.Key: Any] = [
            .font: NSFont.monospacedDigitSystemFont(
                ofSize: max(8, diameter * 0.5),
                weight: .semibold
            ),
            .foregroundColor: NSColor.white,
        ]
        let textSize = text.size(withAttributes: attributes)
        let textOrigin = NSPoint(
            x: center.x - textSize.width / 2,
            y: center.y - textSize.height / 2
        )
        if flipTextVertically,
           let context = NSGraphicsContext.current?.cgContext
        {
            // Bitmap export flips stroke coordinates; undo it for the glyph.
            context.saveGState()
            context.translateBy(x: center.x, y: center.y)
            context.scaleBy(x: 1, y: -1)
            context.translateBy(x: -center.x, y: -center.y)
            text.draw(at: textOrigin, withAttributes: attributes)
            context.restoreGState()
        } else {
            text.draw(at: textOrigin, withAttributes: attributes)
        }
    }

    private func transcriptAnnotationDiameter(
        for stroke: TraceDrawingStroke,
        in rect: NSRect,
        widthScale: Double
    ) -> CGFloat? {
        guard let annotation = stroke.transcriptAnnotation else {
            return nil
        }
        let mappedPoints = stroke.points.map { map($0, into: rect) }
        var pathLength = 0.0
        for index in 1..<stroke.points.count where
            stroke.points[index].connectsToPrevious
        {
            pathLength += hypot(
                mappedPoints[index].x - mappedPoints[index - 1].x,
                mappedPoints[index].y - mappedPoints[index - 1].y
            )
        }
        let renderScale = max(widthScale, 0.000_001)
        // Size from source geometry, then scale once for screen or export.
        return CGFloat(
            TraceTranscriptAnnotationPlanner.labelDiameter(
                pathLength: pathLength / renderScale,
                annotationID: annotation.id,
                scale: transcriptAnnotationScale
            ) * renderScale
        )
    }

    private func initialDirection(
        in points: [NSPoint],
        stroke: TraceDrawingStroke
    ) -> CGVector {
        guard let first = points.first else {
            return .zero
        }
        for index in 1..<points.count {
            guard stroke.points[index].connectsToPrevious else {
                break
            }
            let dx = points[index].x - first.x
            let dy = points[index].y - first.y
            let length = hypot(dx, dy)
            if length > 0.01 {
                return CGVector(dx: dx / length, dy: dy / length)
            }
        }
        return .zero
    }

    private func clamped(
        _ value: CGFloat,
        lower: CGFloat,
        upper: CGFloat
    ) -> CGFloat {
        guard lower <= upper else {
            return (lower + upper) / 2
        }
        return min(upper, max(lower, value))
    }

    private func activeStroke(
        with id: UInt64,
        in strokes: [TraceDrawingStroke]
    ) -> TraceDrawingStroke? {
        if strokes.last?.id == id {
            return strokes.last
        }
        return strokes.first { $0.id == id }
    }

    private func draw(
        points: [TraceDrawingPoint],
        stroke: TraceDrawingStroke,
        in rect: NSRect,
        widthScale: Double,
        color: NSColor,
        initialPrevious: TraceDrawingPoint?,
        hasFollowingPoint: Bool
    ) {
        var previous = initialPrevious
        for (index, point) in points.enumerated() {
            let mapped = map(point, into: rect)
            let nib = nibGeometry(
                point,
                stroke: stroke,
                widthScale: widthScale
            )
            if let previous, point.connectsToPrevious {
                let previousMapped = map(previous, into: rect)
                let previousNib = nibGeometry(
                    previous,
                    stroke: stroke,
                    widthScale: widthScale
                )
                drawConnector(
                    from: previousMapped,
                    previousNib: previousNib,
                    to: mapped,
                    nib: nib,
                    color: color
                )
            }
            let hasNextInSequence = index < points.count - 1
            let hasNext = hasNextInSequence
                || (index == points.count - 1 && hasFollowingPoint)
            let isEndpoint = StrokePathTopology.isEndpoint(
                hasPrevious: previous != nil,
                connectsToPrevious: point.connectsToPrevious,
                hasNext: hasNext,
                nextConnectsToPrevious: hasNextInSequence
                    ? points[index + 1].connectsToPrevious
                    : hasFollowingPoint
            )
            if isEndpoint {
                color.setFill()
                nibPath(at: mapped, geometry: nib).fill()
            }
            previous = point
        }
    }

    private func drawAsUnifiedStroke(
        color: NSColor,
        draw: (NSColor) -> Void
    ) {
        guard let context = NSGraphicsContext.current?.cgContext,
              let resolved = color.usingColorSpace(.deviceRGB),
              resolved.alphaComponent < 0.999
        else {
            draw(color)
            return
        }
        context.saveGState()
        context.setAlpha(resolved.alphaComponent)
        context.beginTransparencyLayer(auxiliaryInfo: nil)
        draw(resolved.withAlphaComponent(1))
        context.endTransparencyLayer()
        context.restoreGState()
    }

    private func drawConnector(
        from start: NSPoint,
        previousNib: StrokeNibGeometry,
        to end: NSPoint,
        nib: StrokeNibGeometry,
        color: NSColor
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
        color.setStroke()
        let midpoint = NSPoint(
            x: (start.x + end.x) / 2,
            y: (start.y + end.y) / 2
        )
        drawConnectorSegment(
            from: start,
            to: midpoint,
            width: startWidth * 0.75 + endWidth * 0.25
        )
        drawConnectorSegment(
            from: midpoint,
            to: end,
            width: startWidth * 0.25 + endWidth * 0.75
        )
    }

    private func drawConnectorSegment(
        from start: NSPoint,
        to end: NSPoint,
        width: Double
    ) {
        let connector = NSBezierPath()
        connector.move(to: start)
        connector.line(to: end)
        connector.lineCapStyle = .round
        connector.lineJoinStyle = .round
        connector.lineWidth = CGFloat(width)
        connector.stroke()
    }

    private func drawSelection(
        in rect: NSRect,
        widthScale: Double
    ) {
        guard let document, !selectedStrokeIDs.isEmpty else {
            return
        }
        for stroke in document.manifest.strokes where
            selectedStrokeIDs.contains(stroke.id)
        {
            guard let first = stroke.points.first else {
                continue
            }
            var strokeBounds = NSRect(
                origin: map(first, into: rect),
                size: .zero
            )
            var maximumNibWidth: Double = 0
            for point in stroke.points {
                let mapped = map(point, into: rect)
                strokeBounds = strokeBounds.union(
                    NSRect(origin: mapped, size: .zero)
                )
                maximumNibWidth = max(
                    maximumNibWidth,
                    nibGeometry(
                        point,
                        stroke: stroke,
                        widthScale: widthScale
                    ).majorAxis
                )
            }
            let selectionBounds = strokeBounds.insetBy(
                dx: -CGFloat(maximumNibWidth / 2 + 6),
                dy: -CGFloat(maximumNibWidth / 2 + 6)
            )
            for point in selectionDotCenters(
                in: selectionBounds,
                cornerRadius: 5,
                spacing: 5
            ) {
                adaptiveSelectionColor(at: point, imageRect: rect).setFill()
                NSBezierPath(
                    ovalIn: NSRect(
                        x: point.x - 1.1,
                        y: point.y - 1.1,
                        width: 2.2,
                        height: 2.2
                    )
                ).fill()
            }
        }
    }

    private func selectionDotCenters(
        in rect: NSRect,
        cornerRadius: CGFloat,
        spacing: CGFloat
    ) -> [NSPoint] {
        let radius = min(
            cornerRadius,
            rect.width / 2,
            rect.height / 2
        )
        var points: [NSPoint] = []
        func appendLine(_ start: NSPoint, _ end: NSPoint) {
            let length = hypot(end.x - start.x, end.y - start.y)
            let count = max(1, Int((length / spacing).rounded(.down)))
            for index in 0..<count {
                let progress = CGFloat(index) / CGFloat(count)
                points.append(
                    NSPoint(
                        x: start.x + (end.x - start.x) * progress,
                        y: start.y + (end.y - start.y) * progress
                    )
                )
            }
        }
        func appendArc(
            center: NSPoint,
            startAngle: CGFloat,
            endAngle: CGFloat
        ) {
            let length = radius * abs(endAngle - startAngle)
            let count = max(1, Int((length / spacing).rounded(.down)))
            for index in 0..<count {
                let progress = CGFloat(index) / CGFloat(count)
                let angle = startAngle
                    + (endAngle - startAngle) * progress
                points.append(
                    NSPoint(
                        x: center.x + cos(angle) * radius,
                        y: center.y + sin(angle) * radius
                    )
                )
            }
        }

        appendLine(
            NSPoint(x: rect.minX + radius, y: rect.minY),
            NSPoint(x: rect.maxX - radius, y: rect.minY)
        )
        appendArc(
            center: NSPoint(
                x: rect.maxX - radius,
                y: rect.minY + radius
            ),
            startAngle: -.pi / 2,
            endAngle: 0
        )
        appendLine(
            NSPoint(x: rect.maxX, y: rect.minY + radius),
            NSPoint(x: rect.maxX, y: rect.maxY - radius)
        )
        appendArc(
            center: NSPoint(
                x: rect.maxX - radius,
                y: rect.maxY - radius
            ),
            startAngle: 0,
            endAngle: .pi / 2
        )
        appendLine(
            NSPoint(x: rect.maxX - radius, y: rect.maxY),
            NSPoint(x: rect.minX + radius, y: rect.maxY)
        )
        appendArc(
            center: NSPoint(
                x: rect.minX + radius,
                y: rect.maxY - radius
            ),
            startAngle: .pi / 2,
            endAngle: .pi
        )
        appendLine(
            NSPoint(x: rect.minX, y: rect.maxY - radius),
            NSPoint(x: rect.minX, y: rect.minY + radius)
        )
        appendArc(
            center: NSPoint(
                x: rect.minX + radius,
                y: rect.minY + radius
            ),
            startAngle: .pi,
            endAngle: .pi * 1.5
        )
        return points
    }

    private func adaptiveSelectionColor(
        at point: NSPoint,
        imageRect: NSRect
    ) -> NSColor {
        if document?.manifest.pageKind == .blank,
           let background = document?.manifest.backgroundColor
        {
            return selectionColor(for: NSColor(background))
        }
        guard let representation = screenshotRepresentation,
              imageRect.width > 0,
              imageRect.height > 0
        else {
            return .white
        }
        let localX = min(
            1,
            max(0, (point.x - imageRect.minX) / imageRect.width)
        )
        let localY = min(
            1,
            max(0, (point.y - imageRect.minY) / imageRect.height)
        )
        let sourcePoint = TracePageViewport.unmap(
            TracePoint(x: localX, y: localY),
            through: resolvedViewport()
        )
        let x = min(
            representation.pixelsWide - 1,
            max(
                0,
                Int(sourcePoint.x * Double(representation.pixelsWide))
            )
        )
        let y = min(
            representation.pixelsHigh - 1,
            max(
                0,
                Int(sourcePoint.y * Double(representation.pixelsHigh))
            )
        )
        guard let color = representation.colorAt(x: x, y: y)?
            .usingColorSpace(.deviceRGB)
        else {
            return .white
        }
        return selectionColor(for: color)
    }

    private func selectionColor(for color: NSColor) -> NSColor {
        guard let color = color.usingColorSpace(.deviceRGB) else {
            return .white
        }
        switch TraceAdaptiveContrast.selectionTone(
            red: color.redComponent,
            green: color.greenComponent,
            blue: color.blueComponent
        ) {
        case .black:
            return NSColor.black.withAlphaComponent(0.82)
        case .white:
            return NSColor.white.withAlphaComponent(0.94)
        }
    }

    private func bitmapRepresentation(
        of image: NSImage
    ) -> NSBitmapImageRep? {
        if let representation = image.representations.first(where: {
            $0 is NSBitmapImageRep
        }) as? NSBitmapImageRep {
            return representation
        }
        guard let data = image.tiffRepresentation else {
            return nil
        }
        return NSBitmapImageRep(data: data)
    }

    private func deleteSelectedStroke() {
        guard let document, !selectedStrokeIDs.isEmpty else {
            return
        }
        let before = document.manifest.strokes
        document.manifest.strokes.removeAll {
            selectedStrokeIDs.contains($0.id)
        }
        setSelection([])
        predictedStroke = nil
        needsDisplay = true
        onDocumentEdited?(before, document.manifest.strokes)
    }

    private func setSelection(_ selection: Set<UInt64>) {
        let wasSelecting = !selectedStrokeIDs.isEmpty
        selectedStrokeIDs = selection
        let isSelecting = !selectedStrokeIDs.isEmpty
        if wasSelecting != isSelecting {
            onSelectionModeChanged?(isSelecting)
        }
    }

    private func map(
        _ point: TraceDrawingPoint,
        into rect: NSRect
    ) -> NSPoint {
        let local = TracePageViewport.map(
            TracePoint(x: point.x, y: point.y),
            through: resolvedViewport()
        )
        return NSPoint(
            x: rect.minX + local.x * rect.width,
            y: rect.minY + local.y * rect.height
        )
    }

    private func resolvedViewport() -> TraceRect {
        document?.manifest.viewport ?? TracePageViewport.full
    }

    private func sourcePointSize() -> TraceSize {
        guard let document else {
            return TraceSize(
                width: bounds.width,
                height: bounds.height
            )
        }
        return document.manifest.sourceWindowBounds.map {
            TraceSize(width: $0.width, height: $0.height)
        } ?? TraceSize(
            width: Double(document.manifest.screenshotPixelWidth),
            height: Double(document.manifest.screenshotPixelHeight)
        )
    }

    private func nibGeometry(
        _ point: TraceDrawingPoint,
        stroke: TraceDrawingStroke,
        widthScale: Double
    ) -> StrokeNibGeometry {
        let pressureWidth = widthPolicy.width(for: point.pressure)
        let selectedScale = stroke.width / widthPolicy.maximumWidth
        return nibPolicy.geometry(
            baseWidth: pressureWidth
                * selectedScale
                * TraceToolWidthPolicy.brushScale(for: stroke.brush)
                * widthScale,
            tiltX: point.tiltX,
            tiltY: point.tiltY,
            twistDegrees: point.twistDegrees
        )
    }

    private func nibPath(
        at point: NSPoint,
        geometry: StrokeNibGeometry
    ) -> NSBezierPath {
        let width = CGFloat(geometry.majorAxis)
        let height = CGFloat(geometry.minorAxis)
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

    private func brushAlpha(_ brush: TraceBrushKind) -> CGFloat {
        switch brush {
        case .pen:
            return 1
        case .marker:
            return 0.82
        case .highlighter:
            return 0.5
        }
    }

    private func exportWidthScale(
        _ manifest: TraceDrawingManifest
    ) -> Double {
        guard let source = manifest.sourceWindowBounds,
              source.width > 0,
              source.height > 0
        else {
            return 1
        }
        let scaleX = Double(manifest.screenshotPixelWidth) / source.width
        let scaleY = Double(manifest.screenshotPixelHeight) / source.height
        return (scaleX + scaleY) / 2
    }

    private func displayWidthScale(
        _ manifest: TraceDrawingManifest,
        imageRect: NSRect
    ) -> Double {
        let sourceWidth = manifest.sourceWindowBounds?.width
            ?? Double(manifest.screenshotPixelWidth)
        let sourceHeight = manifest.sourceWindowBounds?.height
            ?? Double(manifest.screenshotPixelHeight)
        guard sourceWidth > 0, sourceHeight > 0 else {
            return 1
        }
        return (
            Double(imageRect.width)
                / (sourceWidth * resolvedViewport().width)
                + Double(imageRect.height)
                / (sourceHeight * resolvedViewport().height)
        ) / 2
    }
}

final class CompletedInkView: NSView {
    private weak var canvas: AnnotationCanvasView?
#if DEBUG
    private(set) var renderCount = 0
#endif

    override var isFlipped: Bool {
        true
    }

    override var isOpaque: Bool {
        false
    }

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        wantsLayer = true
        layer?.needsDisplayOnBoundsChange = true
        layerContentsRedrawPolicy = .onSetNeedsDisplay
    }

    required init?(coder: NSCoder) {
        nil
    }

    func attach(to canvas: AnnotationCanvasView) {
        self.canvas = canvas
    }

    func invalidateInk() {
        needsDisplay = true
    }

    override func draw(_ dirtyRect: NSRect) {
        super.draw(dirtyRect)
#if DEBUG
        renderCount += 1
#endif
        NSGraphicsContext.current?.cgContext.clear(dirtyRect)
        canvas?.drawCompletedStrokes()
    }

#if DEBUG
    func resetRenderCountForTesting() {
        renderCount = 0
    }
#endif
}
