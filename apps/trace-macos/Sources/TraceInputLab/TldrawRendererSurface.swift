import AppKit
import NeoInput
import TraceCalibration
import TraceGeometry
import WebKit

final class TldrawRendererSurface:
    NSObject,
    LabRendererSurface,
    WKNavigationDelegate,
    WKScriptMessageHandler
{
    private enum BridgeUpdateKind {
        case pen
        case mousePrediction
    }

    private struct QueuedRendererUpdate {
        let kind: BridgeUpdateKind
        let strokeID: UInt64
        var committed: [LabRenderPoint]
        var predicted: [LabRenderPoint]
        var replacement: [LabRenderPoint]?
        var sourceSamples: [RawPenSample]
        var isFinal: Bool

        init(
            _ update: LabRendererUpdate,
            kind: BridgeUpdateKind
        ) {
            self.kind = kind
            strokeID = update.strokeID
            committed = kind == .mousePrediction
                ? update.committed.last.map { [$0] } ?? []
                : update.committed
            predicted = update.predicted
            replacement = update.replacement
            sourceSamples = update.sourceSamples
            isFinal = update.isFinal
        }

        mutating func merge(_ update: LabRendererUpdate) -> Bool {
            guard strokeID == update.strokeID,
                  kind == (
                      update.strokeID >= LabMouseIdentifier.base
                          ? .mousePrediction
                          : .pen
                  ),
                  !isFinal,
                  replacement == nil
            else {
                return false
            }
            if kind == .mousePrediction {
                if let anchor = update.committed.last {
                    committed = [anchor]
                }
            } else if let nextReplacement = update.replacement {
                committed.removeAll(keepingCapacity: false)
                replacement = nextReplacement
            } else {
                committed.append(contentsOf: update.committed)
            }
            predicted = update.predicted
            sourceSamples.append(contentsOf: update.sourceSamples)
            isFinal = update.isFinal
            return true
        }
    }

    let view: NSView
    let childViewControllers: [NSViewController] = []
    var onSamplesRendered: (([RawPenSample], UInt64) -> Void)?
    var onMouseStrokeEvent: ((LabMouseStrokeEvent) -> Void)?
    private(set) var unavailableReason: String?

    private let root = TldrawRendererRootView()
    private let webView: WKWebView
    private let messageHandler: WeakScriptMessageHandler
    private let resourceSchemeHandler: TldrawResourceSchemeHandler
    private let resourceDirectory: URL?
    private let statusLabel = NSTextField(
        wrappingLabelWithString: "Loading tldraw…"
    )
    private var isReady = false
    private var queuedUpdates: [QueuedRendererUpdate] = []
    private var pendingSamples: [UInt64: RawPenSample] = [:]
    private var clearPending = false
    private var bridgeOperationScheduled = false
    private var pendingEvaluationCount = 0
    private var navigationState = "loading"
    var isReadyForInput: Bool { isReady }
    var pendingRenderWorkCount: Int {
        queuedUpdates.count
            + pendingSamples.count
            + pendingEvaluationCount
            + (clearPending ? 1 : 0)
            + (bridgeOperationScheduled ? 1 : 0)
    }
#if DEBUG
    var onReadyForTesting: (() -> Void)?
    private(set) var renderedSampleCountForTesting = 0
    private(set) var runtimeErrorCountForTesting = 0
    private(set) var lastRuntimeErrorForTesting: String?
    private(set) var penEvaluationCountForTesting = 0
    private(set) var maximumConcurrentEvaluationCountForTesting = 0
    var queuedUpdateCountForTesting: Int { queuedUpdates.count }
    var bridgeEvaluationInFlightForTesting: Bool {
        pendingEvaluationCount > 0 || bridgeOperationScheduled
    }
    var pendingSampleCountForTesting: Int { pendingSamples.count }
    private(set) var lastBridgeOperationForTesting = "none"

    func insertPendingSampleForTesting(_ sample: RawPenSample) {
        pendingSamples[sample.id] = sample
    }
    var isReadyForTesting: Bool { isReady }
    var drawingFrameForTesting: NSRect { webView.frame }
    var debugStateForTesting: String {
        [
            navigationState,
            "url=\(webView.url?.absoluteString ?? "nil")",
            "ready=\(isReady)",
            "error=\(unavailableReason ?? "nil")",
        ].joined(separator: " ")
    }

    func shapeCountForTesting() async -> Int? {
        do {
            let result = try await webView.callAsyncJavaScript(
                "return window.traceRenderer.getShapeCount()",
                arguments: [:],
                in: nil,
                contentWorld: .page
            )
            return (result as? NSNumber)?.intValue
                ?? result as? Int
        } catch {
            return nil
        }
    }

    func shapeSummaryForTesting() async -> String {
        do {
            let result = try await webView.callAsyncJavaScript(
                """
                return JSON.stringify(
                  window.traceRenderer.getShapeSummaryForTesting()
                )
                """,
                arguments: [:],
                in: nil,
                contentWorld: .page
            )
            return result as? String ?? "no shape summary"
        } catch {
            return "shape summary failed: \(error.localizedDescription)"
        }
    }

    func mousePredictionShapeCountForTesting() async -> Int? {
        do {
            let result = try await webView.callAsyncJavaScript(
                """
                return window.traceRenderer
                  .getMousePredictionShapeCountForTesting()
                """,
                arguments: [:],
                in: nil,
                contentWorld: .page
            )
            return (result as? NSNumber)?.intValue
                ?? result as? Int
        } catch {
            return nil
        }
    }

    func emitMouseEventForTesting(
        phase: String,
        x: Double,
        y: Double
    ) async -> Bool {
        do {
            _ = try await webView.callAsyncJavaScript(
                """
                window.traceRenderer
                  .emitMouseEventForTesting(phase, x, y)
                """,
                arguments: [
                    "phase": phase,
                    "x": x,
                    "y": y,
                ],
                in: nil,
                contentWorld: .page
            )
            return true
        } catch {
            return false
        }
    }

    func emitRenderedSampleForTesting(
        sampleID: UInt64
    ) async -> Bool {
        do {
            _ = try await webView.callAsyncJavaScript(
                """
                window.traceRenderer
                  .emitRenderedSampleForTesting(sampleId)
                """,
                arguments: [
                    "sampleId": String(sampleID),
                ],
                in: nil,
                contentWorld: .page
            )
            return true
        } catch {
            return false
        }
    }

    func bridgeDrawingSizeForTesting() async -> NSSize? {
        do {
            let result = try await webView.callAsyncJavaScript(
                "return window.traceRenderer.getDrawingSize()",
                arguments: [:],
                in: nil,
                contentWorld: .page
            )
            guard let values = result as? [String: Any],
                  let width = values["width"] as? NSNumber,
                  let height = values["height"] as? NSNumber
            else {
                return nil
            }
            return NSSize(
                width: width.doubleValue,
                height: height.doubleValue
            )
        } catch {
            return nil
        }
    }

    func iconDiagnosticsForTesting() async -> String {
        do {
            let result = try await webView.callAsyncJavaScript(
                """
                const icon = document.querySelector('.tlui-icon')
                if (!icon) return 'no .tlui-icon'
                const style = getComputedStyle(icon)
                const after = getComputedStyle(icon, '::after')
                return JSON.stringify({
                  html: icon.outerHTML,
                  background: style.background,
                  backgroundImage: style.backgroundImage,
                  mask: style.mask,
                  maskImage: style.maskImage,
                  webkitMask: style.webkitMask,
                  webkitMaskImage: style.webkitMaskImage,
                  afterContent: after.content,
                  afterBackground: after.background,
                  afterMask: after.mask,
                  iconUrl: style.getPropertyValue('--tlui-icon')
                })
                """,
                arguments: [:],
                in: nil,
                contentWorld: .page
            )
            return result as? String ?? "no icon diagnostics"
        } catch {
            return "icon diagnostics failed: \(error.localizedDescription)"
        }
    }

    func iconsRenderForTesting() async -> Bool {
        do {
            let result = try await webView.callAsyncJavaScript(
                """
                const icon = document.querySelector('.tlui-icon')
                if (!icon) return false
                const style = getComputedStyle(icon)
                return style.maskImage !== 'none'
                  || style.webkitMaskImage !== 'none'
                """,
                arguments: [:],
                in: nil,
                contentWorld: .page
            )
            return (result as? NSNumber)?.boolValue
                ?? result as? Bool
                ?? false
        } catch {
            return false
        }
    }

    func lockAllShapesForTesting() async -> Bool {
        do {
            _ = try await webView.callAsyncJavaScript(
                "window.traceRenderer.lockAllShapesForTesting()",
                arguments: [:],
                in: nil,
                contentWorld: .page
            )
            return true
        } catch {
            return false
        }
    }

    func setCameraForTesting(
        x: Double,
        y: Double,
        zoom: Double
    ) async -> Bool {
        do {
            _ = try await webView.callAsyncJavaScript(
                """
                return window.traceRenderer
                  .setCameraForTesting(camera)
                """,
                arguments: [
                    "camera": ["x": x, "y": y, "z": zoom],
                ],
                in: nil,
                contentWorld: .page
            )
            return true
        } catch {
            return false
        }
    }

    func shapeViewportOriginForTesting(
        strokeID: UInt64
    ) async -> NSPoint? {
        do {
            let result = try await webView.callAsyncJavaScript(
                """
                return window.traceRenderer
                  .getShapeViewportOriginForTesting(strokeId)
                """,
                arguments: [
                    "strokeId": String(strokeID),
                ],
                in: nil,
                contentWorld: .page
            )
            guard let values = result as? [String: Any],
                  let x = values["x"] as? NSNumber,
                  let y = values["y"] as? NSNumber
            else {
                return nil
            }
            return NSPoint(x: x.doubleValue, y: y.doubleValue)
        } catch {
            return nil
        }
    }

    func mousePredictionViewportOriginForTesting(
        strokeID: UInt64
    ) async -> NSPoint? {
        do {
            let result = try await webView.callAsyncJavaScript(
                """
                return window.traceRenderer
                  .getMousePredictionViewportOriginForTesting(strokeId)
                """,
                arguments: [
                    "strokeId": String(strokeID),
                ],
                in: nil,
                contentWorld: .page
            )
            guard let values = result as? [String: Any],
                  let x = values["x"] as? NSNumber,
                  let y = values["y"] as? NSNumber
            else {
                return nil
            }
            return NSPoint(x: x.doubleValue, y: y.doubleValue)
        } catch {
            return nil
        }
    }
#endif

    override convenience init() {
        self.init(
            resourceDirectory: Bundle.main.resourceURL?
            .appendingPathComponent(
                "WebCanvas",
                isDirectory: true
            )
        )
    }

    init(resourceDirectory: URL?) {
        self.resourceDirectory = resourceDirectory
        let configuration = WKWebViewConfiguration()
        configuration.preferences.isElementFullscreenEnabled = false
        let resourceSchemeHandler = TldrawResourceSchemeHandler(
            resourceDirectory: resourceDirectory
        )
        configuration.setURLSchemeHandler(
            resourceSchemeHandler,
            forURLScheme: TldrawResourceSchemeHandler.scheme
        )
        let messageHandler = WeakScriptMessageHandler()
        configuration.userContentController.add(
            messageHandler,
            name: "traceRenderer"
        )
        configuration.userContentController.addUserScript(
            WKUserScript(
                source: """
                window.addEventListener('error', event => {
                  const target = event.target
                  window.webkit?.messageHandlers?.traceRenderer?.postMessage({
                    type: 'error',
                    message: [
                      event.message,
                      event.filename,
                      target?.src,
                      target?.href,
                      target?.tagName,
                      event.lineno,
                      event.colno,
                      event.error?.stack
                    ].filter(Boolean).join(' · ') || 'window error'
                  })
                }, true)
                window.addEventListener('unhandledrejection', event => {
                  window.webkit?.messageHandlers?.traceRenderer?.postMessage({
                    type: 'error',
                    message: String(
                      event.reason?.stack
                        ?? event.reason?.message
                        ?? JSON.stringify(event.reason)
                        ?? 'unhandled rejection'
                    )
                  })
                })
                """,
                injectionTime: .atDocumentStart,
                forMainFrameOnly: true
            )
        )
        webView = WKWebView(
            frame: .zero,
            configuration: configuration
        )
        self.messageHandler = messageHandler
        self.resourceSchemeHandler = resourceSchemeHandler
        view = root
        super.init()

        messageHandler.target = self
        webView.navigationDelegate = self
        webView.setValue(false, forKey: "drawsBackground")

        statusLabel.alignment = .center
        statusLabel.textColor = .secondaryLabelColor
        statusLabel.translatesAutoresizingMaskIntoConstraints = false

        root.webView = webView
        root.layoutHandler = { [weak self] in
            self?.layout()
        }
        root.addSubview(webView)
        root.addSubview(statusLabel)
        NSLayoutConstraint.activate([
            statusLabel.centerXAnchor.constraint(
                equalTo: root.centerXAnchor
            ),
            statusLabel.centerYAnchor.constraint(
                equalTo: root.centerYAnchor
            ),
            statusLabel.widthAnchor.constraint(
                lessThanOrEqualToConstant: 460
            ),
        ])

        loadBundle()
    }

    deinit {
        webView.configuration.userContentController
            .removeScriptMessageHandler(forName: "traceRenderer")
    }

    func updatePresentation(_ presentation: LabRendererPresentation) {
        root.needsLayout = true
    }

    func apply(_ update: LabRendererUpdate) {
        for sample in update.sourceSamples {
            pendingSamples[sample.id] = sample
        }
        let kind: BridgeUpdateKind =
            update.strokeID >= LabMouseIdentifier.base
                ? .mousePrediction
                : .pen
        enqueue(update, kind: kind)
        scheduleBridgeOperation()
    }

    func clear() {
        pendingSamples.removeAll(keepingCapacity: true)
        queuedUpdates.removeAll(keepingCapacity: true)
        clearPending = true
        scheduleBridgeOperation()
    }

    func activate() {
        view.isHidden = false
    }

    func deactivate() {
        view.isHidden = true
    }

    func userContentController(
        _ userContentController: WKUserContentController,
        didReceive message: WKScriptMessage
    ) {
        guard message.name == "traceRenderer",
              let body = message.body as? [String: Any],
              let type = body["type"] as? String
        else {
            return
        }
        switch type {
        case "ready":
            isReady = true
            statusLabel.isHidden = true
#if DEBUG
            onReadyForTesting?()
#endif
            scheduleBridgeOperation()
        case "rendered":
            let ids = (body["sampleIds"] as? [String] ?? [])
                .compactMap(UInt64.init)
            let samples = ids.compactMap {
                pendingSamples.removeValue(forKey: $0)
            }
            if !samples.isEmpty {
#if DEBUG
                renderedSampleCountForTesting += samples.count
#endif
                onSamplesRendered?(
                    samples,
                    DispatchTime.now().uptimeNanoseconds
                )
            }
        case "mouse":
            handleMouseMessage(body)
        case "error":
            let detail = body["message"] as? String
                ?? "Unknown tldraw renderer error"
#if DEBUG
            runtimeErrorCountForTesting += 1
            lastRuntimeErrorForTesting = detail
#endif
            NSLog("Trace Input Lab tldraw error: %@", detail)
        default:
            break
        }
    }

    func webView(
        _ webView: WKWebView,
        didFail navigation: WKNavigation!,
        withError error: Error
    ) {
        showLoadError(error.localizedDescription)
    }

    func webView(
        _ webView: WKWebView,
        didFinish navigation: WKNavigation!
    ) {
        navigationState = "finished"
    }

    func webViewWebContentProcessDidTerminate(_ webView: WKWebView) {
        navigationState = "terminated"
        showLoadError("The tldraw WebContent process terminated.")
    }

    func webView(
        _ webView: WKWebView,
        didFailProvisionalNavigation navigation: WKNavigation!,
        withError error: Error
    ) {
        showLoadError(error.localizedDescription)
    }

    private func loadBundle() {
        guard let resourceDirectory else {
            showLoadError("The app bundle has no Resources directory.")
            return
        }
        let index = resourceDirectory.appendingPathComponent("index.html")
        let iconSprite = resourceDirectory
            .appendingPathComponent("icon-sprite.svg")
        guard FileManager.default.fileExists(atPath: index.path),
              FileManager.default.fileExists(atPath: iconSprite.path)
        else {
            showLoadError(
                "Run tools/trace-input-lab to build and bundle tldraw."
            )
            return
        }
        webView.load(
            URLRequest(
                url: TldrawResourceSchemeHandler.indexURL
            )
        )
    }

    private func showLoadError(_ detail: String) {
        navigationState = "failed"
        unavailableReason = detail
        statusLabel.stringValue = "tldraw is unavailable.\n\(detail)"
        statusLabel.isHidden = false
        webView.isHidden = true
    }

    private func layout() {
        guard root.bounds.width.isFinite,
              root.bounds.height.isFinite,
              root.bounds.width > 48,
              root.bounds.height > 48
        else {
            webView.frame = .zero
            return
        }
        let paperRect = LabPaperLayout.drawingRect(in: root.bounds)
        webView.frame = paperRect
    }

    private func payload(
        for update: QueuedRendererUpdate
    ) -> [String: Any] {
        [
            "strokeId": String(update.strokeID),
            "committed": update.committed.map(pointPayload),
            "predicted": update.predicted.map(pointPayload),
            "replacement": update.replacement.map {
                $0.map(pointPayload)
            } ?? NSNull(),
            "isFinal": update.isFinal,
            "sampleIds": update.sourceSamples.map {
                String($0.id)
            },
        ]
    }

    private func mousePredictionPayload(
        for update: QueuedRendererUpdate
    ) -> [String: Any] {
        [
            "strokeId": String(update.strokeID),
            "anchor": update.committed.last.map(pointPayload)
                ?? NSNull(),
            "predicted": update.predicted.map(pointPayload),
            "isFinal": update.isFinal,
            "sampleIds": update.sourceSamples.map {
                String($0.id)
            },
        ]
    }

    private func pointPayload(_ point: LabRenderPoint) -> [String: Any] {
        [
            "x": point.normalized.x,
            "y": point.normalized.y,
            "pressure": point.render.pressure
                .map { NSNumber(value: $0) }
                ?? NSNull(),
            "connectsToPrevious": point.render.connectsToPrevious,
        ]
    }

    private func enqueue(
        _ update: LabRendererUpdate,
        kind: BridgeUpdateKind
    ) {
        if !queuedUpdates.isEmpty,
           queuedUpdates[queuedUpdates.count - 1].merge(update)
        {
            return
        }
        queuedUpdates.append(
            QueuedRendererUpdate(update, kind: kind)
        )
    }

    private func handleMouseMessage(_ body: [String: Any]) {
        guard let phase = body["phase"] as? String,
              let x = (body["x"] as? NSNumber)?.doubleValue,
              let y = (body["y"] as? NSNumber)?.doubleValue
        else {
            return
        }
        let reportedPressure =
            (body["pressure"] as? NSNumber)?.doubleValue
        let pressure = reportedPressure.flatMap {
            $0 > 0 && $0 < 1 ? $0 : nil
        }
        let sample = LabMouseSample(
            point: UnitPoint(
                x: min(1, max(0, x)),
                y: min(1, max(0, y))
            ),
            pressure: pressure,
            wallClockMilliseconds: UInt64(
                Date().timeIntervalSince1970 * 1_000
            ),
            uptimeNanoseconds:
                DispatchTime.now().uptimeNanoseconds
        )
        switch phase {
        case "began":
            onMouseStrokeEvent?(.began(sample))
        case "moved":
            onMouseStrokeEvent?(.moved(sample))
        case "ended":
            onMouseStrokeEvent?(.ended(sample))
        default:
            break
        }
    }

    private func scheduleBridgeOperation() {
        guard isReady,
              unavailableReason == nil,
              pendingEvaluationCount == 0,
              !bridgeOperationScheduled,
              clearPending || !queuedUpdates.isEmpty
        else {
            return
        }
        bridgeOperationScheduled = true
        DispatchQueue.main.async { [weak self] in
            guard let self else {
                return
            }
            bridgeOperationScheduled = false
            performNextBridgeOperation()
        }
    }

    private func performNextBridgeOperation() {
        guard isReady,
              unavailableReason == nil,
              pendingEvaluationCount == 0
        else {
            return
        }
        let script: String
        let arguments: [String: Any]
        if clearPending {
            clearPending = false
            script = "window.traceRenderer.clear()"
            arguments = [:]
        } else if !queuedUpdates.isEmpty {
            let update = queuedUpdates.removeFirst()
#if DEBUG
            penEvaluationCountForTesting += 1
#endif
            switch update.kind {
            case .pen:
#if DEBUG
                lastBridgeOperationForTesting =
                    "pen stroke=\(update.strokeID) "
                    + "committed=\(update.committed.count) "
                    + "predicted=\(update.predicted.count) "
                    + "final=\(update.isFinal)"
#endif
                script = "window.traceRenderer.applyPenUpdate(payload)"
                arguments = ["payload": payload(for: update)]
            case .mousePrediction:
#if DEBUG
                lastBridgeOperationForTesting =
                    "mouse stroke=\(update.strokeID) "
                    + "anchor=\(!update.committed.isEmpty) "
                    + "predicted=\(update.predicted.count) "
                    + "final=\(update.isFinal)"
#endif
                script =
                    "window.traceRenderer.applyMousePrediction(payload)"
                arguments = [
                    "payload": mousePredictionPayload(for: update),
                ]
            }
        } else {
            return
        }

        pendingEvaluationCount += 1
#if DEBUG
        maximumConcurrentEvaluationCountForTesting = max(
            maximumConcurrentEvaluationCountForTesting,
            pendingEvaluationCount
        )
#endif
        Task { @MainActor [weak self] in
            guard let self else {
                return
            }
            defer {
                pendingEvaluationCount -= 1
                scheduleBridgeOperation()
            }
            do {
                _ = try await webView.callAsyncJavaScript(
                    script,
                    arguments: arguments,
                    in: nil,
                    contentWorld: .page
                )
            } catch {
                showLoadError(error.localizedDescription)
            }
        }
    }
}

private final class TldrawResourceSchemeHandler:
    NSObject,
    WKURLSchemeHandler
{
    static let scheme = "trace-renderer"
    static let indexURL = URL(
        string: "\(scheme)://app/index.html"
    )!

    private let resourceDirectory: URL?

    init(resourceDirectory: URL?) {
        self.resourceDirectory = resourceDirectory
    }

    func webView(
        _ webView: WKWebView,
        start urlSchemeTask: WKURLSchemeTask
    ) {
        guard let requestURL = urlSchemeTask.request.url,
              let resourceDirectory,
              let resource = resource(for: requestURL)
        else {
            urlSchemeTask.didFailWithError(
                CocoaError(.fileNoSuchFile)
            )
            return
        }
        let fileURL = resourceDirectory.appendingPathComponent(resource.name)
        do {
            let data = try Data(contentsOf: fileURL)
            let response = URLResponse(
                url: requestURL,
                mimeType: resource.mimeType,
                expectedContentLength: data.count,
                textEncodingName: resource.textEncoding
            )
            urlSchemeTask.didReceive(response)
            urlSchemeTask.didReceive(data)
            urlSchemeTask.didFinish()
        } catch {
            urlSchemeTask.didFailWithError(error)
        }
    }

    func webView(
        _ webView: WKWebView,
        stop urlSchemeTask: WKURLSchemeTask
    ) {}

    private func resource(
        for url: URL
    ) -> (
        name: String,
        mimeType: String,
        textEncoding: String?
    )? {
        guard url.host == "app" else {
            return nil
        }
        switch url.path {
        case "/index.html":
            return ("index.html", "text/html", "utf-8")
        case "/icon-sprite.svg":
            return ("icon-sprite.svg", "image/svg+xml", "utf-8")
        default:
            return nil
        }
    }
}

private final class TldrawRendererRootView: NSView {
    weak var webView: NSView?
    var layoutHandler: (() -> Void)?

    override var isFlipped: Bool { true }

    override func layout() {
        super.layout()
        layoutHandler?()
    }
}

private final class WeakScriptMessageHandler: NSObject,
    WKScriptMessageHandler
{
    weak var target: WKScriptMessageHandler?

    func userContentController(
        _ userContentController: WKUserContentController,
        didReceive message: WKScriptMessage
    ) {
        target?.userContentController(
            userContentController,
            didReceive: message
        )
    }
}
