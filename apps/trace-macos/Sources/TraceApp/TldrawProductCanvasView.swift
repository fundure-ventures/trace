import AppKit
import TraceAppCore
import WebKit

final class TldrawProductCanvasView:
    NSView,
    WKNavigationDelegate,
    WKScriptMessageHandler
{
    var onDocumentReady: (() -> Void)?
    var onUnavailable: (() -> Void)?
    var onSnapshotChange: ((
        String,
        [TraceTimedCanvasShape]
    ) -> Void)?
    var onHistoryChange: ((Bool, Bool) -> Void)?
    var onUserEdit: ((Int) -> Void)?
    var onToolChange: ((TraceCanvasTool) -> Void)?
    var onTemporaryToolChange: ((TraceCanvasTool?) -> Void)?
    private(set) var unavailableReason: String?
    private(set) var canUndo = false
    private(set) var canRedo = false

    private struct QueuedUpdate {
        let strokeID: UInt64
        let style: TraceToolState
        var committed: [TraceDrawingPoint]
        var predicted: [TraceDrawingPoint]
        var isFinal: Bool

        init(_ update: TraceAnnotationUpdate) {
            strokeID = update.strokeID
            style = update.style
            committed = update.committed
            predicted = update.predicted
            isFinal = update.isFinal
        }

        mutating func merge(_ update: TraceAnnotationUpdate) -> Bool {
            guard strokeID == update.strokeID, !isFinal else {
                return false
            }
            committed.append(contentsOf: update.committed)
            predicted = update.predicted
            isFinal = update.isFinal
            return true
        }
    }

    private struct PendingStrokeSync {
        let strokes: [[String: Any]]
        let shapeAnnotations: [[String: Any]]
    }

    private let webView: WKWebView
    private let errorLabel = NSTextField(wrappingLabelWithString: "")
    private let messageHandler: ProductWeakScriptMessageHandler
    private let schemeHandler: ProductRendererSchemeHandler
    private var isReady = false
    private var pendingDocument: [String: Any]?
    private var pendingTool: [String: Any]?
    private var pendingBackground: String?
    private var pendingStrokeSync: PendingStrokeSync?
    private var pendingImageBatches: [[[String: Any]]] = []
    private var queuedUpdates: [QueuedUpdate] = []
    private var pendingHistoryCommands: [String] = []
    private var evaluationInFlight = false
    private var operationScheduled = false
    private var pageSize = NSSize(width: 1, height: 1)
    private var viewport = TracePageViewport.full
    private var currentDocumentID: UUID?
    private var documentGeneration = 0
    private var appliedDocumentGeneration: Int?
    private var pendingDocumentFrameGeneration: Int?
    private var annotationScale: TraceTranscriptAnnotationScale = .medium

    override init(frame frameRect: NSRect) {
        let resourceDirectory = Bundle.main.resourceURL?
            .appendingPathComponent(
                "WebCanvas",
                isDirectory: true
            )
        let configuration = WKWebViewConfiguration()
        configuration.preferences.isElementFullscreenEnabled = false
        let schemeHandler = ProductRendererSchemeHandler(
            resourceDirectory: resourceDirectory
        )
        configuration.setURLSchemeHandler(
            schemeHandler,
            forURLScheme: ProductRendererSchemeHandler.scheme
        )
        let messageHandler = ProductWeakScriptMessageHandler()
        configuration.userContentController.add(
            messageHandler,
            name: "traceRenderer"
        )
#if DEBUG
        if ProcessInfo.processInfo.environment[
            "TRACE_SIDECAR_INPUT_PROBE"
        ] == "1" {
            configuration.userContentController.addUserScript(
                WKUserScript(
                    source: """
                    (() => {
                      const report = (event) => {
                        window.webkit.messageHandlers.traceRenderer.postMessage({
                          type: 'sidecar-input-probe',
                          eventType: event.type,
                          pointerType: event.pointerType,
                          pointerId: event.pointerId,
                          isPrimary: event.isPrimary,
                          pressure: event.pressure,
                          tangentialPressure: event.tangentialPressure,
                          tiltX: event.tiltX,
                          tiltY: event.tiltY,
                          twist: event.twist,
                          width: event.width,
                          height: event.height,
                          buttons: event.buttons,
                          button: event.button,
                          clientX: event.clientX,
                          clientY: event.clientY,
                        })
                      }
                      for (const type of [
                        'pointerover',
                        'pointerenter',
                        'pointerdown',
                        'pointermove',
                        'pointerup',
                        'pointercancel',
                        'pointerout',
                        'pointerleave',
                      ]) {
                        window.addEventListener(type, report, true)
                      }
                    })()
                    """,
                    injectionTime: .atDocumentStart,
                    forMainFrameOnly: true
                )
            )
        }
#endif
        webView = WKWebView(
            frame: frameRect,
            configuration: configuration
        )
        self.messageHandler = messageHandler
        self.schemeHandler = schemeHandler
        super.init(frame: frameRect)

        wantsLayer = true
        messageHandler.target = self
        webView.navigationDelegate = self
        webView.setValue(false, forKey: "drawsBackground")
        webView.translatesAutoresizingMaskIntoConstraints = false
        addSubview(webView)
        errorLabel.translatesAutoresizingMaskIntoConstraints = false
        errorLabel.alignment = .center
        errorLabel.font = .systemFont(ofSize: 13, weight: .medium)
        errorLabel.textColor = .secondaryLabelColor
        errorLabel.maximumNumberOfLines = 4
        errorLabel.isHidden = true
        addSubview(errorLabel)
        NSLayoutConstraint.activate([
            webView.topAnchor.constraint(equalTo: topAnchor),
            webView.leadingAnchor.constraint(equalTo: leadingAnchor),
            webView.trailingAnchor.constraint(equalTo: trailingAnchor),
            webView.bottomAnchor.constraint(equalTo: bottomAnchor),
            errorLabel.centerXAnchor.constraint(equalTo: centerXAnchor),
            errorLabel.centerYAnchor.constraint(equalTo: centerYAnchor),
            errorLabel.leadingAnchor.constraint(
                greaterThanOrEqualTo: leadingAnchor,
                constant: 24
            ),
            errorLabel.trailingAnchor.constraint(
                lessThanOrEqualTo: trailingAnchor,
                constant: -24
            ),
        ])
        loadBundle(from: resourceDirectory)
    }

    required init?(coder: NSCoder) {
        nil
    }

#if DEBUG
    var isReadyForTesting: Bool {
        isReady
    }

    func stateForTesting() async -> [String: Any]? {
        do {
            return try await webView.callAsyncJavaScript(
                "return window.traceProductRenderer.getStateForTesting()",
                arguments: [:],
                in: nil,
                contentWorld: .page
            ) as? [String: Any]
        } catch {
            return nil
        }
    }

    func snapshotForTesting() async -> String? {
        do {
            return try await webView.callAsyncJavaScript(
                "return window.traceProductRenderer.getSnapshotJson()",
                arguments: [:],
                in: nil,
                contentWorld: .page
            ) as? String
        } catch {
            return nil
        }
    }

    func exportImageForTesting(
        pixelRatio: CGFloat
    ) async -> NSImage? {
        await withCheckedContinuation { continuation in
            exportImage(pixelRatio: pixelRatio) {
                continuation.resume(returning: $0)
            }
        }
    }

    func setFirstUserImagePositionForTesting(
        x: CGFloat,
        y: CGFloat
    ) async -> Bool {
        do {
            return try await webView.callAsyncJavaScript(
                """
                return window.traceProductRenderer
                  .setFirstUserImagePositionForTesting(x, y)
                """,
                arguments: [
                    "x": x,
                    "y": y,
                ],
                in: nil,
                contentWorld: .page
            ) as? Bool ?? false
        } catch {
            return false
        }
    }

    func setExportFixtureForTesting(_ fixture: String) async -> Bool {
        do {
            _ = try await webView.callAsyncJavaScript(
                """
                window.traceProductRenderer
                  .setExportFixtureForTesting(fixture)
                """,
                arguments: ["fixture": fixture],
                in: nil,
                contentWorld: .page
            )
            return true
        } catch {
            return false
        }
    }

    func dropImageForTesting(
        _ image: NSImage,
        delayMilliseconds: Int
    ) async -> Bool {
        guard let dataURL = imageDataURL(image) else {
            return false
        }
        do {
            return try await webView.callAsyncJavaScript(
                """
                const response = await fetch(dataUrl)
                const blob = await response.blob()
                const file = new File(
                  [blob],
                  'delayed-drop.png',
                  { type: 'image/png' }
                )
                const transfer = new DataTransfer()
                transfer.items.add(file)
                const original = window.createImageBitmap
                window.createImageBitmap = async (...args) => {
                  await new Promise((resolve) =>
                    window.setTimeout(resolve, delayMilliseconds)
                  )
                  return original(...args)
                }
                const event = new DragEvent('drop', {
                  bubbles: true,
                  cancelable: true,
                  dataTransfer: transfer,
                })
                document.querySelector('.tl-container')
                  ?.dispatchEvent(event)
                window.createImageBitmap = original
                return event.defaultPrevented
                """,
                arguments: [
                    "dataUrl": dataURL,
                    "delayMilliseconds":
                        max(0, delayMilliseconds),
                ],
                in: nil,
                contentWorld: .page
            ) as? Bool ?? false
        } catch {
            return false
        }
    }

    func keyboardEventForTesting(
        type: String,
        key: String,
        code: String,
        metaKey: Bool = false
    ) async -> [String: Any]? {
        do {
            return try await webView.callAsyncJavaScript(
                """
                const event = new KeyboardEvent(eventType, {
                  key,
                  code,
                  metaKey,
                  bubbles: true,
                  cancelable: true,
                })
                window.dispatchEvent(event)
                return {
                  defaultPrevented: event.defaultPrevented,
                  selectedTool:
                    window.traceProductRenderer
                      .getStateForTesting().selectedTool,
                  productTool:
                    window.traceProductRenderer
                      .getStateForTesting().productTool,
                }
                """,
                arguments: [
                    "eventType": type,
                    "key": key,
                    "code": code,
                    "metaKey": metaKey,
                ],
                in: nil,
                contentWorld: .page
            ) as? [String: Any]
        } catch {
            return nil
        }
    }

    func emitPointerForTesting(
        phase: String,
        x: Double,
        y: Double
    ) async -> Bool {
        do {
            _ = try await webView.callAsyncJavaScript(
                """
                window.traceProductRenderer.emitPointerForTesting(
                  phase,
                  x,
                  y
                )
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

    func setZoomForTesting(_ zoom: Double) async -> Bool {
        do {
            _ = try await webView.callAsyncJavaScript(
                """
                window.traceProductRenderer.setZoomForTesting(zoom)
                """,
                arguments: ["zoom": zoom],
                in: nil,
                contentWorld: .page
            )
            return true
        } catch {
            return false
        }
    }

    func writeSnapshotForTesting(to url: URL) async throws {
        let image: NSImage = try await withCheckedThrowingContinuation {
            continuation in
            webView.takeSnapshot(with: nil) { image, error in
                if let image {
                    continuation.resume(returning: image)
                } else {
                    continuation.resume(
                        throwing: error ?? CocoaError(.fileReadUnknown)
                    )
                }
            }
        }
        guard let data = image.tiffRepresentation,
              let representation = NSBitmapImageRep(data: data),
              let png = representation.representation(
                  using: NSBitmapImageRep.FileType.png,
                  properties: [:]
              )
        else {
            throw CocoaError(.fileWriteUnknown)
        }
        try png.write(to: url, options: Data.WritingOptions.atomic)
    }

    func setTimingFinalizationDelayForTesting(
        _ delayMilliseconds: Int
    ) async {
        _ = try? await webView.callAsyncJavaScript(
            """
            window.traceProductRenderer
              .setTimingFinalizationDelayForTesting(delayMilliseconds)
            """,
            arguments: [
                "delayMilliseconds": max(0, delayMilliseconds),
            ],
            in: nil,
            contentWorld: .page
        )
    }

    func selectFirstUserShapeForTesting() async -> Bool {
        do {
            return try await webView.callAsyncJavaScript(
                """
                return window.traceProductRenderer
                  .selectFirstUserShapeForTesting()
                """,
                arguments: [:],
                in: nil,
                contentWorld: .page
            ) as? Bool ?? false
        } catch {
            return false
        }
    }

    func clearSelectionForTesting() async {
        _ = try? await webView.callAsyncJavaScript(
            """
            window.traceProductRenderer.clearSelectionForTesting()
            """,
            arguments: [:],
            in: nil,
            contentWorld: .page
        )
    }

    func deleteSelectionForTesting() async {
        _ = try? await webView.callAsyncJavaScript(
            """
            window.traceProductRenderer.deleteSelectionForTesting()
            """,
            arguments: [:],
            in: nil,
            contentWorld: .page
        )
    }

    func showErrorForTesting(_ detail: String) {
        showLoadError(detail)
    }

    var errorPresentationForTesting: (
        visible: Bool,
        message: String
    ) {
        (
            visible: !errorLabel.isHidden,
            message: errorLabel.stringValue
        )
    }
#endif

    deinit {
        webView.configuration.userContentController
            .removeScriptMessageHandler(forName: "traceRenderer")
    }

    func setDocument(
        _ document: TraceDrawingSession,
        toolState: TraceToolState
    ) {
        documentGeneration += 1
        appliedDocumentGeneration = nil
        pendingDocumentFrameGeneration = nil
        currentDocumentID = document.manifest.id
        viewport = document.manifest.viewport
            ?? TracePageViewport.full
        pageSize = visiblePageSize(for: document)
        pendingDocument = documentPayload(document)
        pendingTool = toolPayload(toolState)
        pendingBackground = nil
        pendingStrokeSync = nil
        pendingImageBatches.removeAll(keepingCapacity: true)
        queuedUpdates.removeAll(keepingCapacity: true)
        pendingHistoryCommands.removeAll(keepingCapacity: true)
        scheduleOperation()
    }

    func setToolState(_ toolState: TraceToolState) {
        pendingTool = toolPayload(toolState)
        scheduleOperation()
    }

    func setBackgroundColor(_ color: TraceRGBAColor) {
        guard currentDocumentID != nil else {
            return
        }
        pendingBackground = cssColor(color)
        scheduleOperation()
    }

    func focusCanvas() {
        window?.makeFirstResponder(webView)
    }

    func syncStrokes(_ document: TraceDrawingSession) {
        pendingStrokeSync = PendingStrokeSync(
            strokes: document.manifest.strokes.map(strokePayload),
            shapeAnnotations: shapeAnnotationPayloads(document)
        )
        scheduleOperation()
    }

    func setTranscriptAnnotationScale(
        _ scale: TraceTranscriptAnnotationScale,
        document: TraceDrawingSession?
    ) {
        guard annotationScale != scale else {
            return
        }
        annotationScale = scale
        if let document {
            syncStrokes(document)
        }
    }

    func apply(_ update: TraceAnnotationUpdate) {
        let tldrawUpdate = TraceAnnotationUpdate(
            strokeID: update.strokeID,
            style: update.style,
            committed: update.committed,
            predicted: update.predicted,
            replacement: nil,
            isFinal: update.isFinal
        )
        if !queuedUpdates.isEmpty,
           queuedUpdates[queuedUpdates.count - 1].merge(tldrawUpdate)
        {
            scheduleOperation()
            return
        }
        queuedUpdates.append(QueuedUpdate(tldrawUpdate))
        scheduleOperation()
    }

    @discardableResult
    func insertImage(_ image: NSImage) -> Bool {
        insertImages([
            TraceCanvasImage(
                image: image,
                name: "Pasted image"
            ),
        ])
    }

    @discardableResult
    func insertImages(_ images: [TraceCanvasImage]) -> Bool {
        guard currentDocumentID != nil,
              !images.isEmpty
        else {
            return false
        }
        let payloads = images.compactMap(imagePayload)
        guard payloads.count == images.count else {
            return false
        }
        pendingImageBatches.append(payloads)
        scheduleOperation()
        return true
    }

    func exportImage(
        pixelRatio: CGFloat,
        completion: @escaping (NSImage?) -> Void
    ) {
        Task { @MainActor [weak self] in
            guard let self, isReady else {
                completion(nil)
                return
            }
            let generation = documentGeneration
            guard let documentID = currentDocumentID else {
                completion(nil)
                return
            }
            let documentIDString =
                documentID.uuidString.lowercased()
            for _ in 0..<100 where hasPendingWork {
                try? await Task.sleep(nanoseconds: 20_000_000)
            }
            guard !hasPendingWork,
                  generation == documentGeneration,
                  documentID == currentDocumentID
            else {
                completion(nil)
                return
            }
            do {
                guard let result = try await webView.callAsyncJavaScript(
                    """
                    await window.traceProductRenderer.waitForIdle()
                    const snapshot =
                      window.traceProductRenderer.getSnapshot()
                    const exported =
                      await window.traceProductRenderer.exportPng(
                        pixelRatio,
                        expectedDocumentId
                      )
                    return {
                      documentId: exported.documentId,
                      snapshotJson: snapshot.snapshotJson,
                      timedShapes: snapshot.timedShapes,
                      dataUrl: exported.dataUrl,
                    }
                    """,
                    arguments: [
                        "pixelRatio": max(1, pixelRatio),
                        "expectedDocumentId": documentIDString,
                    ],
                    in: nil,
                    contentWorld: .page
                ) as? [String: Any],
                      result["documentId"] as? String
                        == documentIDString,
                      generation == documentGeneration,
                      documentID == currentDocumentID
                else {
                    completion(nil)
                    return
                }
                if let snapshot = result["snapshotJson"] as? String {
                    onSnapshotChange?(
                        snapshot,
                        timedShapes(from: result["timedShapes"])
                    )
                }
                completion(
                    (result["dataUrl"] as? String)
                        .flatMap(imageFromDataURL)
                )
            } catch {
                completion(nil)
            }
        }

    }

    func flushSnapshot(completion: @escaping () -> Void) {
        Task { @MainActor [weak self] in
            guard let self, isReady else {
                completion()
                return
            }
            let generation = documentGeneration
            guard let documentID = currentDocumentID else {
                completion()
                return
            }
            let documentIDString =
                documentID.uuidString.lowercased()
            for _ in 0..<100 where hasPendingWork {
                try? await Task.sleep(nanoseconds: 20_000_000)
            }
            guard !hasPendingWork,
                  generation == documentGeneration,
                  documentID == currentDocumentID
            else {
                completion()
                return
            }
            do {
                if let result = try await webView.callAsyncJavaScript(
                    """
                    await window.traceProductRenderer.waitForIdle()
                    return window.traceProductRenderer.getSnapshot()
                    """,
                    arguments: [:],
                    in: nil,
                    contentWorld: .page
                ) as? [String: Any],
                   result["documentId"] as? String
                    == documentIDString,
                   generation == documentGeneration,
                   documentID == currentDocumentID,
                   let snapshot = result["snapshotJson"] as? String
                {
                    onSnapshotChange?(
                        snapshot,
                        timedShapes(from: result["timedShapes"])
                    )
                }
            } catch {
                if generation == documentGeneration {
                    showLoadError(error.localizedDescription)
                }
            }
            completion()
        }
    }

    func undo() {
        pendingHistoryCommands.append(
            "window.traceProductRenderer.undo()"
        )
        scheduleOperation()
    }

    func redo() {
        pendingHistoryCommands.append(
            "window.traceProductRenderer.redo()"
        )
        scheduleOperation()
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
        case "product-ready":
            isReady = true
            scheduleOperation()
        case "product-change":
            if isCurrentDocumentMessage(body),
               let snapshotJSON = body["snapshotJson"] as? String
            {
                onSnapshotChange?(
                    snapshotJSON,
                    timedShapes(from: body["timedShapes"])
                )
            }
        case "product-edit":
            if isCurrentDocumentMessage(body) {
                onUserEdit?(
                    (body["count"] as? NSNumber)?.intValue ?? 1
                )
            }
        case "product-history":
            if isCurrentDocumentMessage(body) {
                canUndo = body["canUndo"] as? Bool ?? false
                canRedo = body["canRedo"] as? Bool ?? false
                onHistoryChange?(canUndo, canRedo)
            }
        case "product-tool-change":
            if isCurrentDocumentMessage(body),
               let rawTool = body["tool"] as? String,
               let tool = TraceCanvasTool(rawValue: rawTool)
            {
                onToolChange?(tool)
            }
        case "product-tool-preview":
            guard isCurrentDocumentMessage(body) else {
                return
            }
            if let rawTool = body["tool"] as? String {
                onTemporaryToolChange?(
                    TraceCanvasTool(rawValue: rawTool)
                )
            } else {
                onTemporaryToolChange?(nil)
            }
        case "product-export-resolution":
            guard isCurrentDocumentMessage(body) else {
                return
            }
            NSLog(
                "Trace image export resolution reduced: requested=%@ "
                    + "effective=%@ bounds=%@ output=%@x%@",
                String(
                    describing:
                        body["requestedPixelRatio"] ?? "unknown"
                ),
                String(
                    describing:
                        body["effectivePixelRatio"] ?? "unknown"
                ),
                String(describing: body["bounds"] ?? "unknown"),
                String(describing: body["pixelWidth"] ?? "unknown"),
                String(describing: body["pixelHeight"] ?? "unknown")
            )
#if DEBUG
        case "sidecar-input-probe":
            guard ProcessInfo.processInfo.environment[
                "TRACE_SIDECAR_INPUT_PROBE"
            ] == "1" else {
                return
            }
            let fields = [
                "eventType",
                "pointerType",
                "pointerId",
                "isPrimary",
                "pressure",
                "tangentialPressure",
                "tiltX",
                "tiltY",
                "twist",
                "width",
                "height",
                "buttons",
                "button",
                "clientX",
                "clientY",
            ].map {
                "\($0)=\(String(describing: body[$0] ?? "nil"))"
            }.joined(separator: " ")
            NSLog("Trace Sidecar input probe web: %@", fields)
#endif
        case "product-error", "error":
            let detail = body["message"] as? String
                ?? "Unknown tldraw product renderer error"
            showLoadError(detail)
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
        didFailProvisionalNavigation navigation: WKNavigation!,
        withError error: Error
    ) {
        showLoadError(error.localizedDescription)
    }

    func webViewWebContentProcessDidTerminate(_ webView: WKWebView) {
        showLoadError("The tldraw WebContent process terminated.")
    }

    private var hasPendingWork: Bool {
        pendingDocument != nil
            || pendingTool != nil
            || pendingBackground != nil
            || pendingStrokeSync != nil
            || pendingDocumentFrameGeneration != nil
            || !pendingImageBatches.isEmpty
            || !queuedUpdates.isEmpty
            || !pendingHistoryCommands.isEmpty
            || evaluationInFlight
            || operationScheduled
    }

    private func scheduleOperation() {
        guard isReady,
              unavailableReason == nil,
              !evaluationInFlight,
              !operationScheduled,
              pendingDocument != nil
                || pendingTool != nil
                || pendingBackground != nil
                || pendingStrokeSync != nil
                || pendingDocumentFrameGeneration != nil
                || !pendingImageBatches.isEmpty
                || !queuedUpdates.isEmpty
                || !pendingHistoryCommands.isEmpty
        else {
            return
        }
        operationScheduled = true
        DispatchQueue.main.async { [weak self] in
            guard let self else {
                return
            }
            operationScheduled = false
            performNextOperation()
        }
    }

    private func performNextOperation() {
        guard isReady,
              unavailableReason == nil,
              !evaluationInFlight
        else {
            return
        }
        let script: String
        let arguments: [String: Any]
        let completesDocument: Bool
        let completesDocumentFrame: Bool
        let generation = documentGeneration
        let operationDocumentID = currentDocumentID
        if let document = pendingDocument {
            pendingDocument = nil
            script = "window.traceProductRenderer.setDocument(document)"
            arguments = ["document": document]
            completesDocument = true
            completesDocumentFrame = false
        } else if let frameGeneration = pendingDocumentFrameGeneration {
            pendingDocumentFrameGeneration = nil
            script = """
                window.traceProductRenderer.frameDocument(
                  viewportWidth,
                  viewportHeight
                )
                """
            arguments = [
                "viewportWidth": max(1, bounds.width),
                "viewportHeight": max(1, bounds.height),
            ]
            completesDocument = false
            completesDocumentFrame = frameGeneration == generation
        } else if let tool = pendingTool {
            pendingTool = nil
            script = "window.traceProductRenderer.setTool(tool)"
            arguments = ["tool": tool]
            completesDocument = false
            completesDocumentFrame = false
        } else if let background = pendingBackground {
            pendingBackground = nil
            script =
                "window.traceProductRenderer.setBackground(color)"
            arguments = ["color": background]
            completesDocument = false
            completesDocumentFrame = false
        } else if let strokes = pendingStrokeSync {
            pendingStrokeSync = nil
            script = """
                window.traceProductRenderer.syncStrokes(
                  strokes,
                  shapeAnnotations
                )
                """
            arguments = [
                "strokes": strokes.strokes,
                "shapeAnnotations": strokes.shapeAnnotations,
            ]
            completesDocument = false
            completesDocumentFrame = false
        } else if !queuedUpdates.isEmpty {
            let update = queuedUpdates.removeFirst()
            script =
                "window.traceProductRenderer.applyAnnotationUpdate(update)"
            arguments = ["update": updatePayload(update)]
            completesDocument = false
            completesDocumentFrame = false
        } else if !pendingImageBatches.isEmpty {
            let images = pendingImageBatches.removeFirst()
            script = "window.traceProductRenderer.insertImages(images)"
            arguments = ["images": images]
            completesDocument = false
            completesDocumentFrame = false
        } else if !pendingHistoryCommands.isEmpty {
            script = pendingHistoryCommands.removeFirst()
            arguments = [:]
            completesDocument = false
            completesDocumentFrame = false
        } else {
            return
        }
        evaluationInFlight = true
        Task { @MainActor [weak self] in
            guard let self else {
                return
            }
            defer {
                evaluationInFlight = false
                scheduleOperation()
            }
            do {
                _ = try await webView.callAsyncJavaScript(
                    script,
                    arguments: arguments,
                    in: nil,
                    contentWorld: .page
                )
                if completesDocument,
                   generation == documentGeneration,
                   operationDocumentID == currentDocumentID
                {
                    appliedDocumentGeneration = generation
                    scheduleInitialDocumentFrame(
                        generation: generation
                    )
                } else if completesDocumentFrame,
                          generation == documentGeneration,
                          operationDocumentID == currentDocumentID
                {
                    onDocumentReady?()
                }
            } catch {
                if generation == documentGeneration {
                    showLoadError(error.localizedDescription)
                }
            }
        }
    }

    private func scheduleInitialDocumentFrame(generation: Int) {
        DispatchQueue.main.async { [weak self] in
            guard let self,
                  generation == documentGeneration,
                  appliedDocumentGeneration == generation,
                  bounds.width > 0,
                  bounds.height > 0
            else {
                return
            }
            layoutSubtreeIfNeeded()
            pendingDocumentFrameGeneration = generation
            scheduleOperation()
        }
    }

    private func documentPayload(
        _ document: TraceDrawingSession
    ) -> [String: Any] {
        [
            "id": document.manifest.id.uuidString.lowercased(),
            "pageKind": (
                document.manifest.pageKind ?? .screenshot
            ).rawValue,
            "backgroundColor": cssColor(
                document.manifest.backgroundColor
                    ?? TraceRGBAColor(red: 1, green: 1, blue: 1)
            ),
            "width": pageSize.width,
            "height": pageSize.height,
            "backgroundDataUrl":
                backgroundDataURL(document) ?? "",
            "snapshotJson":
                document.tldrawSnapshotJSON ?? NSNull(),
            "strokes": document.manifest.strokes.map(strokePayload),
            "shapeAnnotations": shapeAnnotationPayloads(document),
        ]
    }

    private func strokePayload(
        _ stroke: TraceDrawingStroke
    ) -> [String: Any] {
        [
            "id": String(stroke.id),
            "color": colorName(stroke.color),
            "brush": brushName(stroke.brush),
            "width": stroke.width,
            "annotationId":
                stroke.transcriptAnnotation?.id ?? NSNull(),
            "annotationDiameter":
                annotationDiameter(for: stroke) ?? 0,
            "points": stroke.points.map(pointPayload),
        ]
    }

    private func shapeAnnotationPayloads(
        _ document: TraceDrawingSession
    ) -> [[String: Any]] {
        (document.manifest.timedCanvasShapes ?? []).compactMap {
            shape in
            guard let annotation = shape.transcriptAnnotation else {
                return nil
            }
            return [
                "shapeId": shape.id,
                "annotationId": annotation.id,
                "diameter":
                    TraceTranscriptAnnotationPlanner.labelDiameter(
                        pathLength: shape.pathLength,
                        annotationID: annotation.id,
                        scale: annotationScale
                    ),
            ]
        }
    }

    private func timedShapes(from value: Any?) -> [TraceTimedCanvasShape] {
        guard let payloads = value as? [[String: Any]] else {
            return []
        }
        return payloads.compactMap { payload in
            guard let id = payload["id"] as? String,
                  let startedAt = (
                      payload["startedAtAppClockSeconds"]
                          as? NSNumber
                  )?.doubleValue,
                  let endedAt = (
                      payload["endedAtAppClockSeconds"]
                          as? NSNumber
                  )?.doubleValue,
                  let pathLength = (
                      payload["pathLength"] as? NSNumber
                  )?.doubleValue,
                  startedAt.isFinite,
                  endedAt.isFinite,
                  endedAt >= startedAt,
                  pathLength.isFinite,
                  pathLength >= 0
            else {
                return nil
            }
            return TraceTimedCanvasShape(
                id: id,
                startedAtAppClockSeconds: startedAt,
                endedAtAppClockSeconds: endedAt,
                pathLength: pathLength
            )
        }.sorted(by: { $0.id < $1.id })
    }

    private func updatePayload(
        _ update: QueuedUpdate
    ) -> [String: Any] {
        [
            "strokeId": String(update.strokeID),
            "color": colorName(update.style.color),
            "brush": brushName(update.style.brush),
            "width": update.style.width,
            "committed": update.committed.map(pointPayload),
            "predicted": update.predicted.map(pointPayload),
            "replacement": NSNull(),
            "isFinal": update.isFinal,
            "sampleIds": [],
        ]
    }

    private func pointPayload(
        _ point: TraceDrawingPoint
    ) -> [String: Any] {
        let mapped = TracePageViewport.map(
            TracePoint(x: point.x, y: point.y),
            through: viewport
        )
        return [
            "x": mapped.x,
            "y": mapped.y,
            "pressure": point.pressure.map {
                NSNumber(value: $0)
            } ?? NSNull(),
            "connectsToPrevious": point.connectsToPrevious,
        ]
    }

    private func toolPayload(
        _ state: TraceToolState
    ) -> [String: Any] {
        [
            "tool": productToolName(state),
            "color": colorName(state.color),
            "brush": brushName(state.brush),
            "width": state.width,
            "gridStyle": state.gridStyle.rawValue,
            "gridSpacing": state.gridSpacingPoints,
        ]
    }

    private func colorName(_ color: TraceRGBAColor) -> String {
        if color == .blue { return "blue" }
        if color == .yellow { return "yellow" }
        if color == .green { return "green" }
        return "red"
    }

    private func brushName(_ brush: TraceBrushKind) -> String {
        brush == .highlighter ? "highlighter" : "pen"
    }

    private func productToolName(_ state: TraceToolState) -> String {
        state.canvasTool.rawValue
    }

    private func cssColor(_ color: TraceRGBAColor) -> String {
        let red = Int((color.red * 255).rounded())
        let green = Int((color.green * 255).rounded())
        let blue = Int((color.blue * 255).rounded())
        return "rgba(\(red), \(green), \(blue), \(color.alpha))"
    }

    private func annotationDiameter(
        for stroke: TraceDrawingStroke
    ) -> Double? {
        guard let annotation = stroke.transcriptAnnotation else {
            return nil
        }
        let mapped = stroke.points.map { point -> TracePoint in
            let local = TracePageViewport.map(
                TracePoint(x: point.x, y: point.y),
                through: viewport
            )
            return TracePoint(
                x: local.x * pageSize.width,
                y: local.y * pageSize.height
            )
        }
        var pathLength = 0.0
        for index in mapped.indices.dropFirst() where
            stroke.points[index].connectsToPrevious
        {
            pathLength += hypot(
                mapped[index].x - mapped[index - 1].x,
                mapped[index].y - mapped[index - 1].y
            )
        }
        return TraceTranscriptAnnotationPlanner.labelDiameter(
            pathLength: pathLength,
            annotationID: annotation.id,
            scale: annotationScale
        )
    }

    private func visiblePageSize(
        for document: TraceDrawingSession
    ) -> NSSize {
        let source = document.manifest.sourceWindowBounds
            ?? TraceRect(
                x: 0,
                y: 0,
                width: Double(document.screenshot.size.width),
                height: Double(document.screenshot.size.height)
            )
        return NSSize(
            width: max(1, source.width * viewport.width),
            height: max(1, source.height * viewport.height)
        )
    }

    private func backgroundDataURL(
        _ document: TraceDrawingSession
    ) -> String? {
        if document.manifest.pageKind == .blank {
            return nil
        }
        if viewport == TracePageViewport.full {
            let screenshotURL = document.packageURL.appendingPathComponent(
                document.manifest.screenshotFileName
            )
            if let data = try? Data(contentsOf: screenshotURL) {
                return "data:image/png;base64,"
                    + data.base64EncodedString()
            }
        }
        let image: NSImage
        if document.manifest.pageKind == .screenshot,
           viewport != TracePageViewport.full
        {
            image = NSImage(size: pageSize)
            image.lockFocus()
            let source = document.screenshot.size
            document.screenshot.draw(
                in: NSRect(origin: .zero, size: pageSize),
                from: NSRect(
                    x: source.width * viewport.x,
                    y: source.height
                        * (1 - viewport.y - viewport.height),
                    width: source.width * viewport.width,
                    height: source.height * viewport.height
                ),
                operation: .sourceOver,
                fraction: 1,
                respectFlipped: true,
                hints: [
                    .interpolation:
                        NSImageInterpolation.high,
                ]
            )
            image.unlockFocus()
        } else {
            image = document.screenshot
        }
        guard let representation = bitmapRepresentation(
            of: image
        ),
        let png = representation.representation(
            using: .png,
            properties: [:]
        )
        else {
            return nil
        }
        return "data:image/png;base64,"
            + png.base64EncodedString()
    }

    private func imageDataURL(_ image: NSImage) -> String? {
        guard let representation = bitmapRepresentation(of: image),
              let png = representation.representation(
                  using: .png,
                  properties: [:]
              )
        else {
            return nil
        }
        return "data:image/png;base64,"
            + png.base64EncodedString()
    }

    private func imagePayload(
        _ image: TraceCanvasImage
    ) -> [String: Any]? {
        guard let dataURL = imageDataURL(image.image) else {
            return nil
        }
        return [
            "dataUrl": dataURL,
            "name": image.name,
            "mimeType": "image/png",
            "width": max(1, image.image.size.width),
            "height": max(1, image.image.size.height),
        ]
    }

    private func bitmapRepresentation(
        of image: NSImage
    ) -> NSBitmapImageRep? {
        if let representation = image.representations
            .compactMap({ $0 as? NSBitmapImageRep })
            .max(by: {
                $0.pixelsWide * $0.pixelsHigh
                    < $1.pixelsWide * $1.pixelsHigh
            })
        {
            return representation
        }
        guard let data = image.tiffRepresentation else {
            return nil
        }
        return NSBitmapImageRep(data: data)
    }

    private func imageFromDataURL(_ value: String) -> NSImage? {
        guard let comma = value.firstIndex(of: ","),
              let data = Data(
                  base64Encoded: String(value[value.index(after: comma)...])
              )
        else {
            return nil
        }
        return NSImage(data: data)
    }

    private func loadBundle(from resourceDirectory: URL?) {
        guard let resourceDirectory,
              FileManager.default.fileExists(
                  atPath: resourceDirectory
                      .appendingPathComponent("index.html").path
              ),
              FileManager.default.fileExists(
                  atPath: resourceDirectory
                      .appendingPathComponent("icon-sprite.svg").path
              )
        else {
            showLoadError(
                "Run tools/trace to build and bundle the tldraw canvas."
            )
            return
        }
        webView.load(
            URLRequest(
                url: ProductRendererSchemeHandler.indexURL
            )
        )
    }

    private func isCurrentDocumentMessage(
        _ body: [String: Any]
    ) -> Bool {
        guard let currentDocumentID,
              let documentID = body["documentId"] as? String
        else {
            return false
        }
        return documentID
            == currentDocumentID.uuidString.lowercased()
    }

    private func showLoadError(_ detail: String) {
        unavailableReason = detail
        isReady = false
        canUndo = false
        canRedo = false
        webView.isHidden = true
        errorLabel.stringValue = "Canvas unavailable\n\(detail)"
        errorLabel.isHidden = false
        onUnavailable?()
        NSLog("Trace tldraw canvas unavailable: %@", detail)
    }
}

private final class ProductWeakScriptMessageHandler:
    NSObject,
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

private final class ProductRendererSchemeHandler:
    NSObject,
    WKURLSchemeHandler
{
    static let scheme = "trace-product-renderer"
    static let indexURL = URL(
        string: "\(scheme)://app/index.html?surface=product"
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
