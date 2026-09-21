#if DEBUG
import AppKit
import NeoInput
import NeoTransport
import TraceGeometry
import TraceLabReplay
import TraceStrokeProcessing

enum RendererLabProbe {
    private static let expectedDrawingSize = NSSize(
        width: 1_024,
        height: 720
    )
    private static let expectedWindowContentSize = NSSize(
        width: 1_072,
        height: 862
    )

    @MainActor
    static func run() async throws {
        try verifyDrawingLayout()
        try verifyTldrawProcessingContract()
        try verifyMouseCanvasLifecycle()
        try await verifyMouseProcessing()
        try verifyPickerAndMouseReadiness()
        try verifyUnavailablePaperKitSurface()
        try verifyTldrawMissingResource()
#if canImport(PaperKit)
        if #available(macOS 26.0, *) {
            try verifyPaperKitPenInjection()
        }
#endif
        try await verifyTldrawPenInjection()
    }

    private static func verifyDrawingLayout() throws {
        let invalidBounds = NSRect(
            x: 0,
            y: 0,
            width: CGFloat.infinity,
            height: 700
        )
        guard LabPaperLayout.drawingRect(
            in: invalidBounds
        ) == .zero else {
            throw probeError(
                "renderer layout accepted non-finite view geometry"
            )
        }
        let traceRect = LabPaperLayout.drawingRect(
            in: NSRect(
                origin: .zero,
                size: LabPaperLayout.minimumRendererSize
            )
        )
        let paperKitRect = LabPaperLayout.drawingRect(
            in: NSRect(
                origin: .zero,
                size: LabPaperLayout.minimumRendererSize
            ),
            topReservedHeight:
                LabPaperLayout.paperKitToolbarBandHeight
        )
        let allRenderersProcessPen = LabRendererMode.allCases.allSatisfy({
            $0.supportsTraceProcessing(
                penInputReady: true,
                isReplay: false
            )
        })
        let mouseCapabilitiesMatch =
            LabRendererMode.trace.supportsTraceProcessing(
                penInputReady: false,
                isReplay: false
            )
            && LabRendererMode.tldraw.supportsTraceProcessing(
                penInputReady: false,
                isReplay: false
            )
            && !LabRendererMode.paperKit.supportsTraceProcessing(
                penInputReady: false,
                isReplay: false
            )
        guard allRenderersProcessPen, mouseCapabilitiesMatch
        else {
            throw probeError(
                "renderer processing capabilities do not match input paths"
            )
        }
        guard LabPaperLayout.drawingSize == expectedDrawingSize,
              LabPaperLayout.minimumWindowContentSize
                  == expectedWindowContentSize,
              traceRect.size == expectedDrawingSize,
              paperKitRect.size == expectedDrawingSize,
              traceRect.origin == NSPoint(x: 24, y: 50),
              paperKitRect.origin == NSPoint(x: 24, y: 76),
              LabPaperLayout.drawingRect(
                  in: NSRect(
                      origin: .zero,
                      size: NSSize(width: 1_071, height: 819)
                  )
              ) == .zero
        else {
            throw probeError(
                "renderers did not preserve the 1024x720 drawing area"
            )
        }
    }

    private static func verifyTldrawProcessingContract() throws {
        let base = rendererUpdate(isFinal: false)
        let interpolated = LabRenderPoint(
            render: RenderPoint(
                x: 0.4,
                y: 0.4,
                pressure: 0.45,
                kind: .interpolated,
                sourceSampleID: nil,
                connectsToPrevious: true
            ),
            normalized: UnitPoint(x: 0.4, y: 0.4)
        )
        let predicted = LabRenderPoint(
            render: RenderPoint(
                x: 0.7,
                y: 0.6,
                pressure: 0.55,
                kind: .predicted,
                sourceSampleID: nil,
                connectsToPrevious: true
            ),
            normalized: UnitPoint(x: 0.7, y: 0.6)
        )
        let predictedSecond = LabRenderPoint(
            render: RenderPoint(
                x: 0.75,
                y: 0.65,
                pressure: 0.5,
                kind: .predicted,
                sourceSampleID: nil,
                connectsToPrevious: true
            ),
            normalized: UnitPoint(x: 0.75, y: 0.65)
        )
        let predictedThird = LabRenderPoint(
            render: RenderPoint(
                x: 0.8,
                y: 0.7,
                pressure: 0.45,
                kind: .predicted,
                sourceSampleID: nil,
                connectsToPrevious: true
            ),
            normalized: UnitPoint(x: 0.8, y: 0.7)
        )
        let refined = LabRenderPoint(
            render: RenderPoint(
                x: 0.5,
                y: 0.5,
                pressure: 0.6,
                kind: .refined,
                sourceSampleID: nil,
                connectsToPrevious: true
            ),
            normalized: UnitPoint(x: 0.5, y: 0.5)
        )
        let update = LabRendererUpdate(
            strokeID: base.strokeID,
            committed: [base.committed[0], interpolated],
            predicted: [
                predicted,
                predictedSecond,
                predictedThird,
            ],
            replacement: [refined],
            sourceSamples: base.sourceSamples,
            refinementReadyUptimeNanoseconds: 1,
            isFinal: true
        )
        let prepared = LabRendererMode.tldraw.prepare(update)
        let mousePrepared = LabRendererMode.tldraw.prepare(
            LabRendererUpdate(
                strokeID: LabMouseIdentifier.base,
                committed: update.committed,
                predicted: update.predicted,
                replacement: update.replacement,
                sourceSamples: update.sourceSamples,
                refinementReadyUptimeNanoseconds:
                    update.refinementReadyUptimeNanoseconds,
                isFinal: update.isFinal
            )
        )
        guard LabRendererMode.tldraw.supportsTraceProcessingForMouse,
              !LabRendererMode.paperKit.supportsTraceProcessingForMouse,
              prepared.committed.count == 2,
              prepared.committed[1].render.kind == .interpolated,
              prepared.predicted.count == 3,
              prepared.predicted[0].render.pressure == 0.55,
              prepared.replacement == nil,
              mousePrepared.predicted.count == 1,
              mousePrepared.predicted[0].render.pressure == 0.55,
              LabRendererMode.trace.prepare(update).replacement != nil
        else {
            throw probeError(
                "tldraw processing contract did not preserve fill, "
                    + "prediction, and pressure while suppressing Smooth"
            )
        }
    }

    @MainActor
    private static func verifyMouseCanvasLifecycle() throws {
        let canvas = RawCanvasView(
            frame: NSRect(
                origin: .zero,
                size: LabPaperLayout.minimumRendererSize
            )
        )
        canvas.mouseDrawingEnabled = true
        let window = NSWindow(
            contentRect: canvas.frame,
            styleMask: .borderless,
            backing: .buffered,
            defer: false
        )
        window.contentView = canvas
        guard canvas.drawingRectForTesting.size
            == expectedDrawingSize
        else {
            throw probeError(
                "Trace did not expose a 1024x720 drawing area"
            )
        }

        var phases: [String] = []
        var samples: [LabMouseSample] = []
        canvas.onMouseStrokeEvent = { event in
            switch event {
            case let .began(sample):
                phases.append("began")
                samples.append(sample)
            case let .moved(sample):
                phases.append("moved")
                samples.append(sample)
            case let .ended(sample):
                phases.append("ended")
                samples.append(sample)
            }
        }

        let priorCoalescing = NSEvent.isMouseCoalescingEnabled
        defer {
            NSEvent.isMouseCoalescingEnabled = priorCoalescing
        }
        NSEvent.isMouseCoalescingEnabled = true

        canvas.mouseDown(
            with: try mouseEvent(
                type: .leftMouseDown,
                location: NSPoint(x: 300, y: 300),
                window: window,
                eventNumber: 1
            )
        )
        guard !NSEvent.isMouseCoalescingEnabled else {
            throw probeError(
                "Trace mouse input did not disable event coalescing"
            )
        }
        canvas.mouseDragged(
            with: try mouseEvent(
                type: .leftMouseDragged,
                location: NSPoint(x: 450, y: 400),
                window: window,
                eventNumber: 2
            )
        )
        canvas.mouseUp(
            with: try mouseEvent(
                type: .leftMouseUp,
                location: .zero,
                window: window,
                eventNumber: 3
            )
        )

        guard phases == ["began", "moved", "ended"],
              samples.count == 3,
              samples.allSatisfy({
                  (0...1).contains($0.point.x)
                      && (0...1).contains($0.point.y)
              }),
              NSEvent.isMouseCoalescingEnabled
        else {
            throw probeError(
                "Trace mouse begin/move/end or coalescing restoration failed"
            )
        }
    }

    @MainActor
    private static func verifyMouseProcessing() async throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        defer {
            try? FileManager.default.removeItem(at: directory)
        }
        let model = try LabModel(
            configuration: LabConfiguration(
                logDirectory: directory,
                implementationID: "renderer-probe",
                paperProfile: "renderer-probe",
                replayURL: nil,
                replaySpeed: 1,
                quitAfterReplay: false,
                processingMode: .predict,
                interpolationAlgorithm: .circularArc,
                refinementAlgorithm: .smoothPath,
                predictionAlgorithm: .velocity,
                rendererMode: .trace
            ),
            transport: RendererProbeTransport()
        )
        defer {
            model.stop()
        }
        var updates: [LabRendererUpdate] = []
        model.onRenderUpdate = {
            updates.append($0)
        }
        model.handleMouseStroke(
            .began(
                mouseSample(
                    x: 0.2,
                    y: 0.3,
                    milliseconds: 1_000
                )
            )
        )
        model.handleMouseStroke(
            .moved(
                mouseSample(
                    x: 0.35,
                    y: 0.4,
                    milliseconds: 1_016
                )
            )
        )
        model.handleMouseStroke(
            .ended(
                mouseSample(
                    x: 0.5,
                    y: 0.45,
                    milliseconds: 1_032
                )
            )
        )
        guard updates.contains(where: {
            !$0.committed.isEmpty && !$0.isFinal
        }),
        updates.last?.isFinal == true,
        updates.flatMap(\.committed).allSatisfy({
            (0...1).contains($0.normalized.x)
                && (0...1).contains($0.normalized.y)
        })
        else {
            throw probeError(
                "Trace mouse input did not use the shared render stream"
            )
        }
        model.setRendererMode(.paperKit)
        guard model.snapshot.rendererMode == .paperKit else {
            throw probeError("renderer picker did not update the lab model")
        }
        model.stop()
        let rows = try sessionRows(at: model.snapshot.logFileURL)
        guard rows.contains(where: {
            $0["type"] as? String == "session-start"
                && $0["renderer"] as? String == "trace"
        }),
        rows.contains(where: {
            $0["type"] as? String == "renderer-mode"
                && $0["renderer"] as? String == "paperkit"
        }),
        rows.contains(where: {
            $0["type"] as? String == "performance-snapshot"
                && $0["renderer"] as? String == "paperkit"
        })
        else {
            throw probeError(
                "renderer mode was not preserved in the session log"
            )
        }
        let parsedReplay = try LabReplay.load(
            from: model.snapshot.logFileURL
        )
        guard parsedReplay.events
            .filter({
                if case .sample = $0.event {
                    return true
                }
                return false
            })
            .allSatisfy({ $0.inputSource == .mouse })
        else {
            throw probeError(
                "recorded mouse samples lost their replay source"
            )
        }

        let replayModel = try LabModel(
            configuration: LabConfiguration(
                logDirectory: directory,
                implementationID: "renderer-probe-replay",
                paperProfile: "renderer-probe-replay",
                replayURL: model.snapshot.logFileURL,
                replaySpeed: 100,
                quitAfterReplay: false,
                processingMode: .predict,
                interpolationAlgorithm: .circularArc,
                refinementAlgorithm: .smoothPath,
                predictionAlgorithm: .velocity,
                rendererMode: .trace
            ),
            transport: RendererProbeTransport()
        )
        defer {
            replayModel.stop()
        }
        var replayUpdates: [LabRendererUpdate] = []
        replayModel.onRenderUpdate = {
            replayUpdates.append($0)
        }
        replayModel.start()
        do {
            try await waitUntil("mouse replay") {
                replayUpdates.last?.isFinal == true
            }
        } catch {
            throw probeError(
                "recorded mouse input did not replay through Trace: "
                    + (
                        replayModel.snapshot.lastError
                            ?? "no renderer updates"
                    )
            )
        }
        guard replayUpdates.contains(where: {
            !$0.committed.isEmpty
        }) else {
            throw probeError(
                "recorded mouse input did not replay through Trace"
            )
        }
    }

    @MainActor
    private static func verifyPickerAndMouseReadiness() throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        defer {
            try? FileManager.default.removeItem(at: directory)
        }
        let model = try probeModel(
            directory: directory,
            rendererMode: .trace
        )
        defer {
            model.stop()
        }
        let viewController = LabViewController(model: model)
        viewController.loadView()
        let fittingSize = viewController.view.fittingSize
        viewController.view.frame = NSRect(
            x: 0,
            y: 0,
            width: LabPaperLayout.minimumWindowContentSize.width,
            height: LabPaperLayout.minimumWindowContentSize.height
        )
        viewController.view.layoutSubtreeIfNeeded()
        viewController.refreshStatusForTesting()
        let presentationUpdateCount =
            viewController.tracePresentationUpdateCountForTesting
        viewController.refreshStatusForTesting()

        guard viewController.rendererTitlesForTesting
            == LabRendererMode.allCases.map(\.title),
        viewController.selectedRendererTitleForTesting
            == LabRendererMode.trace.title,
        viewController.connectionTextForTesting == "● Mouse ready",
        !viewController.recalibrateEnabledForTesting,
        viewController.processingModeEnabledForTesting,
        viewController.strategyEnabledForTesting,
        viewController.anchorsEnabledForTesting,
        viewController.statusControlsFitForTesting,
        viewController.rendererDrawingSizesForTesting.values
            .allSatisfy({ $0 == expectedDrawingSize }),
        fittingSize.width >= expectedWindowContentSize.width,
        fittingSize.height >= expectedWindowContentSize.height,
        viewController.tracePresentationUpdateCountForTesting
            == presentationUpdateCount
        else {
            throw probeError(
                "renderer picker or mouse-only readiness is incorrect: "
                    + viewController.statusLayoutDescriptionForTesting
                    + " "
                    + viewController.rendererLayoutDescriptionForTesting
                    + " "
                    + viewController.processingControlStateForTesting
            )
        }

        viewController.selectRendererForTesting(.paperKit)
        guard model.snapshot.rendererMode == .paperKit,
              !viewController.processingModeEnabledForTesting,
              !viewController.strategyEnabledForTesting,
              !viewController.anchorsEnabledForTesting
        else {
            throw probeError(
                "PaperKit mouse mode exposed unsupported Trace controls"
            )
        }
        viewController.selectProcessingModeForTesting(0)
        viewController.selectStrategyForTesting(0)
        guard model.snapshot.processingMode == .predict,
              model.snapshot.predictionAlgorithm == .velocity
        else {
            throw probeError(
                "disabled PaperKit processing controls changed the model"
            )
        }
        model.setRendererMode(.tldraw)
        guard viewController.selectedRendererTitleForTesting
            == LabRendererMode.tldraw.title,
              viewController.processingModeEnabledForTesting,
              viewController.strategyEnabledForTesting,
              !viewController.anchorsEnabledForTesting
        else {
            throw probeError(
                "tldraw mouse prediction controls are incorrect"
            )
        }
        model.stop()
    }

    @MainActor
    private static func verifyUnavailablePaperKitSurface() throws {
        let reason = "PaperKit requires macOS 26 or later."
        let surface = UnavailableLabRendererSurface(
            title: "PaperKit",
            reason: reason
        )
        surface.activate()
        guard surface.unavailableReason == reason,
              !surface.view.isHidden
        else {
            throw probeError(
                "PaperKit platform fallback did not expose its requirement"
            )
        }
        surface.deactivate()
        guard surface.view.isHidden else {
            throw probeError(
                "PaperKit platform fallback did not deactivate"
            )
        }
    }

    @MainActor
    private static func verifyTldrawMissingResource() throws {
        let missingDirectory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        let surface = TldrawRendererSurface(
            resourceDirectory: missingDirectory
        )
        guard surface.unavailableReason
            == "Run tools/trace-input-lab to build and bundle tldraw."
        else {
            throw probeError(
                "tldraw did not report its missing bundled resource"
            )
        }
    }

#if canImport(PaperKit)
    @available(macOS 26.0, *)
    @MainActor
    private static func verifyPaperKitPenInjection() throws {
        let surface = PaperKitRendererSurface()
        let visibleFrame = NSScreen.main?.visibleFrame
            ?? NSRect(x: 0, y: 0, width: 1_200, height: 900)
        let window = NSWindow(
            contentRect: NSRect(
                x: visibleFrame.minX + 20,
                y: visibleFrame.minY + 20,
                width: LabPaperLayout.minimumRendererSize.width,
                height: LabPaperLayout.minimumRendererSize.height
            ),
            styleMask: .borderless,
            backing: .buffered,
            defer: false
        )
        let frontmostProcessID =
            NSWorkspace.shared.frontmostApplication?.processIdentifier
        window.alphaValue = 0
        window.ignoresMouseEvents = true
        let host = NSViewController()
        let hostView = NSView(
            frame: NSRect(
                origin: .zero,
                size: LabPaperLayout.minimumRendererSize
            )
        )
        NSLayoutConstraint.activate([
            hostView.widthAnchor.constraint(
                greaterThanOrEqualToConstant:
                    LabPaperLayout.minimumRendererSize.width
            ),
            hostView.heightAnchor.constraint(
                greaterThanOrEqualToConstant:
                    LabPaperLayout.minimumRendererSize.height
            ),
        ])
        host.view = hostView
        for child in surface.childViewControllers {
            host.addChild(child)
        }
        surface.view.frame = hostView.bounds
        surface.view.autoresizingMask = [.width, .height]
        hostView.addSubview(surface.view)
        window.contentViewController = host
        window.contentMinSize =
            LabPaperLayout.minimumRendererSize
        window.setContentSize(
            LabPaperLayout.minimumRendererSize
        )
        window.orderBack(nil)
        defer {
            window.orderOut(nil)
        }
        RunLoop.current.run(
            until: Date().addingTimeInterval(0.05)
        )
        guard !window.isKeyWindow,
              window.alphaValue == 0,
              frontmostProcessID == nil
                || NSWorkspace.shared.frontmostApplication?
                    .processIdentifier == frontmostProcessID
        else {
            throw probeError(
                "PaperKit probe interrupted the active application"
            )
        }
        surface.updatePresentation(
            LabRendererPresentation(
                calibration: nil,
                calibrationActive: false,
                pagePriming: false,
                calibrationCorner: nil,
                message: nil
            )
        )
        surface.activate()
        surface.view.layoutSubtreeIfNeeded()
        guard let start = surface.windowPointForTesting(
            normalized: UnitPoint(x: 0.2, y: 0.2)
        ) else {
            throw probeError("PaperKit mouse test had no window geometry")
        }
        guard surface.isEditableForTesting,
              surface.mouseTargetsPaperKitForTesting(at: start),
              surface.paperViewIsFirstResponderForTesting
        else {
            throw probeError(
                "PaperKit native mouse drawing is not interactive: "
                    + surface.mouseHitDescriptionForTesting(at: start)
            )
        }
        guard surface.pointerModeForTesting == .selection else {
            throw probeError(
                "PaperKit did not start in native selection mode"
            )
        }
        surface.setPointerModeForTesting(.drawing)
        surface.activate()
        guard surface.pointerModeForTesting == .drawing else {
            throw probeError(
                "PaperKit refresh reset the selected pointer mode"
            )
        }
        surface.apply(rendererUpdate(isFinal: false))
        surface.apply(rendererUpdate(isFinal: true))
        guard surface.committedPenStrokeCountForTesting == 1,
              surface.pointerModeForTesting == .drawing,
              surface.drawingFrameForTesting.size
                  == expectedDrawingSize
        else {
            throw probeError(
                "PaperKit did not accept mouse mode and injected pen ink"
            )
        }
    }
#endif

    @MainActor
    private static func verifyTldrawPenInjection() async throws {
        let surface = TldrawRendererSurface()
        let visibleFrame = NSScreen.main?.visibleFrame
            ?? NSRect(x: 0, y: 0, width: 900, height: 700)
        let window = NSWindow(
            contentRect: NSRect(
                x: visibleFrame.minX + 20,
                y: visibleFrame.minY + 20,
                width: LabPaperLayout.minimumRendererSize.width,
                height: LabPaperLayout.minimumRendererSize.height
            ),
            styleMask: .borderless,
            backing: .buffered,
            defer: false
        )
        let frontmostProcessID =
            NSWorkspace.shared.frontmostApplication?.processIdentifier
        window.alphaValue = 0
        window.ignoresMouseEvents = true
        window.contentView = surface.view
        window.orderBack(nil)
        defer {
            window.orderOut(nil)
        }
        RunLoop.current.run(
            until: Date().addingTimeInterval(0.05)
        )
        guard !window.isKeyWindow,
              window.alphaValue == 0,
              frontmostProcessID == nil
                || NSWorkspace.shared.frontmostApplication?
                    .processIdentifier == frontmostProcessID
        else {
            throw probeError(
                "tldraw probe interrupted the active application"
            )
        }
        surface.view.frame = NSRect(
            origin: .zero,
            size: LabPaperLayout.minimumRendererSize
        )
        surface.updatePresentation(
            LabRendererPresentation(
                calibration: nil,
                calibrationActive: false,
                pagePriming: false,
                calibrationCorner: nil,
                message: nil
            )
        )
        surface.activate()
        surface.view.layoutSubtreeIfNeeded()
        guard surface.drawingFrameForTesting.size
            == expectedDrawingSize
        else {
            throw probeError(
                "tldraw did not expose a 1024x720 drawing area"
            )
        }
        surface.apply(
            rendererUpdate(
                strokeID: 41,
                sampleID: 6,
                isFinal: false
            )
        )
        surface.clear()
        for sampleID in 100..<132 {
            surface.apply(
                rendererUpdate(
                    strokeID: 42,
                    sampleID: UInt64(sampleID),
                    isFinal: false
                )
            )
        }
        surface.apply(rendererUpdate(isFinal: true))
        do {
            try await waitUntil("tldraw ready") {
                surface.isReadyForTesting
                    || surface.unavailableReason != nil
            }
        } catch {
            throw probeError(
                "tldraw readiness failed: "
                    + surface.debugStateForTesting
            )
        }
        if let unavailableReason = surface.unavailableReason {
            throw probeError(
                "tldraw failed to load: \(unavailableReason)"
            )
        }
        try await Task.sleep(nanoseconds: 200_000_000)
        guard await surface.iconsRenderForTesting(),
              surface.runtimeErrorCountForTesting == 0
        else {
            throw probeError(
                "tldraw icons did not resolve: "
                    + (await surface.iconDiagnosticsForTesting())
                    + " runtimeError="
                    + (
                        surface.lastRuntimeErrorForTesting
                            ?? "none"
                    )
                    + " shapes="
                    + (await surface.shapeSummaryForTesting())
                    + " lastOperation="
                    + surface.lastBridgeOperationForTesting
            )
        }
        guard await surface.bridgeDrawingSizeForTesting()
            == expectedDrawingSize
        else {
            throw probeError(
                "tldraw bridge did not preserve 1024x720 coordinates"
            )
        }
        try await waitUntil("tldraw pen bridge") {
            surface.queuedUpdateCountForTesting == 0
                && !surface.bridgeEvaluationInFlightForTesting
        }
        var rendered = false
        var lastShapeCount: Int?
        for _ in 0..<200 {
            lastShapeCount = await surface.shapeCountForTesting()
            if lastShapeCount == 1 {
                rendered = true
                break
            }
            try await Task.sleep(nanoseconds: 10_000_000)
        }
        guard rendered else {
            throw probeError(
                "tldraw queued pen shape or render acknowledgement failed: "
                    + surface.debugStateForTesting
                    + " shapeCount=\(String(describing: lastShapeCount))"
                    + " queued=\(surface.queuedUpdateCountForTesting)"
                    + " evaluations="
                    + "\(surface.penEvaluationCountForTesting)"
                    + " runtimeError="
                    + (
                        surface.lastRuntimeErrorForTesting
                            ?? "none"
                    )
                    + " shapes="
                    + (await surface.shapeSummaryForTesting())
                    + " lastOperation="
                    + surface.lastBridgeOperationForTesting
            )
        }
        guard surface.penEvaluationCountForTesting == 1,
              surface.maximumConcurrentEvaluationCountForTesting == 1,
              surface.queuedUpdateCountForTesting == 0
        else {
            throw probeError(
                "tldraw pen bridge did not coalesce and serialize updates: "
                    + "evaluations="
                    + "\(surface.penEvaluationCountForTesting) "
                    + "concurrent="
                    + "\(surface.maximumConcurrentEvaluationCountForTesting)"
                    + " queued="
                    + "\(surface.queuedUpdateCountForTesting)"
            )
        }
        guard await surface.lockAllShapesForTesting() else {
            throw probeError("tldraw test shape could not be locked")
        }
        surface.clear()
        var erased = false
        for _ in 0..<200 {
            if await surface.shapeCountForTesting() == 0 {
                erased = true
                break
            }
            try await Task.sleep(nanoseconds: 10_000_000)
        }
        guard erased else {
            throw probeError("tldraw erase left a locked shape behind")
        }

        guard await surface.setCameraForTesting(
            x: 120,
            y: 80,
            zoom: 1.5
        ) else {
            throw probeError("tldraw test camera could not be changed")
        }
        surface.apply(
            rendererUpdate(
                strokeID: 43,
                sampleID: 8,
                isFinal: false
            )
        )
        surface.apply(
            rendererUpdate(
                strokeID: 43,
                sampleID: 8,
                isFinal: true
            )
        )
        var cameraRendered = false
        for _ in 0..<200 {
            if await surface.shapeCountForTesting() == 1 {
                cameraRendered = true
                break
            }
            try await Task.sleep(nanoseconds: 10_000_000)
        }
        guard cameraRendered else {
            throw probeError(
                "tldraw camera-mapped stroke was not rendered"
            )
        }
        guard let screenOrigin =
            await surface.shapeViewportOriginForTesting(strokeID: 43)
        else {
            throw probeError(
                "tldraw injected shape had no screen origin"
            )
        }
        guard abs(screenOrigin.x - 204.8) < 0.01,
              abs(screenOrigin.y - 144) < 0.01
        else {
            throw probeError(
                "tldraw camera movement shifted injected pen input: "
                    + NSStringFromPoint(screenOrigin)
            )
        }
        try await verifyTldrawMousePrediction(surface)
    }

    @MainActor
    private static func verifyTldrawMousePrediction(
        _ surface: TldrawRendererSurface
    ) async throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        defer {
            try? FileManager.default.removeItem(at: directory)
        }
        let model = try probeModel(
            directory: directory,
            rendererMode: .tldraw
        )
        defer {
            model.stop()
        }
        model.onRenderUpdate = { update in
            surface.apply(update)
        }
        surface.onMouseStrokeEvent = { event in
            model.handleMouseStroke(event)
        }
        surface.clear()
        var renderedMouseSampleIDs: [UInt64] = []
        surface.onSamplesRendered = { samples, _ in
            renderedMouseSampleIDs.append(
                contentsOf: samples.map(\.id)
            )
        }
        let precisionSampleID = LabMouseIdentifier.base + 101
        let precisionSample = rendererUpdate(
            strokeID: LabMouseIdentifier.base + 100,
            sampleID: precisionSampleID,
            isFinal: false
        ).sourceSamples[0]
        surface.insertPendingSampleForTesting(precisionSample)
        guard await surface.emitRenderedSampleForTesting(
            sampleID: precisionSampleID
        ) else {
            throw probeError(
                "tldraw could not emit a high mouse sample acknowledgement"
            )
        }
        try await waitUntil("tldraw high mouse sample acknowledgement") {
            renderedMouseSampleIDs.contains(precisionSampleID)
        }

        for (phase, x, y) in [
            ("began", 0.2, 0.3),
            ("moved", 0.3, 0.35),
        ] {
            guard await surface.emitMouseEventForTesting(
                phase: phase,
                x: x,
                y: y
            ) else {
                throw probeError(
                    "tldraw mouse event did not reach Trace"
                )
            }
        }
        guard await surface.emitMouseEventForTesting(
            phase: "moved",
            x: 0.4,
            y: 0.4
        ) else {
            throw probeError(
                "tldraw mouse event did not reach Trace"
            )
        }

        var predictionVisible = false
        for _ in 0..<200 {
            if await surface.mousePredictionShapeCountForTesting() == 1 {
                predictionVisible = true
                break
            }
            try await Task.sleep(nanoseconds: 10_000_000)
        }
        guard predictionVisible,
              model.snapshot.processingMode == .predict,
              model.snapshot.predictionAlgorithm == .velocity
        else {
            throw probeError(
                "tldraw freehand mouse did not show Velocity prediction"
            )
        }
        guard let predictionOrigin =
            await surface.mousePredictionViewportOriginForTesting(
                strokeID: LabMouseIdentifier.base
            ),
            abs(predictionOrigin.x - 409.6) < 0.01,
            abs(predictionOrigin.y - 288) < 0.01
        else {
            throw probeError(
                "tldraw mouse prediction moved after camera changes"
            )
        }

        guard await surface.emitMouseEventForTesting(
            phase: "ended",
            x: 0.4,
            y: 0.4
        ) else {
            throw probeError("tldraw mouse-up did not reach Trace")
        }
        for _ in 0..<200 {
            if await surface.mousePredictionShapeCountForTesting() == 0 {
                surface.onMouseStrokeEvent = nil
                surface.onSamplesRendered = nil
                model.onRenderUpdate = nil
                return
            }
            try await Task.sleep(nanoseconds: 10_000_000)
        }
        throw probeError(
            "tldraw mouse prediction overlay survived mouse-up"
        )
    }

    private static func probeModel(
        directory: URL,
        rendererMode: LabRendererMode
    ) throws -> LabModel {
        try LabModel(
            configuration: LabConfiguration(
                logDirectory: directory,
                implementationID: "renderer-probe",
                paperProfile: "renderer-probe",
                replayURL: nil,
                replaySpeed: 1,
                quitAfterReplay: false,
                processingMode: .predict,
                interpolationAlgorithm: .circularArc,
                refinementAlgorithm: .smoothPath,
                predictionAlgorithm: .velocity,
                rendererMode: rendererMode
            ),
            transport: RendererProbeTransport()
        )
    }

    private static func rendererUpdate(
        strokeID: UInt64 = 42,
        sampleID: UInt64 = 7,
        isFinal: Bool
    ) -> LabRendererUpdate {
        let sample = RawPenSample(
            id: sampleID,
            strokeID: strokeID,
            sampleIndex: 0,
            eventCount: 0,
            page: nil,
            penTimestampMilliseconds: 1_000,
            receivedWallClockMilliseconds: 1_000,
            receivedUptimeNanoseconds:
                DispatchTime.now().uptimeNanoseconds,
            protocolClockDeltaMilliseconds: 0,
            interArrivalMilliseconds: nil,
            x: 0.2,
            y: 0.2,
            force: 426,
            pressure: 0.5,
            tiltX: 90,
            tiltY: 90,
            twist: 0,
            continuity: .first
        )
        let first = LabRenderPoint(
            render: RenderPoint(
                x: 0.2,
                y: 0.2,
                pressure: 0.5,
                kind: .raw,
                sourceSampleID: sample.id,
                connectsToPrevious: false
            ),
            normalized: UnitPoint(x: 0.2, y: 0.2)
        )
        let second = LabRenderPoint(
            render: RenderPoint(
                x: 0.6,
                y: 0.5,
                pressure: 0.6,
                kind: .raw,
                sourceSampleID: sample.id,
                connectsToPrevious: true
            ),
            normalized: UnitPoint(x: 0.6, y: 0.5)
        )
        return LabRendererUpdate(
            strokeID: strokeID,
            committed: isFinal ? [] : [first, second],
            predicted: [],
            replacement: nil,
            sourceSamples: isFinal ? [] : [sample],
            refinementReadyUptimeNanoseconds: nil,
            isFinal: isFinal
        )
    }

    private static func mouseSample(
        x: Double,
        y: Double,
        milliseconds: UInt64
    ) -> LabMouseSample {
        LabMouseSample(
            point: UnitPoint(x: x, y: y),
            pressure: nil,
            wallClockMilliseconds: milliseconds,
            uptimeNanoseconds: milliseconds * 1_000_000
        )
    }

    @MainActor
    private static func mouseEvent(
        type: NSEvent.EventType,
        location: NSPoint,
        window: NSWindow,
        eventNumber: Int
    ) throws -> NSEvent {
        guard let event = NSEvent.mouseEvent(
            with: type,
            location: location,
            modifierFlags: [],
            timestamp:
                ProcessInfo.processInfo.systemUptime
                    + TimeInterval(eventNumber) / 60,
            windowNumber: window.windowNumber,
            context: nil,
            eventNumber: eventNumber,
            clickCount: 1,
            pressure: 0
        ) else {
            throw probeError("could not synthesize a mouse event")
        }
        return event
    }

    private static func sessionRows(
        at url: URL
    ) throws -> [[String: Any]] {
        try String(contentsOf: url, encoding: .utf8)
            .split(separator: "\n")
            .map { line in
                guard let data = line.data(using: .utf8),
                      let row = try JSONSerialization.jsonObject(
                          with: data
                      ) as? [String: Any]
                else {
                    throw probeError(
                        "renderer session log contains invalid JSON"
                    )
                }
                return row
            }
    }

    @MainActor
    private static func waitUntil(
        _ description: String,
        _ condition: @MainActor @escaping () -> Bool
    ) async throws {
        for _ in 0..<500 {
            if condition() {
                return
            }
            try await Task.sleep(nanoseconds: 10_000_000)
        }
        throw probeError("renderer probe timed out waiting for \(description)")
    }

    private static func probeError(_ message: String) -> NSError {
        NSError(
            domain: "TraceRendererLabProbe",
            code: 1,
            userInfo: [NSLocalizedDescriptionKey: message]
        )
    }
}

final class RendererProbeTransport: NeoTransport {
    var eventHandler: ((NeoTransportEvent) -> Void)?
    let discoveredDevices: [NeoDevice] = []
    let connectionState: PenConnectionState = .idle

    func startDiscovery() {}
    func stopDiscovery() {}
    func connect(to deviceID: UUID) {}
    func disconnect() {}
    func requestStatus() {}
    func enableOnlineData() {}
    func setCurrentTime(milliseconds: UInt64) {}
    func setHoverEnabled(_ enabled: Bool) {}
    func setBeepEnabled(_ enabled: Bool) {}
    func setOfflineDataEnabled(_ enabled: Bool) {}
    func setAutoPowerOnEnabled(_ enabled: Bool) {}
    func setPenCapPowerOffEnabled(_ enabled: Bool) {}
    func setAutoPowerOffMinutes(_ minutes: UInt16) {}
    func setSensitivityStep(_ step: UInt8) {}
}
#endif
