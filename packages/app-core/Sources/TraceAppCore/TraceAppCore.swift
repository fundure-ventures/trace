import Foundation

public enum TraceAppPhase: Equatable, Sendable {
    case waitingForPen
    case armed
    case capturing
    case annotating(documentID: UUID)
}

public enum TraceAppEvent: Equatable, Sendable {
    case penConnected
    case penDisconnected
    case captureStarted
    case manualCaptureStarted
    case captureSucceeded(UUID)
    case captureFailed
    case drawingOpened(UUID)
    case copiedAndHidden
    case boardClosed
}

public struct TraceAppStateMachine: Equatable, Sendable {
    public private(set) var phase: TraceAppPhase
    public private(set) var penConnected: Bool

    public init(penConnected: Bool) {
        self.penConnected = penConnected
        if penConnected {
            phase = .armed
        } else {
            phase = .waitingForPen
        }
    }

    public mutating func receive(_ event: TraceAppEvent) {
        switch event {
        case .penConnected:
            penConnected = true
            switch phase {
            case .capturing, .annotating:
                break
            case .waitingForPen, .armed:
                phase = .armed
            }
        case .penDisconnected:
            penConnected = false
            phase = .waitingForPen
        case .captureStarted:
            guard penConnected,
                  phase == .armed
            else {
                return
            }
            phase = .capturing
        case .manualCaptureStarted:
            phase = .capturing
        case let .captureSucceeded(documentID),
             let .drawingOpened(documentID):
            phase = .annotating(documentID: documentID)
        case .captureFailed, .copiedAndHidden, .boardClosed:
            phase = penConnected ? .armed : .waitingForPen
        }
    }

    public func shouldAnnotate(strokeID _: UInt64) -> Bool {
        if case .annotating = phase {
            return true
        }
        return false
    }
}

public struct TraceCaptureEventRouter<Element> {
    private var storage: [Element] = []
    public private(set) var isCapturing = false

    public init() {}

    public mutating func startCapture() {
        storage.removeAll(keepingCapacity: true)
        isCapturing = true
    }

    public mutating func route(_ event: Element) -> Element? {
        guard isCapturing else {
            return event
        }
        storage.append(event)
        return nil
    }

    public mutating func finishCapture() -> [Element] {
        isCapturing = false
        defer {
            storage.removeAll(keepingCapacity: true)
        }
        return storage
    }

    public mutating func cancelCapture() {
        isCapturing = false
        storage.removeAll(keepingCapacity: true)
    }
}

public struct TraceAutosaveGate: Equatable, Sendable {
    private var generation: UInt64 = 0

    public init() {}

    public mutating func schedule() -> UInt64 {
        generation &+= 1
        return generation
    }

    public mutating func cancel() {
        generation &+= 1
    }

    public func isCurrent(_ token: UInt64) -> Bool {
        token == generation
    }
}

public struct TraceDocumentCopyProgress: Equatable, Sendable {
    private var documentID: UUID?

    public init() {}

    public var isActive: Bool {
        documentID != nil
    }

    public mutating func begin(for documentID: UUID) -> Bool {
        guard self.documentID == nil else {
            return false
        }
        self.documentID = documentID
        return true
    }

    public mutating func end(for documentID: UUID) -> Bool {
        guard self.documentID == documentID else {
            return false
        }
        self.documentID = nil
        return true
    }

    public mutating func cancelForDocumentPresentation() -> Bool {
        guard documentID != nil else {
            return false
        }
        documentID = nil
        return true
    }
}

public enum TraceAutosavePolicy {
    public static let idleDelaySeconds: TimeInterval = 0.6
}

public struct TracePoint: Codable, Equatable, Sendable {
    public let x: Double
    public let y: Double

    public init(x: Double, y: Double) {
        self.x = x
        self.y = y
    }
}

public struct TraceSize: Codable, Equatable, Sendable {
    public let width: Double
    public let height: Double

    public init(width: Double, height: Double) {
        self.width = width
        self.height = height
    }
}

public enum TraceBoardSizingPolicy {
    public static func fit(
        source: TraceSize,
        maximum: TraceSize
    ) -> TraceSize {
        guard source.width > 0, source.height > 0 else {
            return TraceSize(width: 1, height: 1)
        }
        let scale = min(
            1,
            maximum.width / source.width,
            maximum.height / source.height
        )
        return TraceSize(
            width: source.width * scale,
            height: source.height * scale
        )
    }
}

public struct TraceRect: Codable, Equatable, Sendable {
    public let x: Double
    public let y: Double
    public let width: Double
    public let height: Double

    public init(x: Double, y: Double, width: Double, height: Double) {
        self.x = x
        self.y = y
        self.width = width
        self.height = height
    }

    public func contains(_ point: TracePoint) -> Bool {
        point.x >= x
            && point.x <= x + width
            && point.y >= y
            && point.y <= y + height
    }
}

public enum TracePageViewport {
    public static let full = TraceRect(
        x: 0,
        y: 0,
        width: 1,
        height: 1
    )

    public static func centeredCrop(
        source: TraceSize,
        viewport: TraceSize
    ) -> TraceRect {
        guard source.width > 0,
              source.height > 0,
              viewport.width > 0,
              viewport.height > 0
        else {
            return full
        }
        let width = min(1, viewport.width / source.width)
        let height = min(1, viewport.height / source.height)
        return TraceRect(
            x: (1 - width) / 2,
            y: (1 - height) / 2,
            width: width,
            height: height
        )
    }

    public static func centeredFit(
        contentAspectRatio: Double,
        in viewport: TraceSize
    ) -> TraceRect {
        guard contentAspectRatio.isFinite,
              contentAspectRatio > 0,
              viewport.width > 0,
              viewport.height > 0
        else {
            return full
        }
        let viewportAspectRatio = viewport.width / viewport.height
        if contentAspectRatio < viewportAspectRatio {
            let width = contentAspectRatio / viewportAspectRatio
            return TraceRect(
                x: (1 - width) / 2,
                y: 0,
                width: width,
                height: 1
            )
        }
        let height = viewportAspectRatio / contentAspectRatio
        return TraceRect(
            x: 0,
            y: (1 - height) / 2,
            width: 1,
            height: height
        )
    }

    public static func map(
        _ sourcePoint: TracePoint,
        through viewport: TraceRect
    ) -> TracePoint {
        guard viewport.width > 0, viewport.height > 0 else {
            return sourcePoint
        }
        return TracePoint(
            x: (sourcePoint.x - viewport.x) / viewport.width,
            y: (sourcePoint.y - viewport.y) / viewport.height
        )
    }

    public static func unmap(
        _ localPoint: TracePoint,
        through viewport: TraceRect
    ) -> TracePoint {
        TracePoint(
            x: viewport.x + localPoint.x * viewport.width,
            y: viewport.y + localPoint.y * viewport.height
        )
    }
}

public struct TraceWindowDescriptor: Equatable, Sendable {
    public let id: UInt32
    public let ownerPID: Int32
    public let layer: Int
    public let alpha: Double
    public let bounds: TraceRect
    public let ownerName: String
    public let title: String

    public init(
        id: UInt32,
        ownerPID: Int32,
        layer: Int,
        alpha: Double,
        bounds: TraceRect,
        ownerName: String,
        title: String
    ) {
        self.id = id
        self.ownerPID = ownerPID
        self.layer = layer
        self.alpha = alpha
        self.bounds = bounds
        self.ownerName = ownerName
        self.title = title
    }
}

public struct TraceBoardLayout: Equatable, Sendable {
    public let board: TraceRect
    public let toolbar: TraceRect

    public init(board: TraceRect, toolbar: TraceRect) {
        self.board = board
        self.toolbar = toolbar
    }
}

public enum TraceBoardLayoutPolicy {
    public static func place(
        source: TraceSize,
        visibleFrame: TraceRect,
        toolbar: TraceSize,
        gap: Double,
        margin: Double
    ) -> TraceBoardLayout {
        let maximum = TraceSize(
            width: max(1, visibleFrame.width - margin * 2),
            height: max(
                1,
                visibleFrame.height
                    - margin * 2
                    - toolbar.height
                    - gap
            )
        )
        let fitted = TraceBoardSizingPolicy.fit(
            source: source,
            maximum: maximum
        )
        let totalHeight = fitted.height + gap + toolbar.height
        let board = TraceRect(
            x: round(
                visibleFrame.x
                    + (visibleFrame.width - fitted.width) / 2
            ),
            y: round(
                visibleFrame.y
                    + (visibleFrame.height - totalHeight) / 2
            ),
            width: fitted.width,
            height: fitted.height
        )
        let idealToolbarX = board.x
            + (board.width - toolbar.width) / 2
        let toolbarX = min(
            visibleFrame.x
                + visibleFrame.width
                - toolbar.width
                - margin,
            max(visibleFrame.x + margin, idealToolbarX)
        )
        return TraceBoardLayout(
            board: board,
            toolbar: TraceRect(
                x: round(toolbarX),
                y: board.y + board.height + gap,
                width: toolbar.width,
                height: toolbar.height
            )
        )
    }
}

public enum TraceBlankViewportPolicy {
    public static let defaultSize = TraceSize(width: 900, height: 650)
    public static let minimumSize = TraceSize(width: 320, height: 240)
    public static let maximumSize = TraceSize(width: 4_096, height: 4_096)

    public static func validated(_ size: TraceSize) -> TraceSize {
        guard size.width.isFinite,
              size.height.isFinite,
              size.width > 0,
              size.height > 0
        else {
            return defaultSize
        }
        return TraceSize(
            width: min(
                maximumSize.width,
                max(minimumSize.width, size.width)
            ),
            height: min(
                maximumSize.height,
                max(minimumSize.height, size.height)
            )
        )
    }

    public static func calibrated(
        aspectRatio: Double,
        reference: TraceSize,
        maximum: TraceSize
    ) -> TraceSize {
        guard aspectRatio.isFinite,
              aspectRatio > 0,
              maximum.width > 0,
              maximum.height > 0
        else {
            return validated(reference)
        }
        let reference = validated(reference)
        let area = reference.width * reference.height
        var candidate = TraceSize(
            width: sqrt(area * aspectRatio),
            height: sqrt(area / aspectRatio)
        )
        let fitScale = min(
            1,
            maximum.width / candidate.width,
            maximum.height / candidate.height
        )
        candidate = TraceSize(
            width: candidate.width * fitScale,
            height: candidate.height * fitScale
        )
        let minimumScale = max(
            1,
            minimumSize.width / candidate.width,
            minimumSize.height / candidate.height
        )
        if candidate.width * minimumScale <= maximum.width,
           candidate.height * minimumScale <= maximum.height
        {
            candidate = TraceSize(
                width: candidate.width * minimumScale,
                height: candidate.height * minimumScale
            )
        }
        return candidate
    }
}

public enum TraceWindowSilhouette {
    public static func cornerRadiusPoints(
        horizontalInsetPixels: Int,
        verticalInsetPixels: Int,
        pixelSize: TraceSize,
        sourceSize: TraceSize
    ) -> Double {
        guard pixelSize.width > 0,
              pixelSize.height > 0,
              sourceSize.width > 0,
              sourceSize.height > 0
        else {
            return 0
        }
        let horizontal = Double(horizontalInsetPixels)
            / (pixelSize.width / sourceSize.width)
        let vertical = Double(verticalInsetPixels)
            / (pixelSize.height / sourceSize.height)
        return max(0, (horizontal + vertical) / 2)
    }
}

public struct TraceGridMetrics: Equatable, Sendable {
    public let horizontalSpacing: Double
    public let verticalSpacing: Double
    public let dotDiameter: Double
    public let lineWidth: Double

    public init(
        horizontalSpacing: Double,
        verticalSpacing: Double,
        dotDiameter: Double,
        lineWidth: Double
    ) {
        self.horizontalSpacing = horizontalSpacing
        self.verticalSpacing = verticalSpacing
        self.dotDiameter = dotDiameter
        self.lineWidth = lineWidth
    }
}

public enum TraceGridStyle:
    String,
    CaseIterable,
    Equatable,
    Sendable
{
    case none
    case dots
    case square
    case horizontal
    case vertical
}

public enum TraceGridControlPolicy {
    public static func style(forSegment segment: Int) -> TraceGridStyle {
        switch segment {
        case 1:
            return .dots
        case 2:
            return .square
        case 3:
            return .horizontal
        case 4:
            return .vertical
        default:
            return .none
        }
    }

    public static func segment(for style: TraceGridStyle) -> Int {
        switch style {
        case .none:
            return 0
        case .dots:
            return 1
        case .square:
            return 2
        case .horizontal:
            return 3
        case .vertical:
            return 4
        }
    }
}

public enum TraceGridPolicy {
    public static let minimumSpacingPoints = 4
    public static let maximumSpacingPoints = 64
    public static let defaultSpacingPoints = 8
    public static let dotDiameterPoints = 1.0
    public static let lineWidthPoints = 1.0

    public static func clampedSpacing(_ spacing: Int) -> Int {
        min(
            maximumSpacingPoints,
            max(minimumSpacingPoints, spacing)
        )
    }

    public static func steppedSpacing(
        current: Int?,
        delta: Int
    ) -> Int {
        clampedSpacing(
            (current ?? minimumSpacingPoints) + delta
        )
    }

    public static func spacing(from input: String) -> Int {
        clampedSpacing(
            Int(input.trimmingCharacters(in: .whitespacesAndNewlines))
                ?? minimumSpacingPoints
        )
    }

    public static func metrics(
        spacingPoints: Int,
        displaySize: TraceSize
    ) -> TraceGridMetrics? {
        guard displaySize.width > 0,
              displaySize.height > 0
        else {
            return nil
        }
        let spacing = Double(clampedSpacing(spacingPoints))
        return TraceGridMetrics(
            horizontalSpacing: spacing,
            verticalSpacing: spacing,
            dotDiameter: dotDiameterPoints,
            lineWidth: lineWidthPoints
        )
    }
}

public enum TraceContrastTone: Equatable, Sendable {
    case black
    case white
}

public enum TraceAdaptiveContrast {
    public static func selectionTone(
        red: Double,
        green: Double,
        blue: Double
    ) -> TraceContrastTone {
        let luminance = red * 0.2126
            + green * 0.7152
            + blue * 0.0722
        return luminance > 0.52 ? .black : .white
    }
}

public enum WindowSelectionPolicy {
    public static func select<Windows: Sequence>(
        at point: TracePoint,
        windowsFrontToBack: Windows,
        excludingOwnerPID: Int32
    ) -> TraceWindowDescriptor?
    where Windows.Element == TraceWindowDescriptor {
        windowsFrontToBack.first {
            isEligible($0, excludingOwnerPID: excludingOwnerPID)
                && $0.bounds.contains(point)
        }
    }

    public static func frontmost<Windows: Sequence>(
        windowsFrontToBack: Windows,
        excludingOwnerPID: Int32
    ) -> TraceWindowDescriptor?
    where Windows.Element == TraceWindowDescriptor {
        windowsFrontToBack.first {
            isEligible($0, excludingOwnerPID: excludingOwnerPID)
        }
    }

    private static func isEligible(
        _ window: TraceWindowDescriptor,
        excludingOwnerPID: Int32
    ) -> Bool {
        window.ownerPID != excludingOwnerPID
            && window.layer == 0
            && window.alpha > 0.01
            && window.bounds.width >= 80
            && window.bounds.height >= 60
            && !excludedOwners.contains(window.ownerName)
    }

    private static let excludedOwners: Set<String> = [
        "Control Center",
        "Dock",
        "Notification Center",
        "SystemUIServer",
        "Window Server",
    ]
}

public enum TraceBrushKind: String, Codable, CaseIterable, Equatable, Sendable {
    case pen
    case marker
    case highlighter
}

public struct TraceRGBAColor: Codable, Equatable, Sendable {
    public let red: Double
    public let green: Double
    public let blue: Double
    public let alpha: Double

    public init(
        red: Double,
        green: Double,
        blue: Double,
        alpha: Double = 1
    ) {
        self.red = red
        self.green = green
        self.blue = blue
        self.alpha = alpha
    }

    public static let red = TraceRGBAColor(
        red: 0.96,
        green: 0.19,
        blue: 0.18
    )
    public static let blue = TraceRGBAColor(
        red: 0.10,
        green: 0.43,
        blue: 0.96
    )
    public static let yellow = TraceRGBAColor(
        red: 0.96,
        green: 0.72,
        blue: 0.12
    )
    public static let green = TraceRGBAColor(
        red: 0.12,
        green: 0.68,
        blue: 0.32
    )
}

public struct TraceDrawingPoint: Codable, Equatable, Sendable {
    public let x: Double
    public let y: Double
    public let pressure: Double?
    public let tiltX: Double?
    public let tiltY: Double?
    public let twistDegrees: Double?
    public let connectsToPrevious: Bool

    public init(
        x: Double,
        y: Double,
        pressure: Double?,
        tiltX: Double?,
        tiltY: Double?,
        twistDegrees: Double?,
        connectsToPrevious: Bool
    ) {
        self.x = x
        self.y = y
        self.pressure = pressure
        self.tiltX = tiltX
        self.tiltY = tiltY
        self.twistDegrees = twistDegrees
        self.connectsToPrevious = connectsToPrevious
    }
}

public struct TraceTranscriptAnnotation:
    Codable,
    Equatable,
    Sendable
{
    public let id: Int
    public let wordID: Int

    public init(id: Int, wordID: Int) {
        self.id = id
        self.wordID = wordID
    }
}

public struct TraceTranscriptWord: Codable, Equatable, Sendable {
    public let id: Int
    public let text: String
    public let startedAtAppClockSeconds: Double
    public let endedAtAppClockSeconds: Double

    public init(
        id: Int,
        text: String,
        startedAtAppClockSeconds: Double,
        endedAtAppClockSeconds: Double
    ) {
        self.id = id
        self.text = text
        self.startedAtAppClockSeconds = startedAtAppClockSeconds
        self.endedAtAppClockSeconds = endedAtAppClockSeconds
    }
}

public enum TraceTranscriptAnnotationScale:
    String,
    Codable,
    CaseIterable,
    Equatable,
    Hashable,
    Sendable
{
    case small
    case medium
    case large

    public var multiplier: Double {
        switch self {
        case .small:
            return 0.75
        case .medium:
            return 1
        case .large:
            return 1.5
        }
    }
}

public struct TraceDrawingStroke: Codable, Equatable, Sendable {
    public let id: UInt64
    public let color: TraceRGBAColor
    public let brush: TraceBrushKind
    public let width: Double
    public var startedAtAppClockSeconds: Double?
    public var endedAtAppClockSeconds: Double?
    public var transcriptAnnotation: TraceTranscriptAnnotation?
    public var points: [TraceDrawingPoint]

    public init(
        id: UInt64,
        color: TraceRGBAColor,
        brush: TraceBrushKind,
        width: Double,
        startedAtAppClockSeconds: Double? = nil,
        endedAtAppClockSeconds: Double? = nil,
        transcriptAnnotation: TraceTranscriptAnnotation? = nil,
        points: [TraceDrawingPoint]
    ) {
        self.id = id
        self.color = color
        self.brush = brush
        self.width = width
        self.startedAtAppClockSeconds = startedAtAppClockSeconds
        self.endedAtAppClockSeconds = endedAtAppClockSeconds
        self.transcriptAnnotation = transcriptAnnotation
        self.points = points
    }
}

public struct TraceTimedCanvasShape: Codable, Equatable, Sendable {
    public let id: String
    public let startedAtAppClockSeconds: Double
    public let endedAtAppClockSeconds: Double
    public var pathLength: Double
    public var transcriptAnnotation: TraceTranscriptAnnotation?

    public init(
        id: String,
        startedAtAppClockSeconds: Double,
        endedAtAppClockSeconds: Double,
        pathLength: Double,
        transcriptAnnotation: TraceTranscriptAnnotation? = nil
    ) {
        self.id = id
        self.startedAtAppClockSeconds = startedAtAppClockSeconds
        self.endedAtAppClockSeconds = endedAtAppClockSeconds
        self.pathLength = pathLength
        self.transcriptAnnotation = transcriptAnnotation
    }
}

public enum TraceDrawingCoordinateSpace: String, Codable, Equatable, Sendable {
    case surfaceNormalized = "surface-normalized"
}

public enum TracePageKind: String, Codable, Equatable, Sendable {
    case screenshot
    case blank
}

public struct TraceDrawingManifest: Codable, Equatable, Sendable {
    public let schemaVersion: Int
    public let id: UUID
    public let createdAt: Date
    public var updatedAt: Date
    public let sourceApplicationName: String
    public let sourceWindowTitle: String
    public let screenshotFileName: String
    public var screenshotPixelWidth: Int
    public var screenshotPixelHeight: Int
    public let coordinateSpace: TraceDrawingCoordinateSpace?
    public var sourceWindowCornerRadius: Double?
    public var sourceWindowBounds: TraceRect?
    public var pageKind: TracePageKind?
    public var backgroundColor: TraceRGBAColor?
    public var viewport: TraceRect?
    public var voiceRecordingFileName: String?
    public var transcriptFileName: String?
    public var transcriptText: String?
    public var transcriptWords: [TraceTranscriptWord]?
    public var timedCanvasShapes: [TraceTimedCanvasShape]?
    public var strokes: [TraceDrawingStroke]

    public init(
        schemaVersion: Int = 1,
        id: UUID,
        createdAt: Date,
        updatedAt: Date,
        sourceApplicationName: String,
        sourceWindowTitle: String,
        screenshotFileName: String,
        screenshotPixelWidth: Int,
        screenshotPixelHeight: Int,
        coordinateSpace: TraceDrawingCoordinateSpace? = .surfaceNormalized,
        sourceWindowCornerRadius: Double? = nil,
        sourceWindowBounds: TraceRect? = nil,
        pageKind: TracePageKind? = nil,
        backgroundColor: TraceRGBAColor? = nil,
        viewport: TraceRect? = nil,
        voiceRecordingFileName: String? = nil,
        transcriptFileName: String? = nil,
        transcriptText: String? = nil,
        transcriptWords: [TraceTranscriptWord]? = nil,
        timedCanvasShapes: [TraceTimedCanvasShape]? = nil,
        strokes: [TraceDrawingStroke]
    ) {
        self.schemaVersion = schemaVersion
        self.id = id
        self.createdAt = createdAt
        self.updatedAt = updatedAt
        self.sourceApplicationName = sourceApplicationName
        self.sourceWindowTitle = sourceWindowTitle
        self.screenshotFileName = screenshotFileName
        self.screenshotPixelWidth = screenshotPixelWidth
        self.screenshotPixelHeight = screenshotPixelHeight
        self.coordinateSpace = coordinateSpace
        self.sourceWindowCornerRadius = sourceWindowCornerRadius
        self.sourceWindowBounds = sourceWindowBounds
        self.pageKind = pageKind
        self.backgroundColor = backgroundColor
        self.viewport = viewport
        self.voiceRecordingFileName = voiceRecordingFileName
        self.transcriptFileName = transcriptFileName
        self.transcriptText = transcriptText
        self.transcriptWords = transcriptWords
        self.timedCanvasShapes = timedCanvasShapes
        self.strokes = strokes
    }
}

public enum TraceTranscriptAnnotationPlanner {
    public static let maximumFallbackDistanceSeconds = 2.0

    public static func annotating(
        strokes: [TraceDrawingStroke],
        words: [TraceTranscriptWord]
    ) -> [TraceDrawingStroke] {
        annotating(
            strokes: strokes,
            canvasShapes: [],
            words: words
        ).strokes
    }

    public static func annotating(
        strokes: [TraceDrawingStroke],
        canvasShapes: [TraceTimedCanvasShape],
        words: [TraceTranscriptWord]
    ) -> (
        strokes: [TraceDrawingStroke],
        canvasShapes: [TraceTimedCanvasShape]
    ) {
        struct Candidate {
            let kind: Int
            let index: Int
            let startedAt: Double
            let endedAt: Double
            let stableID: String
        }

        let validWords = words.filter(isValid)
        guard !validWords.isEmpty else {
            return (strokes, canvasShapes)
        }
        var resultStrokes = strokes
        var resultCanvasShapes = canvasShapes
        let existingIDs =
            strokes.compactMap(\.transcriptAnnotation?.id)
            + canvasShapes.compactMap(\.transcriptAnnotation?.id)
        var nextAnnotationID = (existingIDs.max() ?? 0) + 1
        var candidates: [Candidate] = []
        for index in resultStrokes.indices {
            let stroke = resultStrokes[index]
            guard stroke.transcriptAnnotation == nil,
                  let startedAt = stroke.startedAtAppClockSeconds,
                  let endedAt = stroke.endedAtAppClockSeconds,
                  startedAt.isFinite,
                  endedAt.isFinite,
                  endedAt >= startedAt
            else {
                continue
            }
            candidates.append(
                Candidate(
                    kind: 0,
                    index: index,
                    startedAt: startedAt,
                    endedAt: endedAt,
                    stableID: String(stroke.id)
                )
            )
        }
        for index in resultCanvasShapes.indices {
            let shape = resultCanvasShapes[index]
            guard shape.transcriptAnnotation == nil,
                  shape.startedAtAppClockSeconds.isFinite,
                  shape.endedAtAppClockSeconds.isFinite,
                  shape.endedAtAppClockSeconds
                    >= shape.startedAtAppClockSeconds
            else {
                continue
            }
            candidates.append(
                Candidate(
                    kind: 1,
                    index: index,
                    startedAt: shape.startedAtAppClockSeconds,
                    endedAt: shape.endedAtAppClockSeconds,
                    stableID: shape.id
                )
            )
        }
        candidates.sort {
            if $0.startedAt != $1.startedAt {
                return $0.startedAt < $1.startedAt
            }
            if $0.kind != $1.kind {
                return $0.kind < $1.kind
            }
            return $0.stableID < $1.stableID
        }
        for candidate in candidates {
            guard let word = matchingWord(
                      startedAt: candidate.startedAt,
                      endedAt: candidate.endedAt,
                      words: validWords
                  )
            else {
                continue
            }
            let annotation = TraceTranscriptAnnotation(
                id: nextAnnotationID,
                wordID: word.id
            )
            if candidate.kind == 0 {
                resultStrokes[candidate.index]
                    .transcriptAnnotation = annotation
            } else {
                resultCanvasShapes[candidate.index]
                    .transcriptAnnotation = annotation
            }
            nextAnnotationID += 1
        }
        return (resultStrokes, resultCanvasShapes)
    }

    public static func annotatedTranscript(
        _ transcript: String,
        words: [TraceTranscriptWord],
        strokes: [TraceDrawingStroke],
        canvasShapes: [TraceTimedCanvasShape] = []
    ) -> String {
        let annotationsByWord = Dictionary(
            grouping:
                strokes.compactMap(\.transcriptAnnotation)
                + canvasShapes.compactMap(\.transcriptAnnotation),
            by: \.wordID
        )
        guard !annotationsByWord.isEmpty else {
            return transcript
        }
        var output = ""
        var cursor = transcript.startIndex
        for word in words.sorted(by: { $0.id < $1.id }) {
            let token = word.text.trimmingCharacters(
                in: .whitespacesAndNewlines
            )
            guard !token.isEmpty,
                  let range = transcript.range(
                      of: token,
                      options: [
                          .caseInsensitive,
                          .diacriticInsensitive,
                      ],
                      range: cursor..<transcript.endIndex
                  )
            else {
                continue
            }
            output.append(contentsOf: transcript[cursor..<range.upperBound])
            for annotation in (
                annotationsByWord[word.id] ?? []
            ).sorted(by: { $0.id < $1.id }) {
                output.append(" [\(annotation.id)]")
            }
            cursor = range.upperBound
        }
        output.append(contentsOf: transcript[cursor...])
        return output
    }

    public static func labelDiameter(
        pathLength: Double,
        annotationID: Int,
        scale: TraceTranscriptAnnotationScale = .medium
    ) -> Double {
        let lengthBased = 10 + sqrt(max(0, pathLength)) * 0.65
        let digitCount = String(abs(annotationID)).count
        let digitsBased = 10 + Double(digitCount) * 4
        return min(26, max(12, lengthBased, digitsBased))
            * scale.multiplier
    }

    private static func isValid(_ word: TraceTranscriptWord) -> Bool {
        !word.text.trimmingCharacters(
            in: .whitespacesAndNewlines
        ).isEmpty
            && word.startedAtAppClockSeconds.isFinite
            && word.endedAtAppClockSeconds.isFinite
            && word.endedAtAppClockSeconds
                >= word.startedAtAppClockSeconds
    }

    private static func matchingWord(
        startedAt: Double,
        endedAt: Double,
        words: [TraceTranscriptWord]
    ) -> TraceTranscriptWord? {
        struct Candidate {
            let word: TraceTranscriptWord
            let overlaps: Bool
            let overlap: Double
            let distance: Double
        }

        var best: Candidate?
        for word in words {
            let overlaps = startedAt <= word.endedAtAppClockSeconds
                && endedAt >= word.startedAtAppClockSeconds
            let overlap = max(
                0,
                min(endedAt, word.endedAtAppClockSeconds)
                    - max(startedAt, word.startedAtAppClockSeconds)
            )
            let distance: Double
            if endedAt < word.startedAtAppClockSeconds {
                distance = word.startedAtAppClockSeconds - endedAt
            } else if startedAt > word.endedAtAppClockSeconds {
                distance = startedAt - word.endedAtAppClockSeconds
            } else {
                distance = 0
            }
            let candidate = Candidate(
                word: word,
                overlaps: overlaps,
                overlap: overlap,
                distance: distance
            )
            guard let current = best else {
                best = candidate
                continue
            }
            if candidate.overlaps != current.overlaps {
                if candidate.overlaps {
                    best = candidate
                }
            } else if candidate.overlap != current.overlap {
                if candidate.overlap > current.overlap {
                    best = candidate
                }
            } else if candidate.distance != current.distance {
                if candidate.distance < current.distance {
                    best = candidate
                }
            } else if candidate.word.id < current.word.id {
                best = candidate
            }
        }
        guard let best,
              best.overlaps
                || best.distance <= maximumFallbackDistanceSeconds
        else {
            return nil
        }
        return best.word
    }
}

public struct TraceDrawingHistory {
    private struct Entry {
        let before: [TraceDrawingStroke]
        let after: [TraceDrawingStroke]
    }

    private var undoEntries: [Entry] = []
    private var redoEntries: [Entry] = []

    public init() {}

    public var canUndo: Bool {
        !undoEntries.isEmpty
    }

    public var canRedo: Bool {
        !redoEntries.isEmpty
    }

    public mutating func record(
        before: [TraceDrawingStroke],
        after: [TraceDrawingStroke]
    ) {
        guard before != after else {
            return
        }
        undoEntries.append(Entry(before: before, after: after))
        redoEntries.removeAll(keepingCapacity: true)
    }

    public mutating func undo() -> [TraceDrawingStroke]? {
        guard let entry = undoEntries.popLast() else {
            return nil
        }
        redoEntries.append(entry)
        return entry.before
    }

    public mutating func redo() -> [TraceDrawingStroke]? {
        guard let entry = redoEntries.popLast() else {
            return nil
        }
        undoEntries.append(entry)
        return entry.after
    }

    public mutating func clear() {
        undoEntries.removeAll(keepingCapacity: true)
        redoEntries.removeAll(keepingCapacity: true)
    }

    public mutating func updateTranscriptMetadata(
        from strokes: [TraceDrawingStroke]
    ) {
        let metadataByID = Dictionary(
            uniqueKeysWithValues: strokes.map { ($0.id, $0) }
        )
        undoEntries = undoEntries.map {
            Entry(
                before: mergingTranscriptMetadata(
                    into: $0.before,
                    from: metadataByID
                ),
                after: mergingTranscriptMetadata(
                    into: $0.after,
                    from: metadataByID
                )
            )
        }
        redoEntries = redoEntries.map {
            Entry(
                before: mergingTranscriptMetadata(
                    into: $0.before,
                    from: metadataByID
                ),
                after: mergingTranscriptMetadata(
                    into: $0.after,
                    from: metadataByID
                )
            )
        }
    }

    public mutating func clearTranscriptAnnotations() {
        undoEntries = undoEntries.map {
            Entry(
                before: clearingTranscriptAnnotations(in: $0.before),
                after: clearingTranscriptAnnotations(in: $0.after)
            )
        }
        redoEntries = redoEntries.map {
            Entry(
                before: clearingTranscriptAnnotations(in: $0.before),
                after: clearingTranscriptAnnotations(in: $0.after)
            )
        }
    }

    private func mergingTranscriptMetadata(
        into strokes: [TraceDrawingStroke],
        from metadataByID: [UInt64: TraceDrawingStroke]
    ) -> [TraceDrawingStroke] {
        strokes.map { stroke in
            guard let metadata = metadataByID[stroke.id] else {
                return stroke
            }
            var updated = stroke
            if let startedAt = metadata.startedAtAppClockSeconds {
                updated.startedAtAppClockSeconds = startedAt
            }
            if let endedAt = metadata.endedAtAppClockSeconds {
                updated.endedAtAppClockSeconds = endedAt
            }
            if let annotation = metadata.transcriptAnnotation {
                updated.transcriptAnnotation = annotation
            }
            return updated
        }
    }

    private func clearingTranscriptAnnotations(
        in strokes: [TraceDrawingStroke]
    ) -> [TraceDrawingStroke] {
        strokes.map { stroke in
            var updated = stroke
            updated.transcriptAnnotation = nil
            return updated
        }
    }
}

public enum TraceStrokeEditing {
    public static func updatedSelection(
        current: Set<UInt64>,
        hitStrokeID: UInt64?,
        extending: Bool
    ) -> Set<UInt64> {
        guard let hitStrokeID else {
            return extending ? current : []
        }
        guard extending else {
            return current.contains(hitStrokeID)
                ? current
                : [hitStrokeID]
        }
        var result = current
        if result.contains(hitStrokeID) {
            result.remove(hitStrokeID)
        } else {
            result.insert(hitStrokeID)
        }
        return result
    }

    public static func selectStroke(
        at point: TracePoint,
        strokes: [TraceDrawingStroke],
        surface: TraceSize,
        tolerance: Double
    ) -> UInt64? {
        guard surface.width > 0, surface.height > 0 else {
            return nil
        }
        let target = TracePoint(
            x: point.x * surface.width,
            y: point.y * surface.height
        )
        for stroke in strokes.reversed() {
            let brushScale: Double
            switch stroke.brush {
            case .pen:
                brushScale = 1
            case .marker:
                brushScale = 1.32
            case .highlighter:
                brushScale = 2.15
            }
            let hitRadius = tolerance
                + stroke.width * brushScale / 2
            var previous: TraceDrawingPoint?
            for candidate in stroke.points {
                let candidatePoint = TracePoint(
                    x: candidate.x * surface.width,
                    y: candidate.y * surface.height
                )
                if distance(target, candidatePoint) <= hitRadius {
                    return stroke.id
                }
                if let previous, candidate.connectsToPrevious {
                    let previousPoint = TracePoint(
                        x: previous.x * surface.width,
                        y: previous.y * surface.height
                    )
                    if distance(
                        target,
                        toSegmentFrom: previousPoint,
                        to: candidatePoint
                    ) <= hitRadius {
                        return stroke.id
                    }
                }
                previous = candidate
            }
        }
        return nil
    }

    public static func translatedPoints(
        _ points: [TraceDrawingPoint],
        requestedDelta: TracePoint
    ) -> [TraceDrawingPoint] {
        guard let minimumX = points.map(\.x).min(),
              let maximumX = points.map(\.x).max(),
              let minimumY = points.map(\.y).min(),
              let maximumY = points.map(\.y).max()
        else {
            return points
        }
        let deltaX = min(
            1 - maximumX,
            max(-minimumX, requestedDelta.x)
        )
        let deltaY = min(
            1 - maximumY,
            max(-minimumY, requestedDelta.y)
        )
        return points.map {
            TraceDrawingPoint(
                x: $0.x + deltaX,
                y: $0.y + deltaY,
                pressure: $0.pressure,
                tiltX: $0.tiltX,
                tiltY: $0.tiltY,
                twistDegrees: $0.twistDegrees,
                connectsToPrevious: $0.connectsToPrevious
            )
        }
    }

    public static func translatedStrokes(
        _ strokes: [TraceDrawingStroke],
        selectedIDs: Set<UInt64>,
        requestedDelta: TracePoint
    ) -> [TraceDrawingStroke] {
        let selectedPoints = strokes
            .filter { selectedIDs.contains($0.id) }
            .flatMap(\.points)
        guard let minimumX = selectedPoints.map(\.x).min(),
              let maximumX = selectedPoints.map(\.x).max(),
              let minimumY = selectedPoints.map(\.y).min(),
              let maximumY = selectedPoints.map(\.y).max()
        else {
            return strokes
        }
        let deltaX = min(
            1 - maximumX,
            max(-minimumX, requestedDelta.x)
        )
        let deltaY = min(
            1 - maximumY,
            max(-minimumY, requestedDelta.y)
        )
        return strokes.map { stroke in
            guard selectedIDs.contains(stroke.id) else {
                return stroke
            }
            var translated = stroke
            translated.points = stroke.points.map {
                TraceDrawingPoint(
                    x: $0.x + deltaX,
                    y: $0.y + deltaY,
                    pressure: $0.pressure,
                    tiltX: $0.tiltX,
                    tiltY: $0.tiltY,
                    twistDegrees: $0.twistDegrees,
                    connectsToPrevious: $0.connectsToPrevious
                )
            }
            return translated
        }
    }

    private static func distance(
        _ first: TracePoint,
        _ second: TracePoint
    ) -> Double {
        hypot(first.x - second.x, first.y - second.y)
    }

    private static func distance(
        _ point: TracePoint,
        toSegmentFrom start: TracePoint,
        to end: TracePoint
    ) -> Double {
        let deltaX = end.x - start.x
        let deltaY = end.y - start.y
        let lengthSquared = deltaX * deltaX + deltaY * deltaY
        guard lengthSquared > 0 else {
            return distance(point, start)
        }
        let progress = max(
            0,
            min(
                1,
                (
                    (point.x - start.x) * deltaX
                        + (point.y - start.y) * deltaY
                ) / lengthSquared
            )
        )
        return distance(
            point,
            TracePoint(
                x: start.x + progress * deltaX,
                y: start.y + progress * deltaY
            )
        )
    }
}

public struct TraceDocumentStrokeIDAllocator: Equatable, Sendable {
    private var nextID: UInt64

    public init(existingStrokes: [TraceDrawingStroke]) {
        nextID = (existingStrokes.map(\.id).max() ?? 0) + 1
    }

    public mutating func allocate() -> UInt64 {
        defer {
            nextID += 1
        }
        return nextID
    }
}

public enum TraceDrawingFileName {
    public static func make(
        applicationName: String,
        date: Date,
        timeZone: TimeZone = .current
    ) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = timeZone
        formatter.dateFormat = "dd-MM-yyyy HH∶mm"
        let invalid = CharacterSet.controlCharacters.union(
            CharacterSet(charactersIn: "/:")
        )
        let cleaned = applicationName.unicodeScalars.map {
            invalid.contains($0) ? " " : String($0)
        }.joined()
        let collapsed = cleaned
            .split(whereSeparator: \.isWhitespace)
            .joined(separator: " ")
        let prefix = collapsed.isEmpty ? "Capture" : collapsed
        return "\(prefix) · \(formatter.string(from: date)).traceboard"
    }
}
