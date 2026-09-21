import AppKit
import NeoInput
#if canImport(PaperKit)
import PaperKit
import PencilKit
#endif
import TraceCalibration
import TraceGeometry
import TraceStrokeProcessing

final class UnavailableLabRendererSurface: LabRendererSurface {
    let view = NSView()
    let childViewControllers: [NSViewController] = []
    var onSamplesRendered: (([RawPenSample], UInt64) -> Void)?
    let unavailableReason: String?

    private let label: NSTextField

    init(title: String, reason: String) {
        unavailableReason = reason
        label = NSTextField(
            wrappingLabelWithString: "\(title) is unavailable.\n\(reason)"
        )
        label.alignment = .center
        label.textColor = .secondaryLabelColor
        view.addSubview(label)
        label.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            label.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            label.centerYAnchor.constraint(equalTo: view.centerYAnchor),
            label.widthAnchor.constraint(lessThanOrEqualToConstant: 460),
        ])
    }

    func updatePresentation(_ presentation: LabRendererPresentation) {}
    func apply(_ update: LabRendererUpdate) {}
    func clear() {}
    func activate() { view.isHidden = false }
    func deactivate() { view.isHidden = true }
}

#if canImport(PaperKit)
@available(macOS 26.0, *)
final class PaperKitRendererSurface:
    NSObject,
    LabRendererSurface,
    PaperMarkupViewController.Delegate
{
    let view: NSView
    let childViewControllers: [NSViewController]
    var onSamplesRendered: (([RawPenSample], UInt64) -> Void)? {
        didSet {
            penOverlay.onSamplesRendered = onSamplesRendered
        }
    }
    let unavailableReason: String? = nil

    private static let initialModelBounds = CGRect(
        origin: .zero,
        size: LabPaperLayout.drawingSize
    )

    private let root = PaperKitRendererRootView()
    private let paperController: PaperMarkupViewController
    private let toolbarController: MarkupToolbarViewController
    private let penOverlay = PaperKitInjectedPenView()
    private let modelBounds = initialModelBounds
    private var penStrokes: [UInt64: [LabRenderPoint]] = [:]
    private var committedPenStrokeCount = 0
    private var isActive = false
    private var didApplyInitialPointerMode = false

    override init() {
        var featureSet = FeatureSet.latest
        featureSet.remove(.links)
        featureSet.remove(.stickers)

        let markup = PaperMarkup(bounds: Self.initialModelBounds)
        paperController = PaperMarkupViewController(
            markup: markup,
            supportedFeatureSet: featureSet
        )
        toolbarController = MarkupToolbarViewController(
            supportedFeatureSet: featureSet
        )
        toolbarController.delegate = paperController
        toolbarController.indirectPointerTouchModes = [
            .selection,
            .drawing,
        ]
        toolbarController.selectedIndirectPointerTouchMode = .selection
        paperController.indirectPointerTouchMode = .selection
        paperController.isEditable = true
        paperController.drawingTool = PKInkingTool(
            .pen,
            color: .black,
            width: 4
        )
        paperController.zoomRange = 1...1
        paperController.contentView = PaperKitBackgroundView()

        view = root
        childViewControllers = [
            paperController,
            toolbarController,
        ]
        super.init()

        paperController.delegate = self
        root.paperView = paperController.view
        root.toolbarView = toolbarController.view
        root.penOverlay = penOverlay
        root.layoutHandler = { [weak self] in
            self?.layout()
        }
        root.addSubview(paperController.view)
        root.addSubview(penOverlay)
        root.addSubview(toolbarController.view)
        penOverlay.onSamplesRendered = { [weak self] samples, uptime in
            self?.onSamplesRendered?(samples, uptime)
        }
    }

    func updatePresentation(_ presentation: LabRendererPresentation) {
        root.needsLayout = true
    }

    func apply(_ update: LabRendererUpdate) {
        if let replacement = update.replacement {
            penStrokes[update.strokeID] = replacement
        } else if !update.committed.isEmpty {
            penStrokes[update.strokeID, default: []].append(
                contentsOf: update.committed
            )
        }
        penOverlay.apply(update, tool: activeInkingTool())
        guard update.isFinal else {
            return
        }
        commitStroke(update.strokeID)
        penStrokes.removeValue(forKey: update.strokeID)
        penOverlay.finishStroke(update.strokeID)
    }

    func clear() {
        penStrokes.removeAll(keepingCapacity: true)
        paperController.markup = PaperMarkup(bounds: modelBounds)
        committedPenStrokeCount = 0
        penOverlay.clear()
    }

    func activate() {
        view.isHidden = false
        guard !isActive else {
            return
        }
        isActive = true
        if !didApplyInitialPointerMode {
            toolbarController.selectedIndirectPointerTouchMode = .selection
            didApplyInitialPointerMode = true
        }
        paperController.indirectPointerTouchMode =
            toolbarController.selectedIndirectPointerTouchMode
        view.window?.makeFirstResponder(paperController.view)
    }

    func deactivate() {
        isActive = false
        view.isHidden = true
    }

    func paperMarkupViewControllerDidChangeMarkup(
        _ paperMarkupViewController: PaperMarkupViewController
    ) {}

#if DEBUG
    var committedPenStrokeCountForTesting: Int {
        committedPenStrokeCount
    }

    var pointerModeForTesting: PaperMarkupViewController.TouchMode {
        paperController.indirectPointerTouchMode
    }

    func setPointerModeForTesting(
        _ mode: PaperMarkupViewController.TouchMode
    ) {
        paperController.indirectPointerTouchMode = mode
    }

    var drawingFrameForTesting: NSRect {
        paperController.view.frame
    }

    var isEditableForTesting: Bool {
        paperController.isEditable
    }

    var paperViewIsFirstResponderForTesting: Bool {
        view.window?.firstResponder === paperController.view
    }

    func mouseTargetsPaperKitForTesting(
        at windowPoint: NSPoint
    ) -> Bool {
        let localPoint = root.convert(windowPoint, from: nil)
        guard let hitView = root.hitTest(localPoint) else {
            return false
        }
        return !(hitView is PaperKitBackgroundView)
    }

    func windowPointForTesting(
        normalized: UnitPoint
    ) -> NSPoint? {
        guard view.window != nil else {
            return nil
        }
        return root.convert(
            NSPoint(
                x:
                    paperController.view.frame.minX
                        + normalized.x
                            * paperController.view.frame.width,
                y:
                    paperController.view.frame.minY
                        + normalized.y
                            * paperController.view.frame.height
            ),
            to: nil
        )
    }

    func mouseHitDescriptionForTesting(
        at windowPoint: NSPoint
    ) -> String {
        let localPoint = root.convert(windowPoint, from: nil)
        let hitView = root.hitTest(localPoint)
        return "hit=\(String(describing: hitView.map { type(of: $0) })) "
            + "windowPoint=\(NSStringFromPoint(windowPoint)) "
            + "localPoint=\(NSStringFromPoint(localPoint)) "
            + "root=\(NSStringFromRect(root.frame)) "
            + "paper=\(NSStringFromRect(paperController.view.frame)) "
            + "firstResponder="
            + String(
                describing: view.window?.firstResponder.map {
                    type(of: $0)
                }
            )
    }
#endif

    private func layout() {
        guard root.bounds.width.isFinite,
              root.bounds.height.isFinite,
              root.bounds.width > 48,
              root.bounds.height > 48
        else {
            toolbarController.view.frame = .zero
            paperController.view.frame = .zero
            penOverlay.frame = .zero
            return
        }
        let fittingSize = toolbarController.view.fittingSize
        let fittingHeight = fittingSize.height.isFinite
            ? fittingSize.height
            : 36
        let fittingWidth = fittingSize.width.isFinite
            ? fittingSize.width
            : 280
        let toolbarHeight = max(
            36,
            fittingHeight
        )
        let availableWidth = max(1, root.bounds.width - 24)
        let toolbarWidth = min(
            availableWidth,
            max(280, fittingWidth)
        )
        toolbarController.view.frame = NSRect(
            x: round(root.bounds.midX - toolbarWidth / 2),
            y: 6,
            width: toolbarWidth,
            height: toolbarHeight
        )
        let paperRect = LabPaperLayout.drawingRect(
            in: root.bounds,
            topReservedHeight:
                LabPaperLayout.paperKitToolbarBandHeight
        )
        paperController.view.frame = paperRect
        penOverlay.frame = paperRect
        paperController.contentVisibleFrame = modelBounds
    }

    private func activeInkingTool() -> PKInkingTool {
        paperController.drawingTool as? PKInkingTool
            ?? PKInkingTool(.pen, color: .black, width: 4)
    }

    private func commitStroke(_ strokeID: UInt64) {
        guard let points = penStrokes[strokeID], !points.isEmpty else {
            return
        }
        let tool = activeInkingTool()
        let strokes = splitContinuousPaths(points).compactMap {
            points -> PKStroke? in
            guard !points.isEmpty else {
                return nil
            }
            let startedAt = Date()
            let controlPoints = points.enumerated().map {
                index, point in
                let pressure = point.render.pressure ?? 0.5
                return PKStrokePoint(
                    location: CGPoint(
                        x: point.normalized.x * modelBounds.width,
                        y: point.normalized.y * modelBounds.height
                    ),
                    timeOffset: Double(index) / 60,
                    size: CGSize(
                        width: tool.width,
                        height: tool.width
                    ),
                    opacity: 1,
                    force: pressure,
                    azimuth: 0,
                    altitude: .pi / 2
                )
            }
            let path = PKStrokePath(
                controlPoints: controlPoints,
                creationDate: startedAt
            )
            return PKStroke(ink: tool.ink, path: path)
        }
        guard !strokes.isEmpty else {
            return
        }
        var markup = paperController.markup
            ?? PaperMarkup(bounds: modelBounds)
        markup.append(contentsOf: PKDrawing(strokes: strokes))
        paperController.markup = markup
        committedPenStrokeCount += strokes.count
    }

    private func splitContinuousPaths(
        _ points: [LabRenderPoint]
    ) -> [[LabRenderPoint]] {
        var paths: [[LabRenderPoint]] = []
        for point in points {
            if paths.isEmpty || !point.render.connectsToPrevious {
                paths.append([point])
            } else {
                paths[paths.count - 1].append(point)
            }
        }
        return paths
    }
}

@available(macOS 26.0, *)
private final class PaperKitRendererRootView: NSView {
    weak var paperView: NSView?
    weak var toolbarView: NSView?
    weak var penOverlay: NSView?
    var layoutHandler: (() -> Void)?

    override var isFlipped: Bool { true }

    override func layout() {
        super.layout()
        layoutHandler?()
    }
}

@available(macOS 26.0, *)
private final class PaperKitBackgroundView: NSView {
    override var isFlipped: Bool { true }

    override func hitTest(_ point: NSPoint) -> NSView? {
        nil
    }

    override func draw(_ dirtyRect: NSRect) {
        NSColor(calibratedWhite: 0.985, alpha: 1).setFill()
        bounds.fill()
        NSColor(calibratedWhite: 0.78, alpha: 1).setStroke()
        NSBezierPath(rect: bounds).stroke()
    }
}

@available(macOS 26.0, *)
private final class PaperKitInjectedPenView: NSView {
    var onSamplesRendered: (([RawPenSample], UInt64) -> Void)?

    private var strokes: [UInt64: [LabRenderPoint]] = [:]
    private var predicted: [UInt64: [LabRenderPoint]] = [:]
    private var tool = PKInkingTool(.pen, color: .black, width: 4)
    private var pendingSamples: [RawPenSample] = []

    override var isFlipped: Bool { true }

    override func hitTest(_ point: NSPoint) -> NSView? {
        nil
    }

    func apply(
        _ update: LabRendererUpdate,
        tool: PKInkingTool
    ) {
        if let replacement = update.replacement {
            strokes[update.strokeID] = replacement
        } else if !update.committed.isEmpty {
            strokes[update.strokeID, default: []].append(
                contentsOf: update.committed
            )
        }
        predicted[update.strokeID] = update.predicted
        self.tool = tool
        pendingSamples.append(contentsOf: update.sourceSamples)
        needsDisplay = true
    }

    func finishStroke(_ strokeID: UInt64) {
        strokes.removeValue(forKey: strokeID)
        predicted.removeValue(forKey: strokeID)
        needsDisplay = true
    }

    func clear() {
        strokes.removeAll(keepingCapacity: true)
        predicted.removeAll(keepingCapacity: true)
        pendingSamples.removeAll(keepingCapacity: true)
        needsDisplay = true
    }

    override func draw(_ dirtyRect: NSRect) {
        NSGraphicsContext.current?.cgContext.clear(bounds)
        tool.color.setStroke()
        for (strokeID, points) in strokes {
            draw(points)
            if let predicted = predicted[strokeID], !predicted.isEmpty {
                NSColor.systemPurple.setStroke()
                draw(predicted, initialPoint: points.last)
                tool.color.setStroke()
            }
        }
        guard !pendingSamples.isEmpty else {
            return
        }
        let rendered = pendingSamples
        pendingSamples.removeAll(keepingCapacity: true)
        onSamplesRendered?(
            rendered,
            DispatchTime.now().uptimeNanoseconds
        )
    }

    private func draw(
        _ points: [LabRenderPoint],
        initialPoint: LabRenderPoint? = nil
    ) {
        var previous = initialPoint
        for point in points {
            let location = NSPoint(
                x: point.normalized.x * bounds.width,
                y: point.normalized.y * bounds.height
            )
            if let previous, point.render.connectsToPrevious {
                let previousLocation = NSPoint(
                    x: previous.normalized.x * bounds.width,
                    y: previous.normalized.y * bounds.height
                )
                let path = NSBezierPath()
                path.move(to: previousLocation)
                path.line(to: location)
                path.lineCapStyle = .round
                path.lineJoinStyle = .round
                path.lineWidth = max(
                    1,
                    tool.width * CGFloat(
                        point.render.pressure ?? 0.5
                    )
                )
                path.stroke()
            }
            previous = point
        }
    }
}
#endif
