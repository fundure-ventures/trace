#if DEBUG
import AppKit
import KeyboardShortcuts
import NeoInput
import NeoTransport
import TraceAppCore
import TraceCalibration
import TraceGeometry
import TraceVoice

@MainActor
enum TraceRetainedInkProbe {
    static func runOnboardingChecks() throws {
        try verifyOnboardingPresentation()
    }

    static func writeToolbarSnapshot(to url: URL) throws {
        try TraceBoardWindowController()
            .writeVoiceToolbarSnapshotForPreview(to: url)
    }

    static func writeOnboardingSnapshots(
        setupURL: URL?,
        calibrationURL: URL?
    ) throws {
        let board = TraceBoardWindowController()
        if let setupURL {
            board.prepareOnboardingForPreview(
                setupPreviewSnapshot(
                    dictationConfigured: false,
                    apiKeyState: .missing
                )
            )
            try board.writeSnapshot(
                to: setupURL,
                includeConfiguredToolbar: true
            )
        }
        if let calibrationURL {
            board.prepareOnboardingForPreview(
                calibrationPreviewSnapshot(),
                backgroundColor: TraceRGBAColor(
                    red: 0.10,
                    green: 0.18,
                    blue: 0.30
                )
            )
            try board.writeSnapshot(
                to: calibrationURL,
                includeConfiguredToolbar: true
            )
        }
        board.hideBoard()
    }

    static func runHardwareFreeChecks() throws {
        try verifyStatusItemPresentation()
        try verifyProductCanvasPolicy()
        try verifyCaptureTransitionEffects()
        try verifyAppSettings()
        try runGlobalShortcutChecks()
        try verifyOptionalSetupFlow()
        try verifyBlankViewportPersistenceAndCalibration()
        try verifyDocumentPresentationDefaults()
        try verifyDrawingFolderMigration()
        try verifyOpenWithImagePolicy()
        try verifyOpenFileLifecycle()
        try verifyPasteboardImageDecoding()
        try verifyTldrawSnapshotPersistence()
        try verifyDrawingHistoryIntegration()
        try verifyTimedTranscriptAnnotationIntegration()
        try verifyCompatiblePageCalibrationIntegration()
        try verifyTranscriptAnnotationRendering()
        try verifyProjectionPolicy()
        try verifyProductHoverPolicy()
        try verifyAutomaticCaptureDefaultSize()
        try verifyOnboardingPresentation()
        try verifyPageModes(
            TraceBoardWindowController(),
            verifiesInteractivePicker: false
        )
    }

    static func runGlobalShortcutChecks() throws {
        try verifyGlobalShortcuts()
        try verifyGlobalShortcutMenuPresentation()
        try verifyGlobalShortcutSetupUI()
    }

    static func runOpenFileChecks() throws {
        try verifyOpenWithImagePolicy()
        try verifyOpenFileLifecycle()
        try verifyOpenWithRegistration()
    }

    static func runGridSpacingBaselineCheck() throws {
        let board = TraceBoardWindowController()
        defer {
            board.hideBoard()
        }
        let spacing = board.gridSpacingPresentationForPreview
        guard spacing.focusedEditorRect.width > 0,
              spacing.focusedEditorRect.height > 0,
              spacing.focusedEditorRect.height < spacing.fieldHeight,
              spacing.focusedBaselineOffset
                > spacing.fieldHeight / 2,
              spacing.focusedBaselineOffset < spacing.fieldHeight,
              spacing.focusedGlyphCenterOffset < 0.5
        else {
            throw probeError(
                "focused grid spacing digits were not vertically centered: "
                    + "\(spacing)"
            )
        }
    }

    private static func verifyStatusItemPresentation() throws {
        let documentID = UUID()
        let expectedSymbols: [(TraceAppPhase, String)] = [
            (.waitingForPen, "pencil.tip"),
            (.armed, "pencil.tip"),
            (.capturing, "pencil.tip.crop.circle.fill"),
            (
                .annotating(documentID: documentID),
                "pencil.tip.crop.circle.fill"
            ),
        ]

        for (phase, expectedSymbol) in expectedSymbols {
            let actualSymbol = TraceStatusItemPresentation.symbolName(
                for: phase
            )
            guard actualSymbol == expectedSymbol else {
                throw probeError(
                    "status item phase \(phase) used \(actualSymbol) "
                        + "instead of \(expectedSymbol)"
                )
            }
        }
    }

    private static func verifyProductCanvasPolicy() throws {
        let legacyDebugEnvironment = [
            "TRACE_USE_NATIVE_CANVAS": "1",
        ]
        let legacyReleaseEnvironment = [
            "TRACE_ENABLE_TLDRAW_CANVAS": "0",
        ]
        guard TraceProductCanvasPolicy.usesTldraw(
                  environment: [:],
                  debugBuild: true
              ),
              TraceProductCanvasPolicy.usesTldraw(
                  environment: legacyDebugEnvironment,
                  debugBuild: true
              ),
              TraceProductCanvasPolicy.usesTldraw(
                  environment: [:],
                  debugBuild: false
              ),
              TraceProductCanvasPolicy.usesTldraw(
                  environment: legacyReleaseEnvironment,
                  debugBuild: false
              )
        else {
            throw probeError(
                "the product canvas still permits a native fallback"
            )
        }
    }

    private static func verifyCaptureTransitionEffects() throws {
        let toolbarAnimation =
            CaptureTransitionPolicy.toolbarAnimation()
        guard CaptureTransitionPolicy.duration == 0.90,
              CaptureTransitionPolicy.boardRevealProgress == 0.50,
              CaptureTransitionPolicy.toolbarRevealProgress == 0.58,
              CaptureTransitionPolicy.fragmentFunctionName
                  == "traceMonochromeFlashFragment",
              CaptureTransitionPolicy.toolbarStartYOffset == -20,
              CaptureTransitionPolicy.toolbarRevealDuration == 0.32,
              (toolbarAnimation.fromValue as? NSNumber)?
                  .doubleValue == -20,
              (toolbarAnimation.toValue as? NSNumber)?
                  .doubleValue == 0,
              toolbarAnimation.duration == 0.32
        else {
            throw probeError(
                "monochrome capture or toolbar motion changed"
            )
        }

        let source = NSRect(x: 140, y: 220, width: 900, height: 600)
        let defaultBoard = NSRect(
            x: 400,
            y: 300,
            width: 720,
            height: 480
        )
        let monochromeBoard = CaptureTransitionPolicy.finalBoardFrame(
            sourceFrame: source,
            defaultFrame: defaultBoard
        )
        guard monochromeBoard.origin == source.origin,
              monochromeBoard.size == defaultBoard.size
        else {
            throw probeError(
                "monochrome capture did not preserve source placement"
            )
        }

        let beforeReveal = CaptureTransitionPolicy.sample(
            progress: 0.4
        )
        let duringReveal = CaptureTransitionPolicy.sample(
            progress: 0.75
        )
        let completed = CaptureTransitionPolicy.sample(
            progress: 1
        )
        guard beforeReveal.boardOpacity == 0,
              beforeReveal.overlayOpacity == 1,
              !beforeReveal.revealsToolbar,
              duringReveal.boardOpacity > 0,
              duringReveal.overlayOpacity < 1,
              duringReveal.revealsToolbar,
              completed.boardOpacity == 1,
              completed.overlayOpacity == 0,
              BlankCanvasLoadingPolicy.rendererRevealDuration == 0.28,
              BlankCanvasLoadingPolicy.waitsForRenderer(
                  pageKind: .blank,
                  usesTldraw: true
              ),
              !BlankCanvasLoadingPolicy.waitsForRenderer(
                  pageKind: .screenshot,
                  usesTldraw: true
              ),
              !BlankCanvasLoadingPolicy.waitsForRenderer(
                  pageKind: .blank,
                  usesTldraw: false
              ),
              CaptureTransitionDiagnostics.fragmentFunctionNames
                  == ["traceMonochromeFlashFragment"],
              CaptureTransitionDiagnostics.canBuildEffect,
              CaptureTransitionDiagnostics.canExerciseEffect
        else {
            throw probeError(
                "capture or blank loading transition is unavailable"
            )
        }
    }

    static func run(
        board: TraceBoardWindowController,
        setCopyProgress: (Bool) -> Void
    ) throws {
        board.configureInvisibleProbeWindows()
        let probeWindows = board.invisibleProbeWindowState
        guard probeWindows.boardAlpha == 0,
              probeWindows.toolbarAlpha == 0,
              !probeWindows.boardIsKey,
              !probeWindows.toolbarIsKey
        else {
            throw probeError(
                "retained-ink probe windows were visible or key"
            )
        }
        try verifyCaptureTransitionEffects()
        try verifyAppSettings()
        try verifyGlobalShortcuts()
        try verifyDrawingFolderMigration()
        try verifyOpenWithImagePolicy()
        try verifyOpenFileLifecycle()
        try verifyOpenWithRegistration()
        try verifyPasteboardImageDecoding()
        try verifyTldrawSnapshotPersistence()
        try verifyDrawingHistoryIntegration()
        try verifyTimedTranscriptAnnotationIntegration()
        try verifyTranscriptAnnotationRendering()
        try verifyProjectionPolicy()
        try verifyProductHoverPolicy()
        try verifyPredictionSplitParity()
        try verifyVoicePackagePersistence()
        try verifyVoiceStateCoalescing(
            board,
            setCopyProgress: setCopyProgress
        )
        try verifyAutomaticCaptureDefaultSize()
        try verifyPageModes(board, verifiesInteractivePicker: true)

        let pixelWidth = 1_280
        let pixelHeight = 960
        let screenshot = try makeScreenshot(
            pixelWidth: pixelWidth,
            pixelHeight: pixelHeight
        )

        let historicalStrokeCount = 800
        var historicalStrokes: [TraceDrawingStroke] = []
        historicalStrokes.reserveCapacity(historicalStrokeCount)
        for strokeIndex in 0..<historicalStrokeCount {
            let row = strokeIndex % 80
            let column = strokeIndex / 80
            let startX = 0.03 + Double(column) * 0.08
            let startY = 0.02 + Double(row) * 0.012
            let points = (0..<8).map { pointIndex in
                TraceDrawingPoint(
                    x: startX + Double(pointIndex) * 0.007,
                    y: startY
                        + sin(Double(pointIndex) * 0.7) * 0.003,
                    pressure: 0.5,
                    tiltX: nil,
                    tiltY: nil,
                    twistDegrees: nil,
                    connectsToPrevious: pointIndex > 0
                )
            }

            historicalStrokes.append(
                TraceDrawingStroke(
                    id: UInt64(strokeIndex + 1),
                    color: .blue,
                    brush: .pen,
                    width: 5.25,
                    points: points
                )
            )
        }

        let now = Date()
        let document = TraceDrawingSession(
            manifest: TraceDrawingManifest(
                id: UUID(),
                createdAt: now,
                updatedAt: now,
                sourceApplicationName: "Retained Ink Probe",
                sourceWindowTitle: "Offscreen Fixture",
                screenshotFileName: "screenshot.png",
                screenshotPixelWidth: pixelWidth,
                screenshotPixelHeight: pixelHeight,
                sourceWindowBounds: TraceRect(
                    x: 0,
                    y: 0,
                    width: Double(pixelWidth),
                    height: Double(pixelHeight)
                ),
                strokes: historicalStrokes
            ),
            screenshot: screenshot,
            packageURL: URL(fileURLWithPath: "/dev/null")
        )
        try verifyRawScreenshotSurface(document)
        let toolState = TraceToolState()
        board.prepareDocumentForPreview(document, toolState: toolState)
        guard board.isBoardResizableForPreview else {
            throw probeError("drawing board did not become resizable")
        }
        try verifyGridInteraction(board, document: document)
        board.displayInkLayersForPreview()
        guard board.completedInkRenderCountForPreview > 0,
              board.activeInkRenderCountForPreview > 0
        else {
            throw probeError(
                "the offscreen fixture did not exercise both ink layers"
            )
        }

        let activeStrokeID = UInt64(historicalStrokeCount + 1)
        document.manifest.strokes.append(
            TraceDrawingStroke(
                id: activeStrokeID,
                color: toolState.color,
                brush: toolState.brush,
                width: toolState.width,
                points: (0..<8).map { pointIndex in
                    TraceDrawingPoint(
                        x: 0.08 + Double(pointIndex) * 0.004,
                        y: 0.5,
                        pressure: 0.5,
                        tiltX: nil,
                        tiltY: nil,
                        twistDegrees: nil,
                        connectsToPrevious: pointIndex > 0
                    )
                }
            )
        )
        board.apply(
            TraceAnnotationUpdate(
                strokeID: activeStrokeID,
                style: toolState,
                committed: [],
                predicted: [],
                replacement: nil,
                isFinal: false
            )
        )
        board.displayInkLayersForPreview()
        try verifyVisibleInkLayers(board)
        try verifyComposite(
            board,
            pixelWidth: pixelWidth,
            pixelHeight: pixelHeight
        )
        board.selectStrokesForPreview([1])
        board.displayInkLayersForPreview()
        guard board.completedInkHiddenForPreview else {
            throw probeError(
                "selection did not move editable strokes to the active layer"
            )
        }
        let selectionSnapshots = board.inkLayerSnapshotsForPreview()
        guard let selectionSnapshot = selectionSnapshots.active,
              inkCounts(selectionSnapshot).blue >= 4
        else {
            throw probeError(
                "selected historical ink was not visible on the active layer"
            )
        }
        board.selectStrokesForPreview([])
        board.displayInkLayersForPreview()
        guard !board.completedInkHiddenForPreview else {
            throw probeError(
                "completed ink did not return after selection cleared"
            )
        }
        board.updateVoiceState(.recording(transcribedChunks: 2))
        board.resetInkRenderCountsForPreview()

        let iterations = 240
        var renderTimes: [Double] = []
        renderTimes.reserveCapacity(iterations)
        for pointIndex in 1...iterations {
            let x = 0.1 + Double(pointIndex) * 0.0028
            let point = TraceDrawingPoint(
                x: x,
                y: 0.5 + sin(Double(pointIndex) * 0.12) * 0.08,
                pressure: 0.5,
                tiltX: nil,
                tiltY: nil,
                twistDegrees: nil,
                connectsToPrevious: true
            )
            document.manifest.strokes[
                document.manifest.strokes.count - 1
            ].points.append(point)
            let predicted = TraceDrawingPoint(
                x: min(0.99, x + 0.006),
                y: point.y,
                pressure: point.pressure,
                tiltX: nil,
                tiltY: nil,
                twistDegrees: nil,
                connectsToPrevious: true
            )
            let start = DispatchTime.now().uptimeNanoseconds
            board.apply(
                TraceAnnotationUpdate(
                    strokeID: activeStrokeID,
                    style: toolState,
                    committed: [point],
                    predicted: [predicted],
                    replacement: nil,
                    isFinal: false
                )
            )
            board.displayInkLayersForPreview()
            let elapsed = DispatchTime.now().uptimeNanoseconds - start
            renderTimes.append(Double(elapsed) / 1_000_000)
        }

        guard board.completedInkRenderCountForPreview == 0 else {
            throw probeError(
                "completed ink redrew during active samples"
            )
        }
        guard board.activeInkRenderCountForPreview == iterations else {
            throw probeError(
                "active ink rendered "
                    + "\(board.activeInkRenderCountForPreview) times, "
                    + "expected \(iterations)"
            )
        }

        let sortedTimes = renderTimes.sorted()
        let p50 = sortedTimes[(sortedTimes.count - 1) / 2]
        let p95 = sortedTimes[
            Int(Double(sortedTimes.count - 1) * 0.95)
        ]
        guard p95 < 16.7 else {
            throw probeError(
                String(
                    format: "active render p95 %.3f ms exceeds 16.7 ms",
                    p95
                )
            )
        }

        board.apply(
            TraceAnnotationUpdate(
                strokeID: activeStrokeID,
                style: toolState,
                committed: [],
                predicted: [],
                replacement: nil,
                isFinal: true
            )
        )
        board.displayInkLayersForPreview()
        guard board.completedInkRenderCountForPreview == 1 else {
            throw probeError(
                "pen-up should redraw completed ink exactly once"
            )
        }

        print(
            String(
                format: [
                    "retained-ink active p50=%.3f ms p95=%.3f ms",
                    "historical=%d samples=%d completed-redraws=%d",
                    "voice=recording",
                ].joined(separator: " "),
                p50,
                p95,
                historicalStrokeCount,
                iterations,
                board.completedInkRenderCountForPreview
            )
        )
        if let path = ProcessInfo.processInfo.environment[
            "TRACE_VOICE_UI_SNAPSHOT"
        ] {
            try board.writeVoiceToolbarSnapshotForPreview(
                to: URL(fileURLWithPath: path)
            )
        }
    }

    private static func verifyVisibleInkLayers(
        _ board: TraceBoardWindowController
    ) throws {
        let snapshots = board.inkLayerSnapshotsForPreview()
        guard let completedSnapshot = snapshots.completed,
              let activeSnapshot = snapshots.active
        else {
            throw probeError(
                "the ink-layer snapshots could not be rendered"
            )
        }
        let completedPixels = inkCounts(completedSnapshot)
        let activePixels = inkCounts(activeSnapshot)
        guard completedPixels.blue >= 4, activePixels.red >= 1 else {
            throw probeError(
                "the retained and active layers were not both visible "
                    + "(active red \(activePixels.red), retained blue "
                    + "\(completedPixels.blue))"
            )
        }
    }

    private static func verifyVoiceStateCoalescing(
        _ board: TraceBoardWindowController,
        setCopyProgress: (Bool) -> Void
    ) throws {
        board.updateVoiceState(.recording(transcribedChunks: 0))
        board.updateVoiceState(.idle)
        let idle = board.voicePresentationForPreview
        let idleIcons = board.toolbarIconMetricsForPreview
        guard idle.labelHidden,
              idle.label.isEmpty,
              idle.toggleSymbol == "mic.circle.fill",
              abs(idleIcons.voiceHeight - idleIcons.copyHeight)
                <= 1
        else {
            throw probeError(
                "idle microphone icon did not match Copy size"
            )
        }
        board.updateVoiceState(.recording(transcribedChunks: 2))
        let recording = board.voicePresentationForPreview
        guard recording.labelHidden,
              recording.toggleSymbol == "stop.circle.fill",
              isSoftRed(recording.toggleTint),
              isNeutral(recording.waveformColor)
        else {
            throw probeError(
                "recording voice UI did not use neutral wave and red stop circle"
            )
        }
        board.resetVoiceStateApplyCountForPreview()
        for _ in 0..<200 {
            board.updateVoiceState(.recording(transcribedChunks: 2))
        }
        guard board.voiceStateApplyCountForPreview == 0 else {
            throw probeError(
                "unchanged voice state rebuilt the toolbar"
            )
        }
        board.updateVoiceState(.paused(transcribedChunks: 2))
        let paused = board.voicePresentationForPreview
        guard board.voiceStateApplyCountForPreview == 1,
              paused.labelHidden,
              paused.toggleSymbol == "pause.circle.fill",
              paused.toggleTint.map(isNeutral) == true
        else {
            throw probeError(
                "paused voice UI did not use a distinct resume action"
            )
        }
        board.updateVoiceState(
            .transcribing(completedChunks: 2, pendingChunks: 1)
        )
        let finishing = board.voicePresentationForPreview
        guard !finishing.labelHidden,
              finishing.label == "Finishing 1"
        else {
            throw probeError(
                "meaningful voice processing status was hidden"
            )
        }
        board.updateVoiceState(.recording(transcribedChunks: 2))
        setCopyProgress(true)
        board.updateVoiceState(
            .transcribing(completedChunks: 2, pendingChunks: 1)
        )
        board.updateVoiceState(.ready)
        let quietCopy = board.voicePresentationForPreview
        guard quietCopy.labelHidden,
              quietCopy.label.isEmpty,
              quietCopy.toggleSymbol == "mic.circle.fill",
              !quietCopy.toggleEnabled,
              !quietCopy.copyEnabled
        else {
            throw probeError(
                "Copy exposed transient voice finalization states"
            )
        }
        setCopyProgress(false)
        board.updateVoiceState(.idle)
    }

    private static func isRed(_ color: NSColor?) -> Bool {
        guard let color = color?.usingColorSpace(.deviceRGB) else {
            return false
        }
        return color.redComponent > 0.7
            && color.redComponent > color.greenComponent * 1.5
            && color.redComponent > color.blueComponent * 1.5
    }

    private static func isSoftRed(_ color: NSColor?) -> Bool {
        guard isRed(color),
              let color = color?.usingColorSpace(.deviceRGB)
        else {
            return false
        }
        return color.alphaComponent >= 0.65
            && color.alphaComponent < 0.9
    }

    private static func isNeutral(_ color: NSColor) -> Bool {
        guard let color = color.usingColorSpace(.deviceRGB) else {
            return false
        }
        return abs(color.redComponent - color.greenComponent) < 0.02
            && abs(color.greenComponent - color.blueComponent) < 0.02
    }

    private static func verifyVoicePackagePersistence() throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        let packageURL = root.appendingPathComponent(
            "Voice.traceboard",
            isDirectory: true
        )
        try FileManager.default.createDirectory(
            at: packageURL,
            withIntermediateDirectories: true
        )
        defer {
            try? FileManager.default.removeItem(at: root)
        }
        let audioURL = root.appendingPathComponent("source.wav")
        let audio = Data([0x52, 0x49, 0x46, 0x46, 1, 2, 3, 4])
        try audio.write(to: audioURL)
        let now = Date()
        let session = TraceDrawingSession(
            manifest: TraceDrawingManifest(
                id: UUID(),
                createdAt: now,
                updatedAt: now,
                sourceApplicationName: "Voice Probe",
                sourceWindowTitle: "Voice",
                screenshotFileName: "screenshot.png",
                screenshotPixelWidth: 1,
                screenshotPixelHeight: 1,
                strokes: []
            ),
            screenshot: NSImage(size: NSSize(width: 1, height: 1)),
            packageURL: packageURL
        )
        try TraceDrawingStore().attachVoice(
            audioFileURL: audioURL,
            transcript: "Recorded annotation",
            to: session
        )
        let savedAudio = try Data(
            contentsOf: packageURL.appendingPathComponent("voice.wav")
        )
        let savedTranscript = try String(
            contentsOf: packageURL.appendingPathComponent(
                "transcript.txt"
            ),
            encoding: .utf8
        )
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let savedManifest = try decoder.decode(
            TraceDrawingManifest.self,
            from: Data(
                contentsOf: packageURL.appendingPathComponent(
                    "document.json"
                )
            )
        )
        guard savedAudio == audio,
              savedTranscript == "Recorded annotation",
              savedManifest.voiceRecordingFileName == "voice.wav",
              savedManifest.transcriptFileName == "transcript.txt"
        else {
            throw probeError(
                "traceboard did not retain voice.wav and transcript.txt"
            )
        }
    }

    private static func verifyPageModes(
        _ board: TraceBoardWindowController,
        verifiesInteractivePicker: Bool
    ) throws {
        let now = Date()
        let defaultsSuite = "TracePageModeProbe.\(UUID().uuidString)"
        guard let defaults = UserDefaults(suiteName: defaultsSuite) else {
            throw probeError("could not create blank-page preferences")
        }
        defer {
            defaults.removePersistentDomain(forName: defaultsSuite)
        }
        TracePageBackgroundPreferences.save(.blue, to: defaults)
        guard let reloadedDefaults = UserDefaults(
            suiteName: defaultsSuite
        ),
        TracePageBackgroundPreferences.load(from: reloadedDefaults) == .blue
        else {
            throw probeError(
                "blank-page background did not survive preferences reload"
            )
        }

        let temporaryDirectory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        defer {
            try? FileManager.default.removeItem(at: temporaryDirectory)
        }
        let store = TraceDrawingStore(
            directoryURL: temporaryDirectory
        )
        let createdBlank = try store.createBlank(
            size: NSSize(width: 160, height: 90),
            backingScale: 2,
            backgroundColor: .green
        )
        guard createdBlank.manifest.pageKind == .blank,
              createdBlank.manifest.screenshotPixelWidth == 320,
              createdBlank.manifest.screenshotPixelHeight == 180,
              createdBlank.manifest.backgroundColor == .green
        else {
            throw probeError(
                "blank page creation ignored color or 1:1 dimensions"
            )
        }
        let pageModel = TraceAppModel(
            drawingStore: store,
            defaults: defaults,
            transportFactory: { HardwareFreeNeoTransport() }
        )
        pageModel.prepareForDocumentCreationTesting()
        var projectActivations: [Bool] = []
        pageModel.onPresentDocument = {
            projectActivations.append($0.activatesProjectOutput)
        }
        pageModel.newBlankPage(
            size: NSSize(width: 200, height: 120),
            backingScale: 1
        )
        pageModel.openDrawing(from: createdBlank.packageURL)
        guard projectActivations == [true, false] else {
            throw probeError(
                "only new pages should activate Project output"
            )
        }
        pageModel.stop()
        createdBlank.manifest.pageKind = nil
        createdBlank.manifest.viewport = nil
        try store.save(createdBlank)
        let normalizedLegacy = try store.load(
            from: createdBlank.packageURL
        )
        guard normalizedLegacy.manifest.pageKind == .screenshot,
              normalizedLegacy.manifest.viewport
                  == TracePageViewport.full
        else {
            throw probeError(
                "legacy drawing did not normalize to a full screenshot"
            )
        }
        createdBlank.manifest.pageKind = .screenshot
        createdBlank.manifest.viewport = TraceRect(
            x: 0.49,
            y: 0.49,
            width: 1 / 160,
            height: 1 / 90
        )
        try store.save(createdBlank)
        let repairedCapture = try store.load(
            from: createdBlank.packageURL
        )
        guard repairedCapture.manifest.viewport
            == TracePageViewport.full
        else {
            throw probeError(
                "collapsed screenshot viewport was not repaired"
            )
        }
        let screenshotModel = TraceAppModel(
            drawingStore: store,
            defaults: defaults,
            transportFactory: { HardwareFreeNeoTransport() }
        )
        screenshotModel.prepareDocumentForHistoryTesting(repairedCapture)
        screenshotModel.updatePageBackground(.red)
        screenshotModel.stop()
        let reopenedRecoloredCapture = try store.load(
            from: repairedCapture.packageURL
        )
        guard repairedCapture.manifest.backgroundColor == .red,
              reopenedRecoloredCapture.manifest.backgroundColor == .red,
              TracePageBackgroundPreferences.load(from: defaults) == .red
        else {
            throw probeError(
                "screenshot background did not persist with the shared default "
                    + "document=\(String(describing: repairedCapture.manifest.backgroundColor)) "
                    + "reopened=\(String(describing: reopenedRecoloredCapture.manifest.backgroundColor)) "
                    + "blank=\(String(describing: TracePageBackgroundPreferences.load(from: defaults)))"
            )
        }
        let blank = TraceDrawingSession(
            manifest: TraceDrawingManifest(
                id: UUID(),
                createdAt: now,
                updatedAt: now,
                sourceApplicationName: "Trace",
                sourceWindowTitle: "Blank Page",
                screenshotFileName: "screenshot.png",
                screenshotPixelWidth: 320,
                screenshotPixelHeight: 180,
                sourceWindowBounds: TraceRect(
                    x: 0,
                    y: 0,
                    width: 160,
                    height: 90
                ),
                pageKind: .blank,
                backgroundColor: .green,
                viewport: TracePageViewport.full,
                strokes: []
            ),
            screenshot: NSImage(size: NSSize(width: 1, height: 1)),
            packageURL: URL(fileURLWithPath: "/dev/null")
        )
        var blankToolState = TraceToolState()
        blankToolState.gridStyle = .square
        board.prepareDocumentForPreview(
            blank,
            toolState: blankToolState
        )
        try verifyBackgroundControlLayout(board, visible: true)
        try verifyToolbarGroupLayout(board)
        var selectedBackground: TraceRGBAColor?
        board.onBackgroundColorChange = { color in
            selectedBackground = color
            blank.manifest.backgroundColor = color
        }
        if verifiesInteractivePicker {
            let picker = board.activateBackgroundPickerForPreview()
            guard picker.isActive,
                  !picker.panelVisible
            else {
                throw probeError(
                    "native background quick swatches did not open"
                )
            }
            board.focusBackgroundColorWellForPreview()
            guard board.backgroundPickerStateForPreview.isActive,
                  !board.backgroundPickerStateForPreview.panelVisible
            else {
                throw probeError(
                    "background well dismissed its own quick swatches"
                )
            }
            board.selectBackgroundQuickColorForPreview(.yellow)
            let quickPicker = board.backgroundPickerStateForPreview
            guard let quickBackground = selectedBackground,
                  quickBackground.red > 0.9,
                  quickBackground.green > 0.65,
                  quickBackground.blue < 0.2,
                  quickPicker.isActive,
                  !quickPicker.panelVisible
            else {
                throw probeError(
                    "quick background swatches closed after color selection "
                        + "active=\(quickPicker.isActive) "
                        + "panel=\(quickPicker.panelVisible)"
                )
            }
            board.focusToolbarControlForPreview()
            guard !board.backgroundPickerStateForPreview.isActive,
                  !board.backgroundPickerStateForPreview.panelVisible
            else {
                throw probeError(
                        "quick background swatches stayed open after toolbar focus"
                )
            }
            _ = board.activateBackgroundPickerForPreview()
            board.selectBackgroundColorForPreview(.blue)
            let fullPicker = board.backgroundPickerStateForPreview
            guard fullPicker.panelVisible,
                  let fullBackground = selectedBackground,
                  fullBackground.blue > fullBackground.red + 0.4
            else {
                throw probeError(
                    "full background picker did not stay open after selection "
                        + "active=\(fullPicker.isActive) "
                        + "panel=\(fullPicker.panelVisible) "
                        + "color=\(String(describing: selectedBackground))"
                )
            }
            board.focusCanvasForPreview()
            guard !board.backgroundPickerStateForPreview.isActive,
                  !board.backgroundPickerStateForPreview.panelVisible
            else {
                throw probeError(
                    "background picker stayed open after canvas focus"
                )
            }
            _ = board.activateBackgroundPickerForPreview()
            board.selectBackgroundColorForPreview(.red)
            board.apply(
                TraceAnnotationUpdate(
                    strokeID: 9_901,
                    style: blankToolState,
                    committed: [],
                    predicted: [],
                    replacement: nil,
                    isFinal: false
                )
            )
            guard !board.backgroundPickerStateForPreview.isActive,
                  !board.backgroundPickerStateForPreview.panelVisible
            else {
                throw probeError(
                    "background picker stayed open after Neo drawing"
                )
            }
            _ = board.activateBackgroundPickerForPreview()
            board.selectBackgroundColorForPreview(.blue)
            NotificationCenter.default.post(
                name: NSApplication.didResignActiveNotification,
                object: NSApp
            )
            guard !board.backgroundPickerStateForPreview.isActive,
                  !board.backgroundPickerStateForPreview.panelVisible
            else {
                throw probeError(
                    "background picker stayed open after app deactivation"
                )
            }
        } else {
            board.selectBackgroundQuickColorForPreview(.blue)
            board.dismissBackgroundPickerForPreview()
        }
        guard let selectedBackground,
              selectedBackground.blue > selectedBackground.red + 0.4,
              let recolored = board.compositeImageForPreview(),
              let recoloredData = recolored.tiffRepresentation,
              let recoloredRepresentation = NSBitmapImageRep(
                  data: recoloredData
              ),
              let recoloredCenter = recoloredRepresentation.colorAt(
                  x: recoloredRepresentation.pixelsWide / 2,
                  y: recoloredRepresentation.pixelsHigh / 2
              )?.usingColorSpace(.deviceRGB),
              recoloredCenter.blueComponent
                  > recoloredCenter.redComponent + 0.4
        else {
            throw probeError(
                "background picker color did not reach the canvas"
            )
        }
        blank.manifest.backgroundColor = .green
        try verifyProductHoverOverlay(board)
        try verifyDeferredResizePositioning(board)
        let blankCanvas = AnnotationCanvasView(
            frame: NSRect(x: 0, y: 0, width: 160, height: 90)
        )
        blankCanvas.setDocument(blank)
        guard let blankImage = blankCanvas.compositeImage(),
              let blankData = blankImage.tiffRepresentation,
              let blankRepresentation = NSBitmapImageRep(data: blankData)
        else {
            throw probeError("blank page could not be rendered")
        }
        let sampledBlankColor = blankRepresentation.colorAt(
            x: 160,
            y: 90
        )?.usingColorSpace(.deviceRGB)
        guard blankRepresentation.pixelsWide == 320,
              blankRepresentation.pixelsHigh == 180,
              let blankColor = sampledBlankColor,
              blankColor.greenComponent
                  > blankColor.redComponent + 0.5,
              blankColor.greenComponent
                  > blankColor.blueComponent + 0.2
        else {
            throw probeError(
                "blank page did not preserve its color and window dimensions "
                    + "size=\(blankRepresentation.pixelsWide)x"
                    + "\(blankRepresentation.pixelsHigh) "
                    + "rgba=\(String(describing: sampledBlankColor))"
            )
        }

        let screenshot = try twoToneScreenshot()
        let cropped = TraceDrawingSession(
            manifest: TraceDrawingManifest(
                id: UUID(),
                createdAt: now,
                updatedAt: now,
                sourceApplicationName: "Crop Probe",
                sourceWindowTitle: "Crop",
                screenshotFileName: "screenshot.png",
                screenshotPixelWidth: 400,
                screenshotPixelHeight: 200,
                sourceWindowBounds: TraceRect(
                    x: 0,
                    y: 0,
                    width: 200,
                    height: 100
                ),
                pageKind: .screenshot,
                viewport: TraceRect(
                    x: 0.5,
                    y: 0,
                    width: 0.5,
                    height: 0.5
                ),
                strokes: []
            ),
            screenshot: screenshot,
            packageURL: URL(fileURLWithPath: "/dev/null")
        )
        board.prepareDocumentForPreview(
            cropped,
            toolState: TraceToolState()
        )
        let reopenedCropSize = board.boardContentSizeForPreview
        guard abs(reopenedCropSize.width - 100) < 0.5,
              abs(reopenedCropSize.height - 50) < 0.5
        else {
            throw probeError(
                "reopened screenshot crop lost its saved viewport"
            )
        }
        let cropCanvas = AnnotationCanvasView(
            frame: NSRect(x: 0, y: 0, width: 100, height: 50)
        )
        cropCanvas.setDocument(cropped)
        guard let cropImage = cropCanvas.compositeImage(),
              let cropData = cropImage.tiffRepresentation,
              let cropRepresentation = NSBitmapImageRep(data: cropData),
              cropRepresentation.pixelsWide == 200,
              cropRepresentation.pixelsHigh == 100,
              let cropColor = cropRepresentation.colorAt(
                  x: 100,
                  y: 50
              )?.usingColorSpace(.deviceRGB),
              cropColor.greenComponent > 0.6,
              cropColor.redComponent < 0.2,
              cropColor.blueComponent < 0.2
        else {
            throw probeError(
                "screenshot resize scaled instead of cropping source pixels"
            )
        }
        let cropSurface = ScreenshotGridSurfaceView(
            frame: NSRect(x: 0, y: 0, width: 100, height: 50)
        )
        cropSurface.setDocument(cropped)
        guard let surfaceRepresentation =
            cropSurface.bitmapImageRepForCachingDisplay(
                in: cropSurface.bounds
            )
        else {
            throw probeError("could not render screenshot crop surface")
        }
        cropSurface.cacheDisplay(
            in: cropSurface.bounds,
            to: surfaceRepresentation
        )
        let sampledSurfaceColor = surfaceRepresentation.colorAt(
            x: surfaceRepresentation.pixelsWide / 2,
            y: surfaceRepresentation.pixelsHigh / 2
        )
        guard let surfaceColor = sampledSurfaceColor?
            .usingColorSpace(.deviceRGB),
        surfaceColor.greenComponent > 0.6,
        surfaceColor.redComponent < 0.2,
        surfaceColor.blueComponent < 0.2
        else {
            throw probeError(
                "live screenshot surface did not match exported crop "
                    + "rgba=\(String(describing: sampledSurfaceColor))"
            )
        }

        cropped.manifest.viewport = TraceRect(
            x: 0.125,
            y: 0.15,
            width: 0.5,
            height: 0.5
        )
        cropSurface.setDocument(cropped)
        let metalGeometry = cropSurface.metalGridGeometryForTesting
        guard abs(metalGeometry.sourcePointSize.width - 200) < 0.01,
              abs(metalGeometry.sourcePointSize.height - 100) < 0.01,
              abs(metalGeometry.viewport.x - 0.125) < 0.001,
              abs(metalGeometry.viewport.y - 0.15) < 0.001,
              abs(metalGeometry.viewport.width - 0.5) < 0.001,
              abs(metalGeometry.viewport.height - 0.5) < 0.001
        else {
            throw probeError(
                "Metal grid lost cropped source geometry"
            )
        }
    }

    private static func verifyDeferredResizePositioning(
        _ board: TraceBoardWindowController
    ) throws {
        board.showToolbarForResizePreview()
        RunLoop.current.run(
            until: Date().addingTimeInterval(0.02)
        )
        let size = board.boardContentSizeForPreview
        board.resetToolbarPositionCountForPreview()
        for _ in 0..<40 {
            board.windowDidResize(
                Notification(name: NSWindow.didResizeNotification)
            )
        }

        guard board.toolbarPositionCountForPreview == 0 else {
            throw probeError(
                "window resize synchronously repositioned AppKit windows"
            )
        }
        RunLoop.current.run(
            until: Date().addingTimeInterval(0.02)
        )
        guard board.toolbarPositionCountForPreview <= 1,
              board.boardContentSizeForPreview == size
        else {
            throw probeError(
                "deferred toolbar positioning changed the drawing frame "
                    + "positions=\(board.toolbarPositionCountForPreview) "
                    + "size=\(board.boardContentSizeForPreview) "
                    + "expected=\(size)"
            )
        }
    }

    private static func verifyNativeResizeTracking(
        _ board: TraceBoardWindowController
    ) throws {
        board.showToolbarForResizePreview()
        RunLoop.current.run(
            until: Date().addingTimeInterval(0.02)
        )
        board.resetToolbarPositionCountForPreview()
        let nativeResize = board.performNativeResizeForPreview()
        RunLoop.current.run(
            until: Date().addingTimeInterval(0.05)
        )
        guard nativeResize.after.width > nativeResize.before.width,
              nativeResize.after.height >= nativeResize.before.height,
              board.toolbarPositionCountForPreview <= 2,
              abs(board.toolbarVerticalGapForPreview - 10) < 0.5
        else {
            throw probeError(
                "native resize regression failed "
                    + "size=\(nativeResize) "
                    + "positions=\(board.toolbarPositionCountForPreview) "
                    + "gap=\(board.toolbarVerticalGapForPreview)"
            )
        }
    }

    private static func verifyBackgroundControlLayout(
        _ board: TraceBoardWindowController,
        visible: Bool
    ) throws {
        let layout = board.backgroundControlLayoutForPreview
        let swatch = board.backgroundSwatchPresentationForPreview
        guard layout.backgroundIndex == 0,
              layout.gridIndex == 1,
              layout.separatorIndex == 2,
              layout.colorsIndex == 3,
              layout.backgroundHidden == !visible,
              !layout.separatorHidden
        else {
            throw probeError(
                "background control is not the leading toolbar group"
            )
        }
        guard swatch.size.width >= 26,
              swatch.size.height >= 20,
              swatch.usesQuickSwatches
        else {
            throw probeError(
                "background color well did not use native quick swatches "
                    + "size=\(swatch.size) quick=\(swatch.usesQuickSwatches) "
                    + "color=\(swatch.color)"
            )
        }
    }

    private static func verifyToolbarGroupLayout(
        _ board: TraceBoardWindowController
    ) throws {
        let layout = board.toolbarGroupLayoutForPreview
        board.updateVoiceState(.recording(transcribedChunks: 0))
        let icons = board.toolbarIconMetricsForPreview
        let tools = board.drawingToolPresentationForPreview
        let accents = board.controlAccentPresentationForPreview
        let spacing = board.gridSpacingPresentationForPreview
        let sizing = board.toolbarSizingForPreview
        let gridSelector = board.gridSelectorPresentationForPreview
        guard layout.contentCenterOffset < 0.5,
              layout.gridAccessoryGap >= 5,
              layout.gridDividerVisible,
              layout.toolSeparatorIndex == 4,
              layout.brushIndex == 5,
              layout.strokeIndex == 6,
              layout.voiceSeparatorIndex == 1,
              layout.voiceIndex == 0,
              layout.recordingSeparatorIndex == 1,
              layout.copyIndex == 2,
              layout.actionSeparatorIndex == 3,
              layout.closeIndex == 4,
              layout.separatorNeighborGaps.count == 10,
              (
                  layout.separatorNeighborGaps.allSatisfy {
                      (9.5...10.5).contains($0)
                  }
              )
        else {
            throw probeError(
                "toolbar groups are not packed in the requested order "
                    + "center=\(layout.contentCenterOffset) "
                    + "voice-divider=\(String(describing: layout.voiceSeparatorIndex)) "
                    + "grid-divider=\(layout.gridDividerVisible) "
                    + "separator-gaps=\(layout.separatorNeighborGaps)"
            )
        }
        guard icons.brushHeights.count == 4,
              icons.gridHeights.count == 5,
              icons.voiceHeight >= 18,
              icons.copyHeight >= 20,
              icons.closeHeight >= 15,
              icons.swatchDiameter == 20,
              icons.brushControlHeight >= icons.swatchDiameter,
              icons.brushHeights.allSatisfy({
                  $0 >= icons.swatchDiameter * 0.95
                    && $0 <= icons.swatchDiameter * 1.10
              }),
              icons.gridHeights.allSatisfy({
                  (13...17).contains($0)
              }),
              icons.sliderControlSize
                == NSControl.ControlSize.small.rawValue,
              icons.sliderCellType == "NSSliderCell",
              icons.sliderKnobSize.width <= icons.swatchDiameter * 1.05,
              icons.sliderKnobSize.height <= icons.swatchDiameter * 1.05,
              icons.sliderKnobSize.width >= icons.swatchDiameter * 0.75,
              icons.sliderKnobSize.height >= icons.swatchDiameter * 0.75
        else {
            throw probeError(
                "toolbar controls did not match production scale "
                    + "voice=\(icons.voiceHeight) "
                    + "copy=\(icons.copyHeight) "
                    + "close=\(icons.closeHeight) "
                    + "brush=\(icons.brushHeights) "
                    + "grid=\(icons.gridHeights) "
                    + "brush-control=\(icons.brushControlHeight) "
                    + "swatch=\(icons.swatchDiameter) "
                    + "slider-size=\(icons.sliderControlSize) "
                    + "slider=\(icons.sliderCellType) "
                    + "\(icons.sliderKnobSize)"
            )
        }
        guard gridSelector.isPopUp,
              gridSelector.displaysSelectedImageOnly,
              (38...48).contains(gridSelector.controlWidth),
              gridSelector.accessibilityLabel == "Canvas grid",
              gridSelector.selectedTitle == "No grid",
              gridSelector.selectedStyle == .none,
              gridSelector.menuTitles == [
                  "No grid",
                  "Dots",
                  "Square",
                  "Horizontal",
                  "Vertical",
              ],
              gridSelector.menuImageCount == 5
        else {
            throw probeError(
                "Grid did not use one iconized native selector: "
                    + "\(gridSelector)"
            )
        }
        var selectedGridStyle: TraceGridStyle?
        board.onToolChange = { state in
            selectedGridStyle = state.gridStyle
        }
        board.selectGridStyleForPreview(.horizontal)
        let selectedGrid = board.gridSelectorPresentationForPreview
        let selectedGridSizing = board.toolbarSizingForPreview
        guard selectedGridStyle == .horizontal,
              selectedGrid.selectedTitle == "Horizontal",
              selectedGrid.selectedStyle == .horizontal,
              selectedGridSizing.active.spacingVisible
        else {
            throw probeError(
                "Grid selector did not apply its selected option"
            )
        }
        guard tools.selectedSegment == 1,
              tools.toolTips == [
                  "Select (V or hold ⌘)",
                  "Pen (D)",
                  "Highlighter (H)",
                  "Rectangle (R)",
              ],
              tools.closeToolTip == "Close trace (⌘W)"
        else {
            throw probeError(
                "drawing tools do not expose their shortcuts"
            )
        }
        guard accents.brush,
              accents.grid,
              !accents.slider
        else {
            throw probeError(
                "toolbar accents did not match production"
            )
        }
        guard spacing.unitText == nil,
              spacing.accessibilityLabel == "Grid spacing in points",
              spacing.backgroundAlpha == 0,
              (0.09...0.11).contains(spacing.hoverBackgroundAlpha),
              spacing.focusBackgroundAlpha
                == spacing.hoverBackgroundAlpha,
              spacing.focusBorderAlpha >= 0.85,
              spacing.focusBorderWidth == 1,
              spacing.disabledBackgroundAlpha == 0,
              spacing.disabledTextAlpha >= 0.45,
              spacing.textAlpha >= 0.84,
              !spacing.drawsBackground,
              !spacing.isBezeled,
              spacing.focusRingType == .default,
              spacing.isEditable,
              spacing.isSelectable,
              abs(spacing.fontSize - 11) < 0.5,
              spacing.baselineOffset > 0,
              spacing.baselineOffset < spacing.fieldHeight
        else {
            throw probeError(
                "grid spacing input did not preserve its quiet editable "
                    + "surface contract: \(spacing)"
            )
        }
        try runGridSpacingBaselineCheck()
        guard spacing.gridControlHeight > 0,
              abs(
                  spacing.fieldHeight - spacing.gridControlHeight
              ) < 0.5
        else {
            throw probeError(
                "grid spacing input height did not match grid controls "
                    + "field=\(spacing.fieldHeight) "
                    + "controls=\(spacing.gridControlHeight)"
            )
        }
        guard abs(
                  sizing.active.toolbarWidth
                    - sizing.inactive.toolbarWidth
              ) < 0.5,
              abs(
                  sizing.active.gridCenterX
                    - sizing.inactive.gridCenterX
              ) < 0.5,
              (10...14).contains(sizing.active.leftInset),
              (10...14).contains(sizing.active.rightInset),
              (10...14).contains(sizing.inactive.leftInset),
              (10...14).contains(sizing.inactive.rightInset),
              sizing.active.gridLeftReserve < 0.5,
              sizing.inactive.gridLeftReserve < 0.5,
              sizing.active.gridRightReserve >= 32,
              abs(
                  sizing.active.gridRightReserve
                    - sizing.inactive.gridRightReserve
              ) < 0.5,
              (
                  sizing.active.backgroundToGridGap.map {
                      (6...10).contains($0)
                  } == true
              ),
              (
                  sizing.inactive.backgroundToGridGap.map {
                      (6...10).contains($0)
                  } == true
              ),
              sizing.active.gridToColorsGap >= 24,
              sizing.active.gridToColorsGap <= 26,
              abs(
                  sizing.active.gridToColorsGap
                    - sizing.inactive.gridToColorsGap
              ) < 0.5,
              sizing.active.spacingVisible,
              !sizing.inactive.spacingVisible
        else {
            throw probeError(
                "toolbar did not hug content with a stable Grid reserve "
                    + "inactive=\(sizing.inactive) "
                    + "active=\(sizing.active)"
            )
        }
        board.setActionHoverForPreview(true)
        let hoveredActions = board.actionHoverPresentationForPreview
        guard hoveredActions.brushAttached,
              hoveredActions.brushAlpha >= 0.08,
              hoveredActions.micAlpha >= 0.08,
              hoveredActions.copyAlpha >= 0.08,
              hoveredActions.closeAlpha >= 0.08,
              hoveredActions.cornerRadii.allSatisfy({
                  $0 >= 6
              })
        else {
            throw probeError(
                "toolbar actions did not expose rounded hover feedback"
            )
        }
        board.setColorSwatchHoverForPreview(index: 1, hovered: true)
        guard let hoveredSwatch =
                  board.colorSwatchPresentationForPreview(index: 1),
              !hoveredSwatch.isSelected,
              hoveredSwatch.borderWidth >= 2.5,
              hoveredSwatch.borderAlpha >= 0.95
        else {
            throw probeError(
                "drawing color swatch did not expose its white hover ring"
            )
        }
        board.setActionHoverForPreview(false)
        board.setTemporaryDrawingToolForPreview(.select)
        guard board.drawingToolPresentationForPreview
                .selectedSegment == 0
        else {
            throw probeError(
                "temporary Select was not reflected in the toolbar"
            )
        }
        board.setTemporaryDrawingToolForPreview(nil)
        guard board.drawingToolPresentationForPreview
                .selectedSegment == 1
        else {
            throw probeError(
                "toolbar did not restore the persistent drawing tool"
            )
        }
    }

    private static func verifyProductHoverOverlay(
        _ board: TraceBoardWindowController
    ) throws {
        let initial = board.hoverStateForPreview
        let surfaceWidth = max(
            1,
            Double(board.hoverViewForPreview.bounds.width)
        )
        let update = TraceHoverUpdate(
            point: TracePoint(
                x: 0.5 + 2 / surfaceWidth,
                y: 0.5
            ),
            color: .red
        )
        board.updateHover(update)
        board.displayHoverForPreview()
        let visible = board.hoverStateForPreview
        guard visible.point == update.point,
              abs(
                  visible.diameter - TraceProductHoverPolicy.diameter
              ) < 0.000_001,
              abs(visible.opacity - 0.2) < 0.000_001,
              visible.renderCount > initial.renderCount,
              try alphaPixelCount(in: board.hoverViewForPreview) > 0
        else {
            throw probeError(
                "product hover pointer did not render at selected width"
            )
        }
        if surfaceWidth > 500 {
            guard try hoverLensLuminanceRange(
                in: board.hoverViewForPreview,
                at: update.point
            ) > 0.12 else {
                throw probeError(
                    "product hover lens did not magnify background detail"
                )
            }
        }
        if board.hoverViewForPreview.bounds.width > 500,
           let path = ProcessInfo.processInfo.environment[
               "TRACE_PRODUCT_HOVER_SNAPSHOT"
           ]
        {
            try board.writeSnapshot(
                to: URL(fileURLWithPath: path)
            )
        }

        board.updateHover(
            TraceHoverUpdate(
                point: TracePoint(
                    x: update.point.x + 0.5 / surfaceWidth,
                    y: update.point.y
                ),
                color: update.color
            )
        )
        board.displayHoverForPreview()
        let jittered = board.hoverStateForPreview
        guard jittered.point == update.point else {
            throw probeError(
                "product hover rendered one-pixel hand jitter "
                    + "point=\(String(describing: jittered.point))"
            )
        }

        let movedPoint = TracePoint(
            x: update.point.x + 2 / surfaceWidth,
            y: update.point.y
        )
        board.updateHover(
            TraceHoverUpdate(
                point: movedPoint,
                color: update.color
            )
        )
        guard board.hoverStateForPreview.point == movedPoint else {
            throw probeError(
                "product hover suppressed intentional movement "
                    + "size=\(board.hoverViewForPreview.bounds.size) "
                    + "scale=\(board.hoverViewForPreview.window?.backingScaleFactor ?? 0) "
                    + "point=\(String(describing: board.hoverStateForPreview.point))"
            )
        }
        board.updateHover(nil)
        board.displayHoverForPreview()
        guard board.hoverStateForPreview.point == nil,
              try alphaPixelCount(in: board.hoverViewForPreview) == 0
        else {
            throw probeError("product hover pointer did not clear")
        }
    }

    private static func alphaPixelCount(in view: NSView) throws -> Int {
        guard let representation = view.bitmapImageRepForCachingDisplay(
            in: view.bounds
        ) else {
            throw probeError("could not render product hover pointer")
        }
        view.cacheDisplay(in: view.bounds, to: representation)
        var count = 0
        for y in 0..<representation.pixelsHigh {
            for x in 0..<representation.pixelsWide {
                guard let color = representation.colorAt(x: x, y: y) else {
                    continue
                }
                if color.alphaComponent > 0.05 {
                    count += 1
                }
            }
        }
        return count
    }

    private static func hoverLensLuminanceRange(
        in view: NSView,
        at point: TracePoint
    ) throws -> Double {
        guard let representation = view.bitmapImageRepForCachingDisplay(
            in: view.bounds
        ) else {
            throw probeError("could not inspect product hover lens")
        }
        view.cacheDisplay(in: view.bounds, to: representation)
        let centerX = Int(point.x * Double(representation.pixelsWide))
        let centerY = Int(point.y * Double(representation.pixelsHigh))
        let radius = max(
            2,
            Int(
                3 * Double(representation.pixelsWide)
                    / max(1, Double(view.bounds.width))
            )
        )
        var minimum = 1.0
        var maximum = 0.0
        for y in max(0, centerY - radius)..<min(
            representation.pixelsHigh,
            centerY + radius + 1
        ) {
            for x in max(0, centerX - radius)..<min(
                representation.pixelsWide,
                centerX + radius + 1
            ) {
                guard let color = representation.colorAt(x: x, y: y)?
                    .usingColorSpace(.deviceRGB)
                else {
                    continue
                }
                let luminance = color.redComponent * 0.2126
                    + color.greenComponent * 0.7152
                    + color.blueComponent * 0.0722
                minimum = min(minimum, luminance)
                maximum = max(maximum, luminance)
            }
        }
        return maximum - minimum
    }

    private static func twoToneScreenshot() throws -> NSImage {
        let size = NSSize(width: 400, height: 200)
        guard let representation = NSBitmapImageRep(
            bitmapDataPlanes: nil,
            pixelsWide: 400,
            pixelsHigh: 200,
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
            throw probeError("could not create crop fixture")
        }
        representation.size = size
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = context
        NSColor.red.setFill()
        NSRect(x: 0, y: 0, width: 200, height: 100).fill()
        NSColor.blue.setFill()
        NSRect(x: 200, y: 0, width: 200, height: 100).fill()
        NSColor.yellow.setFill()
        NSRect(x: 0, y: 100, width: 200, height: 100).fill()
        NSColor.green.setFill()
        NSRect(x: 200, y: 100, width: 200, height: 100).fill()
        context.flushGraphics()
        NSGraphicsContext.restoreGraphicsState()
        let image = NSImage(size: size)
        image.addRepresentation(representation)
        return image
    }

    private static func makeScreenshot(
        pixelWidth: Int,
        pixelHeight: Int
    ) throws -> NSImage {
        guard let representation = NSBitmapImageRep(
            bitmapDataPlanes: nil,
            pixelsWide: pixelWidth,
            pixelsHigh: pixelHeight,
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
            throw probeError("could not create the screenshot fixture")
        }
        let size = NSSize(width: pixelWidth, height: pixelHeight)
        representation.size = size
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = context
        NSColor(
            calibratedRed: 0.18,
            green: 0.27,
            blue: 0.36,
            alpha: 1
        ).setFill()
        NSBezierPath(rect: NSRect(origin: .zero, size: size)).fill()
        for row in -4...4 {
            for column in -4...4 where (row + column).isMultiple(of: 2) {
                NSColor.white.withAlphaComponent(0.58).setFill()
                NSRect(
                    x: CGFloat(pixelWidth / 2 + column * 4),
                    y: CGFloat(pixelHeight / 2 + row * 4),
                    width: 3,
                    height: 3
                ).fill()
            }
        }
        context.flushGraphics()
        NSGraphicsContext.restoreGraphicsState()
        let image = NSImage(size: size)
        image.addRepresentation(representation)
        return image
    }

    private static func verifyRawScreenshotSurface(
        _ document: TraceDrawingSession
    ) throws {
        let size = document.screenshot.size
        let surface = ScreenshotGridSurfaceView(
            frame: NSRect(origin: .zero, size: size)
        )
        surface.setDocument(document)
        surface.layoutSubtreeIfNeeded()
        guard let rendered = surface.bitmapImageRepForCachingDisplay(
            in: surface.bounds
        ),
        let source = document.screenshot.representations.first(
            where: { $0 is NSBitmapImageRep }
        ) as? NSBitmapImageRep
        else {
            throw probeError("could not inspect the raw screenshot surface")
        }
        surface.cacheDisplay(in: surface.bounds, to: rendered)
        let x = min(source.pixelsWide, rendered.pixelsWide) / 2
        let y = min(source.pixelsHigh, rendered.pixelsHigh) / 2
        guard let sourceColor = source.colorAt(x: x, y: y)?
            .usingColorSpace(.deviceRGB),
            let renderedColor = rendered.colorAt(x: x, y: y)?
                .usingColorSpace(.deviceRGB),
            abs(sourceColor.redComponent - renderedColor.redComponent) < 0.02,
            abs(sourceColor.greenComponent - renderedColor.greenComponent)
                < 0.02,
            abs(sourceColor.blueComponent - renderedColor.blueComponent)
                < 0.02
        else {
            throw probeError(
                "the no-grid surface altered the captured screenshot"
            )
        }
        surface.setDisplaysScreenshot(false)
        guard !surface.displaysScreenshotForTesting,
              surface.hitTest(
                  NSPoint(
                      x: surface.bounds.midX,
                      y: surface.bounds.midY
                  )
              ) == nil
        else {
            throw probeError(
                "the native grid overlay blocked tldraw interaction"
            )
        }
        guard let overlay = surface.bitmapImageRepForCachingDisplay(
                  in: surface.bounds
              )
        else {
            throw probeError(
                "could not inspect the native grid overlay"
            )
        }
        surface.cacheDisplay(in: surface.bounds, to: overlay)
        guard (
            overlay.colorAt(x: x, y: y)?.alphaComponent ?? 1
        ) < 0.02
        else {
            throw probeError(
                "the native grid overlay retained the screenshot"
            )
        }
    }

    private static func verifyGridInteraction(
        _ board: TraceBoardWindowController,
        document: TraceDrawingSession
    ) throws {
        let unloadedSurface = ScreenshotGridSurfaceView(
            frame: NSRect(x: 0, y: 0, width: 100, height: 50)
        )
        unloadedSurface.setGrid(style: .square, spacingPoints: 12)
        let unloadedState =
            unloadedSurface.configuredGridStateForTesting
        guard unloadedState.style == .square,
              unloadedState.spacingPoints == 12,
              !unloadedState.textureReady,
              unloadedState.metalHidden
        else {
            throw probeError(
                "grid state was not deferred before document texture"
            )
        }
        let unloadedWindow = NSWindow(
            contentRect: unloadedSurface.bounds,
            styleMask: [.borderless],
            backing: .buffered,
            defer: false
        )
        unloadedWindow.alphaValue = 0
        unloadedWindow.ignoresMouseEvents = true
        unloadedWindow.contentView = unloadedSurface
        unloadedWindow.orderBack(nil)
        unloadedSurface.setDocument(document)
        RunLoop.current.run(
            until: Date().addingTimeInterval(0.08)
        )
        unloadedSurface.flushScheduledMetalDrawForTesting()
        let appliedState = unloadedSurface.submittedGridStateForTesting
        let loadedState = unloadedSurface.configuredGridStateForTesting
        unloadedWindow.orderOut(nil)
        guard appliedState?.style == .square,
              appliedState?.spacingPoints == 12,
              loadedState.textureReady,
              !loadedState.metalHidden
        else {
            throw probeError(
                "deferred grid state was not applied after document texture"
            )
        }
        let wideSurface = ScreenshotGridSurfaceView(
            frame: NSRect(x: 0, y: 0, width: 180, height: 50)
        )
        wideSurface.setGrid(style: .dots, spacingPoints: 8)
        let wideWindow = NSWindow(
            contentRect: wideSurface.bounds,
            styleMask: [.borderless],
            backing: .buffered,
            defer: false
        )
        wideWindow.alphaValue = 0
        wideWindow.ignoresMouseEvents = true
        wideWindow.contentView = wideSurface
        wideWindow.orderBack(nil)
        wideSurface.setDocument(document)
        RunLoop.current.run(
            until: Date().addingTimeInterval(0.08)
        )
        wideSurface.flushScheduledMetalDrawForTesting()
        let wideGeometry = wideSurface.submittedGridGeometryForTesting
        let usesViewPointGrid =
            wideSurface.usesIsotropicViewPointGridForTesting
        wideWindow.orderOut(nil)
        guard usesViewPointGrid,
              let wideGeometry,
              abs(wideGeometry.viewPointSize.width - 180) < 0.01,
              abs(wideGeometry.viewPointSize.height - 50) < 0.01,
              abs(
                  wideGeometry.horizontalSpacing
                    - wideGeometry.verticalSpacing
              ) < 0.001,
              abs(wideGeometry.horizontalSpacing - 8) < 0.001,
              abs(wideGeometry.dotDiameter - 1) < 0.001,
              abs(wideGeometry.lineWidth - 1) < 0.001
        else {
            throw probeError(
                "wide Metal grid did not keep isotropic view-point geometry "
                    + "shader=\(usesViewPointGrid) "
                    + "\(String(describing: wideGeometry))"
            )
        }
        for style in [
            TraceGridStyle.dots,
            .square,
            .horizontal,
            .vertical,
        ] {
            let lightGrid = TraceGridContrastPolicy.gridColor(
                for: .white,
                style: style
            ).usingColorSpace(.deviceRGB)
            let darkGrid = TraceGridContrastPolicy.gridColor(
                for: .black,
                style: style
            ).usingColorSpace(.deviceRGB)
            guard let lightGrid,
                  let darkGrid,
                  lightGrid.redComponent < 0.1,
                  darkGrid.redComponent > 0.9,
                  abs(lightGrid.alphaComponent - 0.2) < 0.001,
                  abs(darkGrid.alphaComponent - 0.2) < 0.001
            else {
                throw probeError(
                    "\(style.rawValue) grid contrast or opacity changed"
                )
            }
        }
        board.showBehindForPreview()
        RunLoop.current.run(until: Date().addingTimeInterval(0.05))
        board.resetSubmittedGridFrameCountForPreview()

        let styles: [TraceGridStyle] = [
            .dots,
            .square,
            .horizontal,
            .vertical,
        ]
        let iterations = 160
        let finalStyle = styles[(iterations - 1) % styles.count]
        let finalSpacing = 4 + (iterations - 1) % 61
        var updateTimes: [Double] = []
        updateTimes.reserveCapacity(iterations)
        for index in 0..<iterations {
            let start = DispatchTime.now().uptimeNanoseconds
            board.setGridForPreview(
                style: styles[index % styles.count],
                spacingPoints: 4 + index % 61
            )
            let elapsed = DispatchTime.now().uptimeNanoseconds - start
            updateTimes.append(Double(elapsed) / 1_000_000)
        }
        board.flushScheduledGridDrawForPreview()
        board.hideAfterPreview()

        let submitted = board.submittedGridFrameCountForPreview
        guard submitted > 0, submitted <= 4 else {
            throw probeError(
                "grid burst submitted \(submitted) frames instead of "
                    + "coalescing the latest state"
            )
        }
        guard let submittedState = board.submittedGridStateForPreview,
              submittedState.style == finalStyle,
              submittedState.spacingPoints == finalSpacing
        else {
            throw probeError(
                "grid burst did not present its latest state"
            )
        }
        let sorted = updateTimes.sorted()
        let p95 = sorted[Int(Double(sorted.count - 1) * 0.95)]
        guard p95 < 1 else {
            throw probeError(
                String(
                    format: "grid update p95 %.3f ms exceeds 1 ms",
                    p95
                )
            )
        }
        print(
            String(
                format: "grid-update dispatch p95=%.2f µs frames=%d",
                p95 * 1_000,
                submitted
            )
        )
    }

    private static func setupPreviewSnapshot(
        inputEnabled: Bool = false,
        calibration: CalibratedSurface? = nil,
        microphoneAuthorized: Bool = true,
        dictationConfigured: Bool = true,
        apiKeyState: OpenRouterAPIKeyState = .externallySupplied,
        deviceInfo: PenDeviceInfo? = nil,
        lastError: String? = nil
    ) -> TraceAppSnapshot {
        TraceAppSnapshot(
            phase: .waitingForPen,
            connectionState: inputEnabled ? .connected : .reconnecting,
            inputEnabled: inputEnabled,
            calibration: calibration,
            calibrationActive: false,
            calibrationCorner: nil,
            calibrationMessage: nil,
            screenCaptureAuthorized: false,
            microphoneAuthorized: microphoneAuthorized,
            dictationConfigured: dictationConfigured,
            openRouterAPIKeyState: apiKeyState,
            voiceState: .idle,
            penStatus: nil,
            penDeviceInfo: deviceInfo,
            desiredHoverEnabled: nil,
            appSettings: TraceAppSettings(),
            canUndo: false,
            canRedo: false,
            setupVisible: true,
            currentDocument: nil,
            lastError: lastError
        )
    }

    private static func calibrationPreviewSnapshot() -> TraceAppSnapshot {
        TraceAppSnapshot(
            phase: .waitingForPen,
            connectionState: .connected,
            inputEnabled: true,
            calibration: nil,
            calibrationActive: true,
            calibrationCorner: .topRight,
            calibrationMessage: "Touch the top right paper corner.",
            screenCaptureAuthorized: true,
            microphoneAuthorized: true,
            dictationConfigured: true,
            openRouterAPIKeyState: .externallySupplied,
            voiceState: .idle,
            penStatus: nil,
            penDeviceInfo: nil,
            desiredHoverEnabled: nil,
            appSettings: TraceAppSettings(),
            canUndo: false,
            canRedo: false,
            setupVisible: true,
            currentDocument: nil,
            lastError: nil
        )
    }

    private static func verifyOnboardingPresentation() throws {
        let board = TraceBoardWindowController()
        board.prepareOnboardingForPreview(setupPreviewSnapshot())
        let setup = board.setupStateForPreview
        let setupText = board.setupVisibleTextForPreview
        let setupChrome = board.boardWindowChromeForPreview
        guard setup.setupVisible,
              !setup.calibrationVisible,
              setup.panelUsesStandaloneWindow,
              setup.panelUsesNativeWindowChrome,
              setup.panelIsOutsideDrawingArea,
              !setup.panelUsesDarkAppearance,
              setup.calibrationUsesDarkAppearance,
              (0.14...0.16).contains(
                  setup.calibrationBackgroundBrightness
              ),
              (0.87...0.89).contains(setup.calibrationBackgroundAlpha),
              setup.penDetail == "Connecting",
              setup.penAction == nil,
              setup.captureAction == "Allow",
              setup.voiceAction == nil,
              setup.penTitle == "Not detected",
              setup.usesRegularItemTypography,
              abs(setup.panelFrame.width - 360) < 0.5,
              setupText.contains("Pen"),
              setupText.contains("Microphone access"),
              setupText.contains("Screen Recording permission"),
              setupText.contains("Keyboard shortcuts"),
              !setupText.contains("Devices and permissions"),
              !setupText.contains("Voice service"),
              !setupText.contains(
                  "Active system-wide while Trace is running."
              ),
              !setupText.contains(
                  "Unassigned. Use a modifier or function key."
              ),
              setupChrome.titled,
              setupChrome.resizable,
              setupChrome.fullSizeContent,
              setupChrome.titleHidden,
              setupChrome.titlebarTransparent,
              setupChrome.titlebarSeparatorHidden,
              setupChrome.visibleStandardButtonCount == 0,
              setupChrome.topContentInteractive,
              setupChrome.nativeFrameOwnsEdges
        else {
            throw probeError(
                "setup did not use native external utility-panel chrome "
                    + "setup=\(setup) chrome=\(setupChrome)"
            )
        }

        let wrappingError =
            "Trace could not access the OpenRouter key in Keychain: "
            + "Invalid attempt to change the owner of this item."
        board.prepareOnboardingForPreview(
            setupPreviewSnapshot(lastError: wrappingError)
        )
        let setupWithError = board.setupStateForPreview
        guard abs(setupWithError.panelFrame.width - 360) < 0.5,
              setupWithError.panelFrame.height > setup.panelFrame.height,
              setupWithError.errorUsesConstrainedWrapping,
              board.setupVisibleTextForPreview.contains(wrappingError)
        else {
            throw probeError(
                "setup errors did not wrap within the fixed panel width"
            )
        }

        board.prepareOnboardingForPreview(
            setupPreviewSnapshot(inputEnabled: true)
        )
        let uncalibrated = board.setupStateForPreview
        guard uncalibrated.penDetail == "Connected",
              uncalibrated.penAction == "Start calibration"
        else {
            throw probeError(
                "connected pen did not expose calibration contextually"
            )
        }

        let savedCalibration = CalibratedSurface(
            page: PenPageID(section: 3, owner: 27, note: 258, page: 1),
            calibration: try NcodeSurfaceCalibration(
                corners: [
                    NcodePoint(x: 0, y: 0),
                    NcodePoint(x: 100, y: 0),
                    NcodePoint(x: 100, y: 100),
                    NcodePoint(x: 0, y: 100),
                ]
            )
        )
        let pen = PenDeviceInfo(
            modelName: "NWP-F50",
            firmwareVersion: "1.03",
            protocolVersion: "2.13",
            subName: "Neosmartpen_M1",
            deviceType: 1,
            macAddress: "00:00:00:00:00:00",
            pressureSensorType: 1,
            colorTypeID: nil
        )
        board.prepareOnboardingForPreview(
            setupPreviewSnapshot(
                inputEnabled: true,
                calibration: savedCalibration,
                deviceInfo: pen
            )
        )
        let calibrated = board.setupStateForPreview
        guard calibrated.penTitle == "Connected",
              calibrated.penDetail == "Connected and ready",
              calibrated.penAction == "Calibration"
        else {
            throw probeError(
                "ready pen did not expose optional recalibration"
            )
        }

        board.prepareOnboardingForPreview(
            setupPreviewSnapshot(
                apiKeyState: .userKeychain
            )
        )
        let savedAPIKey = board.setupStateForPreview
        guard !savedAPIKey.apiKeyFieldVisible,
              !savedAPIKey.apiKeySaveVisible,
              savedAPIKey.apiKeyRemoveVisible,
              savedAPIKey.apiKeyResetTitle == "Reset",
              savedAPIKey.apiKeyResetUsesLinkStyle
        else {
            throw probeError(
                "saved API key did not expose an inline reset action"
            )
        }

        board.prepareOnboardingForPreview(
            setupPreviewSnapshot(
                microphoneAuthorized: true,
                dictationConfigured: false,
                apiKeyState: .missing
            )
        )
        let configuredMicrophone = board.setupStateForPreview
        guard configuredMicrophone.voiceReady,
              configuredMicrophone.voiceAction == nil
        else {
            throw probeError(
                "voice setup did not model microphone permission separately"
            )
        }

        board.prepareOnboardingForPreview(
            setupPreviewSnapshot(
                microphoneAuthorized: false,
                dictationConfigured: false
            )
        )
        let missingVoice = board.setupStateForPreview
        guard missingVoice.voiceAction == "Allow" else {
            throw probeError(
                "missing Dictation configuration hid microphone recovery"
            )
        }

        let calibrationBackground = TraceRGBAColor(
            red: 0.10,
            green: 0.18,
            blue: 0.30
        )
        board.prepareOnboardingForPreview(
            calibrationPreviewSnapshot(),
            backgroundColor: calibrationBackground
        )
        let calibration = board.setupStateForPreview
        guard !calibration.setupVisible,
              calibration.calibrationVisible,
              !calibration.paintsReplacementBackground,
              !calibration.panelUsesDarkAppearance,
              calibration.calibrationUsesDarkAppearance,
              (0.14...0.16).contains(
                  calibration.calibrationBackgroundBrightness
              ),
              (0.87...0.89).contains(
                  calibration.calibrationBackgroundAlpha
              ),
              board.isBoardResizableForPreview
        else {
            throw probeError(
                "calibration replaced or escaped the focused current surface "
                    + "state=\(calibration)"
            )
        }
        var cancelRequested = false
        board.onCancelCalibration = {
            cancelRequested = true
        }
        board.cancelCalibrationForPreview()
        guard cancelRequested else {
            throw probeError(
                "Cancel calibration did not use its distinct callback"
            )
        }
        board.hideBoard()
    }

    private static func verifyOptionalSetupFlow() throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        let suite = "TraceOptionalSetup.\(UUID().uuidString)"
        guard let defaults = UserDefaults(suiteName: suite) else {
            throw probeError("could not create setup preferences")
        }
        defer {
            defaults.removePersistentDomain(forName: suite)
            try? FileManager.default.removeItem(at: directory)
        }
        let store = TraceDrawingStore(directoryURL: directory)
        let model = TraceAppModel(
            drawingStore: store,
            defaults: defaults,
            transportFactory: { HardwareFreeNeoTransport() }
        )
        model.start()
        guard let firstDocument = model.snapshot.currentDocument,
              firstDocument.manifest.pageKind == .blank,
              firstDocument.manifest.sourceWindowBounds?.width == 900,
              firstDocument.manifest.sourceWindowBounds?.height == 650,
              model.snapshot.setupVisible
        else {
            throw probeError(
                "first launch did not present the real blank drawing with setup"
            )
        }
        let documentID = firstDocument.manifest.id
        guard model.newBlankPage(
            size: NSSize(width: 840, height: 620),
            backingScale: 1
        ),
        defaults.bool(forKey: "TraceOnboardingComplete"),
        !model.snapshot.setupVisible,
        model.snapshot.currentDocument?.manifest.id != documentID
        else {
            throw probeError(
                "new blank did not hide and complete first-run setup"
            )
        }
        let secondDocumentID = model.snapshot.currentDocument?.manifest.id
        model.showOnboarding()
        guard model.snapshot.setupVisible,
              model.snapshot.currentDocument?.manifest.id == secondDocumentID
        else {
            throw probeError(
                "manual setup reopen discarded the current drawing"
            )
        }
        guard model.newBlankPage(
            size: NSSize(width: 760, height: 580),
            backingScale: 1
        ),
        !model.snapshot.setupVisible,
        model.snapshot.currentDocument?.manifest.id != secondDocumentID
        else {
            throw probeError(
                "setup remained visible across an imported/new blank document"
            )
        }
        model.showOnboarding()
        model.openDrawing(from: firstDocument.packageURL)
        guard !model.snapshot.setupVisible,
              model.snapshot.currentDocument?.manifest.id == documentID
        else {
            throw probeError(
                "setup remained visible across an existing document open"
            )
        }
        let screenshotDocument = try store.createBlank(
            size: NSSize(width: 640, height: 480),
            backingScale: 1,
            backgroundColor: TraceRGBAColor(red: 1, green: 1, blue: 1)
        )
        screenshotDocument.manifest.pageKind = TracePageKind.screenshot
        try store.save(screenshotDocument)
        model.showOnboarding()
        model.openDrawing(from: screenshotDocument.packageURL)
        guard !model.snapshot.setupVisible,
              model.snapshot.currentDocument?.manifest.id
                  == screenshotDocument.manifest.id
        else {
            throw probeError(
                "setup remained visible across a screenshot document open"
            )
        }
        model.openDrawing(from: firstDocument.packageURL)
        model.showOnboarding()
        model.recalibrate()
        guard model.snapshot.calibrationActive,
              model.snapshot.currentDocument?.manifest.id == documentID
        else {
            throw probeError(
                "calibration replaced the current drawing"
            )
        }
        model.cancelCalibration()
        guard !model.snapshot.calibrationActive,
              model.snapshot.setupVisible,
              model.snapshot.currentDocument?.manifest.id == documentID
        else {
            throw probeError(
                "calibration cancel dismissed setup or replaced the drawing"
            )
        }
        model.recalibrate()
        let calibration = CalibratedSurface(
            page: PenPageID(section: 3, owner: 27, note: 258, page: 1),
            calibration: try NcodeSurfaceCalibration(
                corners: [
                    NcodePoint(x: 0, y: 0),
                    NcodePoint(x: 100, y: 0),
                    NcodePoint(x: 100, y: 100),
                    NcodePoint(x: 0, y: 100),
                ]
            )
        )
        model.completeCalibrationForTesting(calibration)
        guard !model.snapshot.calibrationActive,
              model.snapshot.setupVisible,
              model.snapshot.currentDocument?.manifest.id == documentID
        else {
            throw probeError(
                "calibration completion did not return to setup over the drawing"
            )
        }
        model.stop()
        let returningModel = TraceAppModel(
            drawingStore: TraceDrawingStore(directoryURL: directory),
            defaults: defaults,
            transportFactory: { HardwareFreeNeoTransport() }
        )
        returningModel.start()
        guard !returningModel.snapshot.setupVisible,
              returningModel.snapshot.currentDocument == nil
        else {
            throw probeError(
                "dismissed setup reopened for the returning user"
            )
        }
        returningModel.stop()
    }

    private static func verifyGlobalShortcutSetupUI() throws {
        let previousBlank = KeyboardShortcuts.getShortcut(
            for: .traceNewBlankTrace
        )
        let previousCapture = KeyboardShortcuts.getShortcut(
            for: .traceCaptureFrontmostApp
        )
        defer {
            KeyboardShortcuts.setShortcut(
                previousBlank,
                for: .traceNewBlankTrace
            )
            KeyboardShortcuts.setShortcut(
                previousCapture,
                for: .traceCaptureFrontmostApp
            )
        }
        KeyboardShortcuts.setShortcut(nil, for: .traceNewBlankTrace)
        KeyboardShortcuts.setShortcut(nil, for: .traceCaptureFrontmostApp)

        let shortcuts = TraceGlobalShortcutManager()
        shortcuts.start()
        defer {
            shortcuts.stop()
        }

        let board = TraceBoardWindowController()
        let snapshot = setupPreviewSnapshot()
        board.onGlobalShortcutsChange = {
            shortcuts.shortcutsDidChange()
            board.updateOnboarding(
                snapshot,
                shortcuts: shortcuts.snapshot
            )
        }
        board.prepareOnboardingForPreview(
            snapshot,
            shortcuts: shortcuts.snapshot
        )
        let state = board.setupStateForPreview
        guard state.blankShortcut == "Unassigned",
              state.blankShortcutDetail.contains(
                  "modifier or function key"
              ),
              board.shortcutConflictPolicyForPreview(
                  .newBlankTrace
              ) == .allowAll,
              board.shortcutConflictPolicyForPreview(
                  .captureFrontmostApp
              ) == .allowAll
        else {
            throw probeError(
                "setup did not present package-owned unassigned recorders"
            )
        }

        let assigned = KeyboardShortcuts.Shortcut(
            .n,
            modifiers: [.command, .option]
        )
        KeyboardShortcuts.setShortcut(
            assigned,
            for: .traceNewBlankTrace
        )
        shortcuts.shortcutsDidChange()
        let relaunchedBoard = TraceBoardWindowController()
        relaunchedBoard.prepareOnboardingForPreview(
            snapshot,
            shortcuts: shortcuts.snapshot
        )
        let relaunchedState = relaunchedBoard.setupStateForPreview
        guard relaunchedState.blankShortcut == assigned.description,
              relaunchedState.blankShortcutDetail.contains(
                  "Active system-wide"
              )
        else {
            throw probeError(
                "setup did not show the package-persisted layout-aware value"
            )
        }

        guard board.shortcutValidationForPreview(
            .captureFrontmostApp,
            shortcut: assigned
        ) == .disallow(
            reason: "Already assigned to New Blank Trace."
        )
        else {
            throw probeError(
                "setup did not reject a duplicate Trace assignment"
            )
        }

        KeyboardShortcuts.setShortcut(
            nil,
            for: .traceNewBlankTrace
        )
        shortcuts.shortcutsDidChange()
        let clearedBoard = TraceBoardWindowController()
        clearedBoard.prepareOnboardingForPreview(
            snapshot,
            shortcuts: shortcuts.snapshot
        )
        guard clearedBoard.setupStateForPreview.blankShortcut
                  == "Unassigned",
              KeyboardShortcuts.getShortcut(
                  for: .traceNewBlankTrace
              ) == nil
        else {
            throw probeError(
                "package clear did not persist across recorder recreation"
            )
        }
        board.hideBoard()
        relaunchedBoard.hideBoard()
        clearedBoard.hideBoard()
    }

    private static func verifyProductHoverPolicy() throws {
        guard TraceProductHoverPolicy.diameter == 24,
              TraceProductHoverPolicy.strokeWidth == 2,
              TraceProductHoverPolicy.magnification == 2,
              TraceProductHoverPolicy.opacity == 0.2
        else {
            throw probeError(
                "hover magnifier geometry changed"
            )
        }
        guard !TraceHoverSyncPolicy.shouldRequest(
            desired: nil,
            reported: false,
            requestPending: false
        ),
        TraceHoverSyncPolicy.shouldRequest(
            desired: true,
            reported: false,
            requestPending: false
        ),
        !TraceHoverSyncPolicy.shouldRequest(
            desired: true,
            reported: false,
            requestPending: true
        ),
        TraceHoverSyncPolicy.displayedState(
            desired: true,
            reported: false
        ),
        !TraceHoverSyncPolicy.displayedState(
            desired: false,
            reported: true
        ) else {
            throw probeError("local hover sync policy changed")
        }

        guard TraceProductHoverPolicy.canDisplay(
            hoverEnabled: true,
            isAnnotating: true,
            pageIsCompatible: true
        ),
        !TraceProductHoverPolicy.canDisplay(
            hoverEnabled: false,
            isAnnotating: true,
            pageIsCompatible: true
        ),
        !TraceProductHoverPolicy.canDisplay(
            hoverEnabled: true,
            isAnnotating: true,
            pageIsCompatible: false
        ),
        !TraceProductHoverPolicy.canDisplay(
            hoverEnabled: true,
            isAnnotating: true,
            pageIsCompatible: false
        ) else {
            throw probeError(
                "product hover ignored setting or page availability"
            )
        }

        let current = TracePoint(x: 100, y: 100)
        guard !TraceProductHoverPolicy.shouldMove(
            from: current,
            to: TracePoint(x: 100.5, y: 100),
            backingScale: 2
        ),
        TraceProductHoverPolicy.shouldMove(
            from: current,
            to: TracePoint(x: 101, y: 100),
            backingScale: 2
        ),
        TraceProductHoverPolicy.idleSeconds == 0.5
        else {
            throw probeError(
                "product hover deadband or expiry changed"
            )
        }
    }

    private static func verifyBlankViewportPersistenceAndCalibration()
        throws
    {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        let suite = "TraceBlankViewport.\(UUID().uuidString)"
        guard let defaults = UserDefaults(suiteName: suite) else {
            throw probeError("could not create blank viewport preferences")
        }
        defer {
            defaults.removePersistentDomain(forName: suite)
            try? FileManager.default.removeItem(at: directory)
        }

        let invalid = try JSONEncoder().encode(
            TraceSize(width: -1, height: 100)
        )
        defaults.set(invalid, forKey: TraceBlankViewportPreferences.key)
        let invalidModel = TraceAppModel(
            drawingStore: TraceDrawingStore(directoryURL: directory),
            defaults: defaults,
            transportFactory: { HardwareFreeNeoTransport() }
        )
        guard invalidModel.preferredBlankViewportSize
            == NSSize(width: 900, height: 650)
        else {
            throw probeError("invalid saved blank viewport was not rejected")
        }

        defaults.removeObject(forKey: TraceBlankViewportPreferences.key)
        let store = TraceDrawingStore(directoryURL: directory)
        let model = TraceAppModel(
            drawingStore: store,
            defaults: defaults,
            transportFactory: { HardwareFreeNeoTransport() }
        )
        model.prepareForDocumentCreationTesting()
        var presented: TraceDrawingSession?
        model.onPresentDocument = { presented = $0.document }
        guard model.newBlankPage(
            size: model.preferredBlankViewportSize,
            backingScale: 2
        ), let blank = presented
        else {
            throw probeError("could not create blank viewport probe")
        }
        blank.manifest.strokes = [
            TraceDrawingStroke(
                id: 1,
                color: .red,
                brush: .pen,
                width: 5.25,
                points: [
                    TraceDrawingPoint(
                        x: 0.25,
                        y: 0.75,
                        pressure: nil,
                        tiltX: nil,
                        tiltY: nil,
                        twistDegrees: nil,
                        connectsToPrevious: false
                    ),
                ]
            ),
        ]
        let originalPoints = blank.manifest.strokes[0].points

        let board = TraceBoardWindowController()
        board.prepareDocumentForPreview(
            blank,
            toolState: TraceToolState()
        )
        board.onBlankViewportResize = {
            model.recordBlankViewportSize($0)
        }
        for size in [
            NSSize(width: 980, height: 680),
            NSSize(width: 1_040, height: 720),
        ] {
            board.resizeBoardForPreview(to: size)
        }
        board.endLiveResizeForPreview()
        let persisted = TraceBlankViewportPreferences.load(from: defaults)
        guard persisted == NSSize(width: 1_040, height: 720),
              blank.manifest.sourceWindowBounds
                  == TraceRect(x: 0, y: 0, width: 900, height: 650),
              blank.manifest.strokes[0].points == originalPoints
        else {
            throw probeError(
                "manual blank resize did not persist without distorting mapping"
            )
        }

        let portrait = CalibratedSurface(
            page: PenPageID(section: 3, owner: 27, note: 258, page: 1),
            calibration: try NcodeSurfaceCalibration(
                corners: [
                    NcodePoint(x: 0, y: 0),
                    NcodePoint(x: 70, y: 0),
                    NcodePoint(x: 70, y: 100),
                    NcodePoint(x: 0, y: 100),
                ]
            )
        )
        model.onCalibrationCompleted = { surface in
            guard let size = board.calibratedBlankViewportSize(
                aspectRatio: surface.calibration.estimatedAspectRatio
            ) else {
                return
            }
            model.resizeCurrentBlankForCalibration(
                to: size,
                backingScale: 2
            )
            board.applyCurrentDocumentGeometry()
        }
        model.recalibrate()
        model.completeCalibrationForTesting(portrait)
        let calibratedSize = board.boardContentSizeForPreview
        guard calibratedSize.height > calibratedSize.width,
              abs(
                  calibratedSize.width / calibratedSize.height
                      - portrait.calibration.estimatedAspectRatio
              ) < 0.001,
              blank.manifest.strokes[0].points == originalPoints,
              TraceBlankViewportPreferences.load(from: defaults)
                  == calibratedSize
        else {
            throw probeError(
                "portrait calibration did not resize the real drawable "
                    + "viewport without moving normalized content "
                    + "size=\(calibratedSize)"
            )
        }

        let reloadedModel = TraceAppModel(
            drawingStore: store,
            defaults: defaults,
            transportFactory: { HardwareFreeNeoTransport() }
        )
        guard reloadedModel.preferredBlankViewportSize == calibratedSize
        else {
            throw probeError(
                "calibrated blank viewport did not survive a new model instance"
            )
        }
        reloadedModel.prepareForDocumentCreationTesting()
        var nextBlank: TraceDrawingSession?
        reloadedModel.onPresentDocument = { nextBlank = $0.document }
        guard reloadedModel.newBlankPage(
            size: reloadedModel.preferredBlankViewportSize,
            backingScale: 2
        ),
        nextBlank?.manifest.sourceWindowBounds
            == TraceRect(
                x: 0,
                y: 0,
                width: calibratedSize.width,
                height: calibratedSize.height
            )
        else {
            throw probeError(
                "the next blank did not use the persisted calibrated viewport"
            )
        }

        let screenshot = try makeScreenshot(
            pixelWidth: 640,
            pixelHeight: 480
        )
        let screenshotDocument = TraceDrawingSession(
            manifest: TraceDrawingManifest(
                id: UUID(),
                createdAt: Date(),
                updatedAt: Date(),
                sourceApplicationName: "Probe",
                sourceWindowTitle: "Screenshot",
                screenshotFileName: "screenshot.png",
                screenshotPixelWidth: 640,
                screenshotPixelHeight: 480,
                sourceWindowBounds: TraceRect(
                    x: 0,
                    y: 0,
                    width: 640,
                    height: 480
                ),
                pageKind: .screenshot,
                viewport: TraceRect(
                    x: 0.125,
                    y: 0.125,
                    width: 0.5,
                    height: 0.5
                ),
                strokes: []
            ),
            screenshot: screenshot,
            packageURL: URL(fileURLWithPath: "/dev/null")
        )
        let screenshotBoard = TraceBoardWindowController()
        screenshotBoard.prepareDocumentForPreview(
            screenshotDocument,
            toolState: TraceToolState()
        )
        guard screenshotBoard.boardContentSizeForPreview
            == NSSize(width: 320, height: 240)
        else {
            throw probeError(
                "cropped screenshot did not size from source crop geometry"
            )
        }
        screenshotBoard.onBlankViewportResize = {
            model.recordBlankViewportSize($0)
        }
        screenshotBoard.resizeBoardForPreview(
            to: NSSize(width: 333, height: 222)
        )
        screenshotBoard.endLiveResizeForPreview()
        guard TraceBlankViewportPreferences.load(from: defaults)
                == calibratedSize,
              abs(
                  screenshotBoard.boardContentSizeForPreview.width - 333
              ) < 0.5,
              screenshotDocument.manifest.sourceWindowBounds?.width == 640
        else {
            throw probeError(
                "screenshot sizing overwrote blank persistence or source geometry"
            )
        }
        board.hideBoard()
        screenshotBoard.hideBoard()
    }

    private static func verifyAppSettings() throws {
        let suite = "TraceAppSettingsProbe.\(UUID().uuidString)"
        guard let defaults = UserDefaults(suiteName: suite) else {
            throw probeError("could not create app settings preferences")
        }
        defer {
            defaults.removePersistentDomain(forName: suite)
        }
        let initial = TraceAppSettingsPreferences.load(from: defaults)
        guard initial == TraceAppSettings(),
              initial.autoAnnotateDictation,
              initial.transcriptAnnotationScale == .medium
        else {
            throw probeError("app settings defaults changed")
        }
        defaults.set(true, forKey: "TraceCopyOnCapOn")
        guard TraceAppSettingsPreferences.load(from: defaults)
            .copyTraceAndCloseOnDisconnect
        else {
            throw probeError("legacy disconnect-copy setting was lost")
        }
        defaults.removeObject(forKey: "TraceCopyOnCapOn")
        let modelDirectory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        defer {
            try? FileManager.default.removeItem(at: modelDirectory)
        }
        defaults.set(24, forKey: "TraceGridSpacingPixels")
        defaults.set(8.75, forKey: "TraceStrokeWidth")
        var transportCreated = false
        let previewModel = TraceAppModel(
            drawingStore: TraceDrawingStore(directoryURL: modelDirectory),
            defaults: defaults,
            transportFactory: {
                transportCreated = true
                return HardwareFreeNeoTransport()
            }
        )
        _ = previewModel.snapshot
        previewModel.stop()
        guard !transportCreated,
              previewModel.toolState.gridSpacingPoints == 24,
              defaults.integer(forKey: "TraceGridSpacingPoints") == 24,
              abs(previewModel.toolState.width - 8.75) < 0.001
        else {
            throw probeError(
                "tool preferences did not restore without Bluetooth"
            )
        }
        var updatedToolState = previewModel.toolState
        updatedToolState.width = 10.25
        previewModel.updateToolState(updatedToolState)
        RunLoop.current.run(
            until: Date().addingTimeInterval(0.02)
        )
        guard abs(
                  defaults.double(forKey: "TraceStrokeWidth") - 10.25
              ) < 0.001
        else {
            throw probeError(
                "stroke width did not persist after changing it"
            )
        }
        let reopenedModel = TraceAppModel(
            drawingStore: TraceDrawingStore(directoryURL: modelDirectory),
            defaults: defaults,
            transportFactory: {
                transportCreated = true
                return HardwareFreeNeoTransport()
            }
        )
        defer {
            reopenedModel.stop()
        }
        guard abs(reopenedModel.toolState.width - 10.25) < 0.001
        else {
            throw probeError(
                "stroke width did not survive model recreation"
            )
        }
        guard TracePenPreferences.hoverEnabled(from: defaults) == nil else {
            throw probeError("untouched hover preference was not optional")
        }
        TracePenPreferences.saveHoverEnabled(true, to: defaults)
        let hoverTransport = HardwareFreeNeoTransport()
        let hoverModel = TraceAppModel(
            drawingStore: TraceDrawingStore(directoryURL: modelDirectory),
            defaults: defaults,
            transportFactory: { hoverTransport }
        )
        hoverModel.receiveTransportForTesting(
            .status(penStatus(hoverEnabled: false))
        )
        hoverModel.receiveTransportForTesting(
            .status(penStatus(hoverEnabled: false))
        )
        guard hoverTransport.hoverRequests == [true] else {
            throw probeError(
                "local hover preference was not de-duplicated on connect"
            )
        }
        hoverModel.receiveTransportForTesting(.settingChanged(.hover))
        hoverModel.receiveTransportForTesting(
            .status(penStatus(hoverEnabled: true))
        )
        hoverModel.setPenHoverEnabled(false)
        guard hoverTransport.statusRequestCount == 1,
              hoverTransport.hoverRequests == [true, false],
              TracePenPreferences.hoverEnabled(from: defaults) == false
        else {
            throw probeError(
                "local hover preference did not persist and reconcile"
            )
        }
        let customized = TraceAppSettings(
            captureScreenshotOnCapOff: false,
            copyTraceAndCloseOnDisconnect: true,
            copyTraceAndCloseOnCopy: false,
            autoAnnotateDictation: false,
            transcriptAnnotationScale: .large,
            launchInMenuBarAtLogin: false
        )
        TraceAppSettingsPreferences.save(customized, to: defaults)
        guard let reloadedDefaults = UserDefaults(suiteName: suite),
              TraceAppSettingsPreferences.load(from: reloadedDefaults)
                  == customized,
              reloadedDefaults.object(forKey: "TraceCloseOnCopy") == nil,
              reloadedDefaults.object(forKey: "TraceCopyOnCapOn") == nil
        else {
            throw probeError("app settings did not survive relaunch")
        }

        let pen = PenDeviceInfo(
            modelName: "NWP-F50",
            firmwareVersion: "1.03",
            protocolVersion: "2.13",
            subName: "Neosmartpen_M1",
            deviceType: 1,
            macAddress: "00:00:00:00:00:00",
            pressureSensorType: 1,
            colorTypeID: nil
        )
        guard TracePenMenuPresentation.title(
            deviceInfo: pen,
            batteryPercent: 73
        ) == "NeoPen M1+ · 73%" else {
            throw probeError(
                "pen menu did not show recognized model and battery"
            )
        }
        guard TraceAppSettingsMenuPresentation.connectedSection
            == "When pen is connected",
            TraceAppSettingsMenuPresentation.captureScreenshot
                == "Capture screenshot",
            TraceAppSettingsMenuPresentation.disconnectedSection
                == "When pen is disconnected",
            TraceAppSettingsMenuPresentation.copyTraceAndClose
                == "Copy trace and close app",
            TraceAppSettingsMenuPresentation.onCopySection
                == "On copy (cmd+c)",
            TraceAppSettingsMenuPresentation.dictationSection
                == "Dictation",
            TraceAppSettingsMenuPresentation.autoAnnotateDictation
                == "Start dictation automatically",
            TraceAppSettingsMenuPresentation.annotationScale
                == "Annotation scale",
            TraceAppSettingsMenuPresentation.launchInMenuBarAtLogin
                == "Launch in menu bar at login",
            TraceAppSettingsMenuPresentation.annotationScaleTitle(.small)
                == "Small (75%)",
            TraceAppSettingsMenuPresentation.annotationScaleTitle(.medium)
                == "Medium (100%)",
            TraceAppSettingsMenuPresentation.annotationScaleTitle(.large)
                == "Large (150%)"
        else {
            throw probeError("app settings menu labels changed")
        }
        let penAppSettingItems = (0..<6).map { _ in NSMenuItem() }
        TraceAppSettingsMenuPresentation.applyPenVisibility(
            isConnected: false,
            to: penAppSettingItems
        )
        guard penAppSettingItems.allSatisfy(\.isHidden) else {
            throw probeError(
                "pen-related app settings remained visible while disconnected"
            )
        }
        TraceAppSettingsMenuPresentation.applyPenVisibility(
            isConnected: true,
            to: penAppSettingItems
        )
        guard penAppSettingItems.allSatisfy({ !$0.isHidden }) else {
            throw probeError(
                "pen-related app settings did not return after connection"
            )
        }
        guard TraceAppMenuPresentation.newBlankTrace
            == "New Blank trace",
            TraceAppMenuPresentation.newScreenshotTrace
                == "New Screenshot trace",
            TraceAppMenuPresentation.openTraces == "Open traces...",
            TraceAppMenuPresentation.setup == "Setup"
        else {
            throw probeError("app menu labels changed")
        }

        guard TraceAppBehaviorPolicy.shouldCaptureScreenshot(
            settings: initial,
            force: false
        ),
        !TraceAppBehaviorPolicy.shouldCaptureScreenshot(
            settings: customized,
            force: false
        ),
        TraceAppBehaviorPolicy.shouldCaptureScreenshot(
            settings: customized,
            force: true
        ),
        TraceAppBehaviorPolicy.shouldCloseAfterManualCopy(
            settings: initial
        ),
        !TraceAppBehaviorPolicy.shouldCloseAfterManualCopy(
            settings: customized
        ) else {
            throw probeError(
                "app settings were not applied to copy/capture"
            )
        }
        let automaticCopy = TraceAppBehaviorPolicy.penDisconnectPlan(
            settings: customized,
            hasDocument: true,
            keepDocumentOpen: false,
            copyAlreadyInFlight: false,
            copyRequestPending: false
        )
        let pendingCopy = TraceAppBehaviorPolicy.penDisconnectPlan(
            settings: customized,
            hasDocument: true,
            keepDocumentOpen: false,
            copyAlreadyInFlight: false,
            copyRequestPending: true
        )
        let ordinaryDisconnect = TraceAppBehaviorPolicy.penDisconnectPlan(
            settings: TraceAppSettings(),
            hasDocument: true,
            keepDocumentOpen: false,
            copyAlreadyInFlight: false,
            copyRequestPending: false
        )
        let manualCopy = TraceAppBehaviorPolicy.penDisconnectPlan(
            settings: TraceAppSettings(),
            hasDocument: true,
            keepDocumentOpen: false,
            copyAlreadyInFlight: true,
            copyRequestPending: false
        )
        let keptOpen = TraceAppBehaviorPolicy.penDisconnectPlan(
            settings: TraceAppSettings(),
            hasDocument: true,
            keepDocumentOpen: true,
            copyAlreadyInFlight: false,
            copyRequestPending: false
        )
        guard automaticCopy == TracePenDisconnectPlan(
            preserveDocumentForCopy: true,
            requestCopy: true,
            keepDocumentOpenWithoutCopy: false
        ),
        pendingCopy == TracePenDisconnectPlan(
            preserveDocumentForCopy: true,
            requestCopy: false,
            keepDocumentOpenWithoutCopy: false
        ),
        ordinaryDisconnect == TracePenDisconnectPlan(
            preserveDocumentForCopy: false,
            requestCopy: false,
            keepDocumentOpenWithoutCopy: true
        ),
        manualCopy == TracePenDisconnectPlan(
            preserveDocumentForCopy: true,
            requestCopy: false,
            keepDocumentOpenWithoutCopy: false
        ),
        keptOpen == TracePenDisconnectPlan(
            preserveDocumentForCopy: true,
            requestCopy: false,
            keepDocumentOpenWithoutCopy: false
        ) else {
            throw probeError("disconnect copy lifecycle plan changed")
        }
    }

    private static func verifyGlobalShortcuts() throws {
        var blankCommandCount = 0
        var captureCommandCount = 0
        for action in TraceGlobalShortcutAction.allCases {
            TraceGlobalShortcutActionDispatch.perform(
                action,
                newBlankTrace: { blankCommandCount += 1 },
                captureFrontmostApp: { captureCommandCount += 1 }
            )
        }
        guard blankCommandCount == 1, captureCommandCount == 1 else {
            throw probeError(
                "global shortcut actions did not route to canonical commands"
            )
        }

        let previousBlank = KeyboardShortcuts.getShortcut(
            for: .traceNewBlankTrace
        )
        let previousCapture = KeyboardShortcuts.getShortcut(
            for: .traceCaptureFrontmostApp
        )
        defer {
            KeyboardShortcuts.setShortcut(
                previousBlank,
                for: .traceNewBlankTrace
            )
            KeyboardShortcuts.setShortcut(
                previousCapture,
                for: .traceCaptureFrontmostApp
            )
        }
        KeyboardShortcuts.setShortcut(nil, for: .traceNewBlankTrace)
        KeyboardShortcuts.setShortcut(nil, for: .traceCaptureFrontmostApp)
        guard KeyboardShortcuts.getShortcut(
                  for: .traceNewBlankTrace
              ) == nil,
              KeyboardShortcuts.getShortcut(
                  for: .traceCaptureFrontmostApp
              ) == nil
        else {
            throw probeError("global shortcuts did not default to unassigned")
        }

        let persistenceRawValue =
            "TraceProbePersistence-\(UUID().uuidString)"
        let persistenceName = KeyboardShortcuts.Name(persistenceRawValue)
        let persisted = KeyboardShortcuts.Shortcut(
            .f19,
            modifiers: [.command, .option]
        )
        KeyboardShortcuts.setShortcut(persisted, for: persistenceName)
        guard KeyboardShortcuts.getShortcut(
                  for: KeyboardShortcuts.Name(persistenceRawValue)
              ) == persisted
        else {
            throw probeError("global shortcuts did not round-trip")
        }
        KeyboardShortcuts.setShortcut(nil, for: persistenceName)

        let suite = "TraceGlobalShortcuts.\(UUID().uuidString)"
        guard let defaults = UserDefaults(suiteName: suite) else {
            throw probeError("could not create shortcut preferences")
        }
        defer {
            defaults.removePersistentDomain(forName: suite)
        }
        defaults.set(Data([1, 2, 3]), forKey: "TraceGlobalShortcutAssignments")
        TraceGlobalShortcutLegacyStorage.remove(from: defaults)
        guard defaults.object(
            forKey: "TraceGlobalShortcutAssignments"
        ) == nil else {
            throw probeError("legacy custom shortcut storage was retained")
        }

        let blank = KeyboardShortcuts.Shortcut(
            .f17,
            modifiers: [.command, .option, .control, .shift]
        )
        let capture = KeyboardShortcuts.Shortcut(
            .f18,
            modifiers: [.command, .option, .control, .shift]
        )
        KeyboardShortcuts.setShortcut(blank, for: .traceNewBlankTrace)
        KeyboardShortcuts.setShortcut(
            capture,
            for: .traceCaptureFrontmostApp
        )
        let shortcuts = TraceGlobalShortcutManager(
            legacyDefaults: defaults
        )
        shortcuts.start()
        defer {
            shortcuts.stop()
        }
        guard shortcuts.snapshot.assignment(for: .newBlankTrace) == blank,
              shortcuts.snapshot.assignment(
                  for: .captureFrontmostApp
              ) == capture,
              shortcuts.snapshot.state(for: .newBlankTrace).isActive,
              shortcuts.snapshot.state(
                  for: .captureFrontmostApp
              ).isActive
        else {
            throw probeError(
                "persisted global shortcuts did not register on launch"
            )
        }

        KeyboardShortcuts.setShortcut(
            blank,
            for: .traceCaptureFrontmostApp
        )
        shortcuts.shortcutsDidChange()
        guard !shortcuts.snapshot.state(for: .newBlankTrace).isActive,
              !shortcuts.snapshot.state(
                  for: .captureFrontmostApp
              ).isActive,
              !KeyboardShortcuts.isEnabled(for: .traceNewBlankTrace),
              !KeyboardShortcuts.isEnabled(
                  for: .traceCaptureFrontmostApp
              ),
              shortcuts.snapshot.state(
                  for: .captureFrontmostApp
              ).message?.contains("another Trace action") == true
        else {
            throw probeError(
                "stored duplicate shortcuts remained ambiguously active"
            )
        }

        KeyboardShortcuts.setShortcut(
            nil,
            for: .traceCaptureFrontmostApp
        )
        shortcuts.shortcutsDidChange()
        guard shortcuts.snapshot.state(for: .newBlankTrace).isActive,
              shortcuts.snapshot.state(
                  for: .captureFrontmostApp
              ).isUnassigned
        else {
            throw probeError(
                "clearing a duplicate did not restore the remaining shortcut"
            )
        }

        KeyboardShortcuts.disable(.traceNewBlankTrace)
        defer {
            KeyboardShortcuts.enable(.traceNewBlankTrace)
        }
        guard !shortcuts.snapshot.state(for: .newBlankTrace).isActive else {
            throw probeError(
                "package registration failure state was not surfaced"
            )
        }
    }

    private static func verifyGlobalShortcutMenuPresentation() throws {
        let blankItem = NSMenuItem(
            title: TraceAppMenuPresentation.newBlankTrace,
            action: nil,
            keyEquivalent: "n"
        )
        let captureItem = NSMenuItem(
            title: TraceAppMenuPresentation.newScreenshotTrace,
            action: nil,
            keyEquivalent: "n"
        )
        let blankShortcut = KeyboardShortcuts.Shortcut(
            .n,
            modifiers: [.command, .option]
        )
        let captureShortcut = KeyboardShortcuts.Shortcut(
            .f18,
            modifiers: [.control, .shift]
        )
        let fileBlankItem = NSMenuItem(
            title: TraceAppMenuPresentation.newBlankTrace,
            action: nil,
            keyEquivalent: ""
        )
        let fileCaptureItem = NSMenuItem(
            title: TraceAppMenuPresentation.newScreenshotTrace,
            action: nil,
            keyEquivalent: ""
        )
        let items: [TraceGlobalShortcutAction: [NSMenuItem]] = [
            .newBlankTrace: [blankItem, fileBlankItem],
            .captureFrontmostApp: [captureItem, fileCaptureItem],
        ]
        let assigned = TraceGlobalShortcutsSnapshot(states: [
            .newBlankTrace: TraceGlobalShortcutActionState(
                assignment: blankShortcut,
                isActive: true,
                message: nil
            ),
            .captureFrontmostApp: TraceGlobalShortcutActionState(
                assignment: captureShortcut,
                isActive: true,
                message: nil
            ),
        ])

        TraceGlobalShortcutMenuPresentation.apply(
            assigned,
            to: items
        )
        guard blankItem.keyEquivalent
                  == blankShortcut.nsMenuItemKeyEquivalent,
              blankItem.keyEquivalentModifierMask
                  == blankShortcut.modifiers,
              captureItem.keyEquivalent
                  == captureShortcut.nsMenuItemKeyEquivalent,
              captureItem.keyEquivalentModifierMask
                  == captureShortcut.modifiers,
              fileBlankItem.keyEquivalent
                  == blankShortcut.nsMenuItemKeyEquivalent,
              fileBlankItem.keyEquivalentModifierMask
                  == blankShortcut.modifiers,
              fileCaptureItem.keyEquivalent
                  == captureShortcut.nsMenuItemKeyEquivalent,
              fileCaptureItem.keyEquivalentModifierMask
                  == captureShortcut.modifiers
        else {
            throw probeError(
                "assigned global shortcuts were not shown natively in menu"
            )
        }

        TraceGlobalShortcutMenuPresentation.apply(
            TraceGlobalShortcutsSnapshot(),
            to: items
        )
        guard blankItem.keyEquivalent.isEmpty,
              blankItem.keyEquivalentModifierMask.isEmpty,
              captureItem.keyEquivalent == "n",
              captureItem.keyEquivalentModifierMask == [.command],
              fileBlankItem.keyEquivalent.isEmpty,
              fileBlankItem.keyEquivalentModifierMask.isEmpty,
              fileCaptureItem.keyEquivalent == "n",
              fileCaptureItem.keyEquivalentModifierMask == [.command]
        else {
            throw probeError(
                "unassigned menu shortcuts did not restore action defaults"
            )
        }
    }

    private static func verifyDrawingFolderMigration() throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        let legacy = root.appendingPathComponent(
            "Trace Drawings",
            isDirectory: true
        )
        let package = legacy.appendingPathComponent(
            "Existing.traceboard",
            isDirectory: true
        )
        defer {
            try? FileManager.default.removeItem(at: root)
        }
        try FileManager.default.createDirectory(
            at: package,
            withIntermediateDirectories: true
        )
        try Data("existing".utf8).write(
            to: package.appendingPathComponent("marker")
        )
        let store = TraceDrawingStore(
            documentsDirectoryURL: root
        )
        let preferredPackage = root
            .appendingPathComponent("Trace", isDirectory: true)
            .appendingPathComponent(
                "Existing.traceboard",
                isDirectory: true
            )
        guard store.directoryURL.lastPathComponent == "Trace",
              FileManager.default.fileExists(
                  atPath: preferredPackage
                      .appendingPathComponent("marker").path
              ),
              !FileManager.default.fileExists(atPath: legacy.path)
        else {
            throw probeError(
                "Trace Drawings folder was not renamed without data loss"
            )
        }
    }

    private static func penStatus(
        hoverEnabled: Bool
    ) -> PenDeviceStatus {
        PenDeviceStatus(
            isLocked: false,
            passwordMaxRetryCount: 3,
            passwordRetryCount: 0,
            timestampMilliseconds: 0,
            autoPowerOffMinutes: 20,
            maxForce: 852,
            usedStoragePercent: 0,
            penCapPowerOffEnabled: true,
            autoPowerOnEnabled: true,
            beepEnabled: true,
            hoverEnabled: hoverEnabled,
            batteryPercent: 73,
            isCharging: false,
            offlineDataEnabled: true,
            pressureSensitivityStep: 2
        )
    }

    private static func verifyOpenWithImagePolicy() throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(
            at: directory,
            withIntermediateDirectories: true
        )
        defer {
            try? FileManager.default.removeItem(at: directory)
        }
        let pngURL = directory.appendingPathComponent("first.png")
        let jpegURL = directory.appendingPathComponent("second.jpg")
        let textURL = directory.appendingPathComponent("invalid.txt")
        let drawingURL = directory.appendingPathComponent("drawing.traceboard")
        try encodedImageData(
            color: .systemRed,
            format: .png
        ).write(to: pngURL)
        try encodedImageData(
            color: .systemBlue,
            format: .jpeg
        ).write(to: jpegURL)
        try Data("not an image".utf8).write(to: textURL)
        guard let request = TraceOpenFilePolicy.request(
                  for: [pngURL.path, jpegURL.path]
              ),
              case let .images(images) = request,
              images.map(\.name) == ["first.png", "second.jpg"],
              images.count == 2
        else {
            throw probeError(
                "Open With did not preserve one multi-image selection"
            )
        }
        var imageOpenCount = 0
        var openedImageCount = 0
        guard TraceOpenFileCoordinator.handle(
                  request,
                  openDrawing: { _ in },
                  openImages: { images in
                      imageOpenCount += 1
                      openedImageCount = images.count
                      return true
                  }
              ),
              imageOpenCount == 1,
              openedImageCount == 2
        else {
            throw probeError(
                "Open With split one image selection into multiple canvases"
            )
        }
        guard TraceOpenFilePolicy.request(
                  for: [pngURL.path, textURL.path]
              ) == nil,
              case let .drawing(url)? = TraceOpenFilePolicy.request(
                  for: [drawingURL.path]
              ),
              url == drawingURL
        else {
            throw probeError(
                "Open With accepted a mixed selection or lost traceboards"
            )
        }
    }

    private static func verifyOpenFileLifecycle() throws {
        let first = "/tmp/First.traceboard"
        let second = "/tmp/Second.traceboard"
        let lifecycle = TraceOpenFileLifecycle()
        var delivered: [[String]] = []

        lifecycle.receive([first])
        guard delivered.isEmpty else {
            throw probeError(
                "Open files were delivered before app launch completed"
            )
        }

        lifecycle.activate { filenames, completion in
            delivered.append(filenames)
            completion(true)
        }
        guard delivered == [[first]] else {
            throw probeError(
                "Queued open files were not delivered after app launch"
            )
        }

        lifecycle.receive([second])
        guard delivered == [[first], [second]] else {
            throw probeError(
                "Open files were not delivered while the app was ready"
            )
        }

        let payload = TraceOpenFileForwarding.payload(
            for: [first, second]
        )
        guard TraceOpenFileForwarding.filenames(from: payload)
                == [first, second],
              TraceOpenFileForwarding.filenames(
                  from: ["filenames": [first, 42]]
              ) == nil
        else {
            throw probeError(
                "Forwarded open files were not validated"
            )
        }
    }

    private static func verifyOpenWithRegistration() throws {
        guard let documentTypes = Bundle.main.object(
                  forInfoDictionaryKey: "CFBundleDocumentTypes"
              ) as? [[String: Any]],
              documentTypes.contains(where: { item in
                  let contentTypes =
                      item["LSItemContentTypes"] as? [String] ?? []
                  return contentTypes.contains("public.image")
                      && item["CFBundleTypeRole"] as? String == "Editor"
                      && item["LSHandlerRank"] as? String == "Alternate"
              })
        else {
            throw probeError(
                "Trace was not registered for native image Open With"
            )
        }
    }

    private static func encodedImageData(
        color: NSColor,
        format: NSBitmapImageRep.FileType
    ) throws -> Data {
        let image = NSImage(size: NSSize(width: 32, height: 24))
        image.lockFocus()
        color.setFill()
        NSRect(x: 0, y: 0, width: 32, height: 24).fill()
        image.unlockFocus()
        guard let tiff = image.tiffRepresentation,
              let representation = NSBitmapImageRep(data: tiff),
              let data = representation.representation(
                  using: format,
                  properties: [:]
              )
        else {
            throw probeError("could not encode Open With image fixture")
        }
        return data
    }

    private static func verifyPasteboardImageDecoding() throws {
        let image = try twoToneScreenshot()
        image.size = NSSize(width: 200, height: 100)
        let pasteboard = NSPasteboard(
            name: NSPasteboard.Name("TracePasteProbe.\(UUID().uuidString)")
        )
        pasteboard.clearContents()
        guard pasteboard.writeObjects([image]),
              TracePasteboardImage.canRead(from: pasteboard),
              case let .success(pastedImages) =
                  TracePasteboardImage.read(from: pasteboard),
              let pastedImage = pastedImages.first?.image
        else {
            throw probeError("clipboard image could not be decoded")
        }
        guard pastedImage.size.width > 0,
              pastedImage.size.height > 0
        else {
            throw probeError(
                "decoded clipboard image had invalid dimensions"
            )
        }

        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(
            at: directory,
            withIntermediateDirectories: true
        )
        defer {
            try? FileManager.default.removeItem(at: directory)
        }
        let fileURL = directory.appendingPathComponent("finder.png")
        try encodedImageData(
            color: .systemPurple,
            format: .png
        ).write(to: fileURL)
        let icon = NSImage(
            systemSymbolName: "doc.fill",
            accessibilityDescription: nil
        ) ?? NSImage(size: NSSize(width: 16, height: 16))
        let finderItem = NSPasteboardItem()
        finderItem.setString(
            fileURL.absoluteString,
            forType: .fileURL
        )
        if let iconData = icon.tiffRepresentation {
            finderItem.setData(iconData, forType: .tiff)
        }
        pasteboard.clearContents()
        pasteboard.writeObjects([finderItem])
        guard case let .success(finderImages) =
                  TracePasteboardImage.read(from: pasteboard),
              let finderImage = finderImages.first?.image,
              abs(finderImage.size.width - 32) < 0.5,
              abs(finderImage.size.height - 24) < 0.5
        else {
            throw probeError(
                "Finder paste preferred its icon instead of image file contents"
            )
        }

        let secondURL = directory.appendingPathComponent("second.jpg")
        try encodedImageData(
            color: .systemOrange,
            format: .jpeg
        ).write(to: secondURL)
        let secondFinderItem = NSPasteboardItem()
        secondFinderItem.setString(
            secondURL.absoluteString,
            forType: .fileURL
        )
        if let iconData = icon.tiffRepresentation {
            secondFinderItem.setData(iconData, forType: .tiff)
        }
        let firstFinderItem = NSPasteboardItem()
        firstFinderItem.setString(
            fileURL.absoluteString,
            forType: .fileURL
        )
        if let iconData = icon.tiffRepresentation {
            firstFinderItem.setData(iconData, forType: .tiff)
        }
        pasteboard.clearContents()
        pasteboard.writeObjects([firstFinderItem, secondFinderItem])
        guard case let .success(multipleFinderImages) =
                  TracePasteboardImage.read(from: pasteboard),
              multipleFinderImages.map(\.name)
                == ["finder.png", "second.jpg"]
        else {
            throw probeError(
                "Finder multi-image paste did not preserve file contents and order"
            )
        }

        let directSecond = try makeScreenshot(
            pixelWidth: 48,
            pixelHeight: 36
        )
        pasteboard.clearContents()
        pasteboard.writeObjects([image, directSecond])
        guard case let .success(directImages) =
                  TracePasteboardImage.read(from: pasteboard),
              directImages.count == 2
        else {
            throw probeError(
                "direct bitmap paste did not preserve multiple images"
            )
        }

        let textURL = directory.appendingPathComponent("unsupported.txt")
        try Data("not an image".utf8).write(to: textURL)
        let unsupportedItem = NSPasteboardItem()
        unsupportedItem.setString(
            textURL.absoluteString,
            forType: .fileURL
        )
        if let iconData = icon.tiffRepresentation {
            unsupportedItem.setData(iconData, forType: .tiff)
        }
        pasteboard.clearContents()
        pasteboard.writeObjects([unsupportedItem])
        guard case .failure =
                  TracePasteboardImage.read(from: pasteboard)
        else {
            throw probeError(
                "unsupported Finder path fell back to its generic icon"
            )
        }
    }

    private static func verifyTldrawSnapshotPersistence() throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        defer {
            try? FileManager.default.removeItem(at: directory)
        }
        let store = TraceDrawingStore(directoryURL: directory)
        let document = try store.createBlank(
            size: NSSize(width: 1_024, height: 720),
            backingScale: 1,
            backgroundColor: TraceRGBAColor(
                red: 1,
                green: 1,
                blue: 1
            )
        )
        let snapshot = """
        {"document":{"store":{"trace":"tldraw"}},"session":{}}
        """
        document.tldrawSnapshotJSON = snapshot
        try store.save(document)
        let reopened = try store.load(from: document.packageURL)
        guard reopened.tldrawSnapshotJSON == snapshot else {
            throw probeError(
                "tldraw snapshot did not survive Trace document reopen"
            )
        }
    }

    private static func verifyDrawingHistoryIntegration() throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        let suite = "TraceHistoryProbe.\(UUID().uuidString)"
        guard let defaults = UserDefaults(suiteName: suite) else {
            throw probeError("could not create history preferences")
        }
        defer {
            defaults.removePersistentDomain(forName: suite)
            try? FileManager.default.removeItem(at: root)
        }
        let store = TraceDrawingStore(directoryURL: root)
        let document = try store.createBlank(
            size: NSSize(width: 320, height: 240),
            backingScale: 1,
            backgroundColor: .green
        )
        let original = TraceDrawingStroke(
            id: 1,
            color: .red,
            brush: .pen,
            width: 5.25,
            points: [
                TraceDrawingPoint(
                    x: 0.2,
                    y: 0.3,
                    pressure: 0.5,
                    tiltX: nil,
                    tiltY: nil,
                    twistDegrees: nil,
                    connectsToPrevious: false
                ),
            ]
        )
        var moved = original
        moved.points = [
            TraceDrawingPoint(
                x: 0.6,
                y: 0.7,
                pressure: 0.5,
                tiltX: nil,
                tiltY: nil,
                twistDegrees: nil,
                connectsToPrevious: false
            ),
        ]
        document.manifest.strokes = [moved]
        let model = TraceAppModel(
            drawingStore: store,
            defaults: defaults,
            transportFactory: { HardwareFreeNeoTransport() }
        )
        model.prepareDocumentForHistoryTesting(document)
        var refreshCount = 0
        model.onDrawingHistoryChange = {
            refreshCount += 1
        }
        model.recordManualDrawingEdit(
            before: [original],
            after: [moved]
        )
        guard model.snapshot.canUndo, !model.snapshot.canRedo else {
            throw probeError("manual move did not enter drawing history")
        }
        model.undoDrawing()
        guard document.manifest.strokes == [original],
              !model.snapshot.canUndo,
              model.snapshot.canRedo,
              refreshCount == 1
        else {
            throw probeError("undo did not restore manual movement")
        }
        model.redoDrawing()
        guard document.manifest.strokes == [moved],
              model.snapshot.canUndo,
              !model.snapshot.canRedo,
              refreshCount == 2
        else {
            throw probeError("redo did not restore manual movement")
        }
        document.manifest.strokes = []
        model.recordManualDrawingEdit(before: [moved], after: [])
        model.undoDrawing()
        guard document.manifest.strokes == [moved],
              refreshCount == 3
        else {
            throw probeError("undo did not restore a deleted drawing")
        }
        model.stop()
    }

    private static func verifyDocumentPresentationDefaults() throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        let suite = "TracePresentationDefaults.\(UUID().uuidString)"
        guard let defaults = UserDefaults(suiteName: suite) else {
            throw probeError("could not create presentation preferences")
        }
        defer {
            defaults.removePersistentDomain(forName: suite)
            try? FileManager.default.removeItem(at: directory)
        }
        TracePageBackgroundPreferences.save(.blue, to: defaults)
        let store = TraceDrawingStore(directoryURL: directory)
        let model = TraceAppModel(
            drawingStore: store,
            defaults: defaults,
            transportFactory: { HardwareFreeNeoTransport() }
        )
        model.prepareForDocumentCreationTesting()
        var selectTool = model.toolState
        selectTool.canvasTool = .select
        model.updateToolState(selectTool)
        guard model.newBlankPage(
            size: NSSize(width: 900, height: 650),
            backingScale: 1
        ),
        model.toolState.canvasTool == .pen,
        model.toolState.brush == .pen,
        model.snapshot.currentDocument?.manifest.backgroundColor == .blue
        else {
            throw probeError(
                "new blank did not reset to Pen with the shared background"
            )
        }

        let existing = try store.createBlank(
            size: NSSize(width: 640, height: 480),
            backingScale: 1,
            backgroundColor: .red
        )
        existing.manifest.pageKind = .screenshot
        try store.save(existing)
        model.updateToolState(selectTool)
        model.openDrawing(from: existing.packageURL)
        guard model.toolState.canvasTool == .pen,
              model.toolState.brush == .pen,
              model.snapshot.currentDocument?.manifest.backgroundColor
                == .red
        else {
            throw probeError(
                "existing document did not preserve color while resetting Pen"
            )
        }

        model.updatePageBackground(.yellow)
        guard model.newBlankPage(
            size: NSSize(width: 720, height: 540),
            backingScale: 1
        ),
        model.snapshot.currentDocument?.manifest.backgroundColor == .yellow,
        TracePageBackgroundPreferences.load(from: defaults) == .yellow
        else {
            throw probeError(
                "screenshot background did not become the shared new-document default"
            )
        }
        let screenshot = try makeScreenshot(
            pixelWidth: 640,
            pixelHeight: 360
        )
        guard let representation = screenshot.representations.first
                as? NSBitmapImageRep,
              let cgImage = representation.cgImage
        else {
            throw probeError("could not create capture background fixture")
        }
        let capture = CapturedWindow(
            descriptor: TraceWindowDescriptor(
                id: 1,
                ownerPID: 2,
                layer: 0,
                alpha: 1,
                bounds: TraceRect(
                    x: 40,
                    y: 60,
                    width: 640,
                    height: 360
                ),
                ownerName: "Capture Fixture",
                title: "Shared background"
            ),
            cgImage: cgImage,
            sourceScreenFrame: NSRect(
                x: 40,
                y: 60,
                width: 640,
                height: 360
            )
        )
        let captured = try model.createCapturedDocumentForTesting(capture)
        guard captured.manifest.backgroundColor == .yellow,
              captured.manifest.pageKind == .screenshot,
              captured.manifest.sourceWindowBounds
                == TraceRect(
                    x: 40,
                    y: 60,
                    width: 640,
                    height: 360
                ),
              captured.manifest.screenshotPixelWidth == 640,
              captured.manifest.screenshotPixelHeight == 360
        else {
            throw probeError(
                "new capture did not inherit background without changing geometry"
            )
        }
        model.stop()
    }

    private static func verifyProjectionPolicy() throws {
        let suite = "TraceProjectionProbe.\(UUID().uuidString)"
        guard let defaults = UserDefaults(suiteName: suite) else {
            throw probeError("could not create projection preferences")
        }
        defer {
            defaults.removePersistentDomain(forName: suite)
        }
        let initial = TraceProjectionPreferences.load(from: defaults)
        guard initial.displayKey == nil,
              initial.mode == .system,
              TraceProjectionPolicy.presentationDisplayIDs(
                  allDisplayIDs: [5],
                  workingDisplayID: 5
              ).isEmpty,
              TraceProjectionPolicy.presentationDisplayIDs(
                  allDisplayIDs: [5, 9],
                  workingDisplayID: 9
              ) == [5]
        else {
            throw probeError("projection did not default to system preference")
        }
        TraceProjectionPreferences.save(
            displayKey: "viewsonic",
            mode: .project,
            to: defaults
        )
        let restored = TraceProjectionPreferences.load(from: defaults)
        guard restored.displayKey == "viewsonic",
              restored.mode == .project,
              TraceProjectionPolicy.mode(
                  for: "viewsonic",
                  selectedDisplayKey: restored.displayKey,
                  selectedMode: restored.mode
              ) == .project,
              TraceProjectionPolicy.mode(
                  for: "other",
                  selectedDisplayKey: restored.displayKey,
                  selectedMode: restored.mode
              ) == .system,
              !TraceProjectionPolicy.editorIsVisible(in: .project),
              TraceProjectionPolicy.editorIsVisible(in: .mirror),
              TraceProjectionPolicy.menuTitle(
                  for: .system,
                  systemPreferenceDescription: "Extended"
              ) == "System preference — Extended",
              TraceProjectionPolicy.output(
                  mode: .system,
                  hasDocument: true,
                  projectDocumentActivated: true
              ) == .hidden,
              TraceProjectionPolicy.output(
                  mode: .mirror,
                  hasDocument: true,
                  projectDocumentActivated: false
              ) == .document,
              TraceProjectionPolicy.output(
                  mode: .project,
                  hasDocument: true,
                  projectDocumentActivated: false
              ) == .black,
              TraceProjectionPolicy.output(
                  mode: .project,
                  hasDocument: false,
                  projectDocumentActivated: false
              ) == .black,
              TraceProjectionPolicy.output(
                  mode: .project,
                  hasDocument: true,
                  projectDocumentActivated: true
              ) == .document,
              !TraceProjectionPolicy.shouldHoldDisplayAwake(
                  mode: .project,
                  hasDocument: true,
                  projectDocumentActivated: false
              ),
              TraceProjectionPolicy.shouldHoldDisplayAwake(
                  mode: .project,
                  hasDocument: true,
                  projectDocumentActivated: true
              )
        else {
            throw probeError(
                "projection preference or exclusive mode policy changed"
            )
        }

        let screenshot = try makeScreenshot(
            pixelWidth: 640,
            pixelHeight: 480
        )
        let now = Date()
        let document = TraceDrawingSession(
            manifest: TraceDrawingManifest(
                id: UUID(),
                createdAt: now,
                updatedAt: now,
                sourceApplicationName: "Projection Probe",
                sourceWindowTitle: "Aspect Fit",
                screenshotFileName: "screenshot.png",
                screenshotPixelWidth: 640,
                screenshotPixelHeight: 480,
                sourceWindowBounds: TraceRect(
                    x: 0,
                    y: 0,
                    width: 640,
                    height: 480
                ),
                pageKind: .screenshot,
                viewport: TracePageViewport.full,
                strokes: []
            ),
            screenshot: screenshot,
            packageURL: URL(fileURLWithPath: "/dev/null")
        )
        let projection = TraceProjectionWindowController()
        let black = projection.prepareBlackForPreview(
            outputSize: NSSize(width: 1_920, height: 1_080)
        )
        guard black.contentHidden,
              black.backgroundColor.usingColorSpace(.deviceRGB)?
                  .brightnessComponent == 0
        else {
            throw probeError(
                "inactive Project output did not render a black frame"
            )
        }
        let frame = projection.prepareForPreview(
            document,
            toolState: TraceToolState(),
            outputSize: NSSize(width: 1_920, height: 1_080)
        )
        guard frame == NSRect(
            x: 240,
            y: 0,
            width: 1_440,
            height: 1_080
        ) else {
            throw probeError(
                "projection did not preserve document aspect ratio "
                    + "frame=\(frame)"
            )
        }
        let rendered = projection.renderedContentPreview()
        let letterbox = projection.letterboxColorForPreview
            .usingColorSpace(.deviceRGB)
        let content = rendered?.colorAt(
            x: (rendered?.pixelsWide ?? 0) / 2,
            y: (rendered?.pixelsHigh ?? 0) / 2
        )?
            .usingColorSpace(.deviceRGB)
        guard rendered != nil,
              let letterbox,
              let content,
              letterbox.redComponent < 0.02,
              letterbox.greenComponent < 0.02,
              letterbox.blueComponent < 0.02,
              content.redComponent > 0.05,
              content.greenComponent > 0.05,
              content.blueComponent > 0.05
        else {
            throw probeError(
                "projection did not render content with black letterboxing "
                    + "size=\(rendered?.pixelsWide ?? -1)x"
                    + "\(rendered?.pixelsHigh ?? -1) "
                    + "letterbox=\(String(describing: letterbox)) "
                    + "content=\(String(describing: content))"
            )
        }
    }

    private static func verifyTranscriptAnnotationRendering() throws {
        let stroke = TraceDrawingStroke(
            id: 99,
            color: .red,
            brush: .pen,
            width: 5.25,
            startedAtAppClockSeconds: 100,
            endedAtAppClockSeconds: 101,
            transcriptAnnotation: TraceTranscriptAnnotation(
                id: 7,
                wordID: 3
            ),
            points: [
                TraceDrawingPoint(
                    x: 0.25,
                    y: 0.5,
                    pressure: 0.5,
                    tiltX: nil,
                    tiltY: nil,
                    twistDegrees: nil,
                    connectsToPrevious: false
                ),
                TraceDrawingPoint(
                    x: 0.75,
                    y: 0.5,
                    pressure: 0.5,
                    tiltX: nil,
                    tiltY: nil,
                    twistDegrees: nil,
                    connectsToPrevious: true
                ),
            ]
        )
        let canvas = AnnotationCanvasView(
            frame: NSRect(x: 0, y: 0, width: 200, height: 100)
        )
        guard let rendered = canvas.renderStrokeRepresentationForTesting(
            stroke,
            size: NSSize(width: 200, height: 100)
        ),
        let exported = canvas.renderStrokeRepresentationForTesting(
            stroke,
            size: NSSize(width: 200, height: 100),
            exportCoordinates: true
        ) else {
            throw probeError("could not render transcript annotation")
        }
        guard whitePixelCount(rendered) >= 3 else {
            throw probeError(
                "stroke annotation did not render its contrasting number"
            )
        }
        let yellowStroke = TraceDrawingStroke(
            id: 100,
            color: .yellow,
            brush: .pen,
            width: stroke.width,
            startedAtAppClockSeconds:
                stroke.startedAtAppClockSeconds,
            endedAtAppClockSeconds:
                stroke.endedAtAppClockSeconds,
            transcriptAnnotation: stroke.transcriptAnnotation,
            points: stroke.points
        )
        guard let yellow =
                  canvas.renderStrokeRepresentationForTesting(
                      yellowStroke,
                      size: NSSize(width: 200, height: 100)
                  ),
              whitePixelCount(yellow) >= 3
        else {
            throw probeError(
                "light stroke annotation did not keep a white number"
            )
        }
        guard let renderedData = rendered.bitmapData,
              let exportedData = exported.bitmapData,
              rendered.bytesPerRow == exported.bytesPerRow,
              rendered.pixelsHigh == exported.pixelsHigh,
              Data(
                  bytes: renderedData,
                  count: rendered.bytesPerRow * rendered.pixelsHigh
              ) == Data(
                  bytes: exportedData,
                  count: exported.bytesPerRow * exported.pixelsHigh
              )
        else {
            throw probeError(
                "exported transcript annotation mirrored its number"
            )
        }
        canvas.setTranscriptAnnotationScale(.small)
        guard let small = canvas.renderStrokeRepresentationForTesting(
            stroke,
            size: NSSize(width: 200, height: 100)
        ),
        let smallDiameter =
            canvas.transcriptAnnotationDiameterForTesting(
                stroke,
                size: NSSize(width: 200, height: 100),
                widthScale: 1
            ) else {
            throw probeError("could not render small transcript annotation")
        }
        canvas.setTranscriptAnnotationScale(.medium)
        guard let medium = canvas.renderStrokeRepresentationForTesting(
            stroke,
            size: NSSize(width: 200, height: 100)
        ),
        let mediumDiameter =
            canvas.transcriptAnnotationDiameterForTesting(
                stroke,
                size: NSSize(width: 200, height: 100),
                widthScale: 1
            ) else {
            throw probeError("could not render medium transcript annotation")
        }
        guard small.pixelsWide == medium.pixelsWide,
              abs(
                  mediumDiameter - smallDiameter / 0.75
              ) < 0.001,
              mediumDiameter <= 26
        else {
            throw probeError(
                "medium transcript annotation was not the compact base size"
            )
        }
        guard let boardDiameter =
                  canvas.transcriptAnnotationDiameterForTesting(
                      stroke,
                      size: NSSize(width: 200, height: 100),
                      widthScale: 1
                  ),
              let copiedDiameter =
                  canvas.transcriptAnnotationDiameterForTesting(
                      stroke,
                      size: NSSize(width: 400, height: 200),
                      widthScale: 2
                  ),
              abs(copiedDiameter - boardDiameter * 2) < 0.001
        else {
            throw probeError(
                "copied transcript annotation rendered smaller than board"
            )
        }
    }

    private static func whitePixelCount(
        _ representation: NSBitmapImageRep
    ) -> Int {
        var count = 0
        for y in 0..<representation.pixelsHigh {
            for x in 0..<representation.pixelsWide {
                guard let color = representation.colorAt(x: x, y: y)?
                    .usingColorSpace(.deviceRGB)
                else {
                    continue
                }
                if color.alphaComponent > 0.2,
                   color.redComponent > 0.75,
                   color.greenComponent > 0.75,
                   color.blueComponent > 0.75
                {
                    count += 1
                }
            }
        }
        return count
    }

    private static func verifyTimedTranscriptAnnotationIntegration() throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        defer {
            try? FileManager.default.removeItem(at: directory)
        }

        let store = TraceDrawingStore(directoryURL: directory)
        let document = try store.createBlank(
            size: NSSize(width: 400, height: 300),
            backingScale: 1,
            backgroundColor: TraceRGBAColor(
                red: 1,
                green: 1,
                blue: 1
            )
        )
        let page = PenPageID(section: 3, owner: 27, note: 258, page: 1)
        let calibration = CalibratedSurface(
            page: page,
            calibration: try NcodeSurfaceCalibration(
                corners: [
                    NcodePoint(x: 0, y: 0),
                    NcodePoint(x: 100, y: 0),
                    NcodePoint(x: 100, y: 100),
                    NcodePoint(x: 0, y: 100),
                ]
            )
        )
        let suite = "TraceTimedAnnotation.\(UUID().uuidString)"
        guard let defaults = UserDefaults(suiteName: suite) else {
            throw probeError("could not create annotation preferences")
        }
        defer {
            defaults.removePersistentDomain(forName: suite)
        }
        let model = TraceAppModel(
            drawingStore: store,
            defaults: defaults,
            transportFactory: { HardwareFreeNeoTransport() }
        )
        model.prepareDocumentForAnnotationTesting(
            document,
            calibration: calibration
        )
        model.receiveInputForTesting(
            .strokeStarted(
                InputStrokeStarted(
                    strokeID: 1,
                    penTimestampMilliseconds: 1_000_000,
                    receivedWallClockMilliseconds: 1_000_050,
                    receivedUptimeNanoseconds: 1,
                    inputLatencyMilliseconds: 50,
                    tipType: .normal,
                    color: 0
                )
            )
        )
        for (index, x) in [20.0, 40.0].enumerated() {
            model.receiveInputForTesting(
                .sample(
                    RawPenSample(
                        id: UInt64(index + 1),
                        strokeID: 1,
                        sampleIndex: index,
                        eventCount: UInt8(index + 1),
                        page: page,
                        penTimestampMilliseconds:
                            1_000_100 + UInt64(index * 100),
                        receivedWallClockMilliseconds:
                            1_000_150 + UInt64(index * 100),
                        receivedUptimeNanoseconds:
                            UInt64(index + 2),
                        protocolClockDeltaMilliseconds: 50,
                        interArrivalMilliseconds: 10,
                        x: x,
                        y: 40,
                        force: 426,
                        pressure: 0.5,
                        tiltX: 90,
                        tiltY: 90,
                        twist: 0,
                        continuity: index == 0 ? .first : .continuous
                    )
                )
            )
        }
        model.receiveInputForTesting(
            .strokeCompleted(
                InputStrokeCompleted(
                    strokeID: 1,
                    page: page,
                    startedAtPenMilliseconds: 1_000_000,
                    endedAtPenMilliseconds: 1_000_500,
                    durationMilliseconds: 500,
                    sampleCount: 2,
                    opticalErrorCount: 0,
                    reportedDotCount: 2,
                    totalImageCount: 2,
                    processedImageCount: 2,
                    successfulImageCount: 2,
                    sentImageCount: 2,
                    imageRecognitionRate: 1,
                    receivedWallClockMilliseconds: 1_000_550,
                    receivedUptimeNanoseconds: 4,
                    completionLatencyMilliseconds: 50
                )
            )
        )
        model.receiveTranscriptForTesting(
            TraceVoiceTranscriptSnapshot(
                text: "Sketch this.",
                words: [
                    TraceTimedTranscriptionWord(
                        text: "Sketch",
                        startedAtAppClockSeconds: 999.9,
                        endedAtAppClockSeconds: 1_000.4
                    ),
                ]
            )
        )
        let stroke = document.manifest.strokes.first
        guard stroke?.startedAtAppClockSeconds == 1_000,
              stroke?.endedAtAppClockSeconds == 1_000.5,
              stroke?.transcriptAnnotation
                == TraceTranscriptAnnotation(id: 1, wordID: 1),
              document.manifest.transcriptText == "Sketch this.",
              document.manifest.transcriptWords?.first?
                  .startedAtAppClockSeconds == 999.9,
              model.formattedTranscriptForTesting()
                  == "Sketch [1] this."
        else {
            throw probeError(
                "drawing and transcript timestamps did not align on app clock"
            )
        }
        document.manifest.strokes.append(
            TraceDrawingStroke(
                id: 2,
                color: .blue,
                brush: .pen,
                width: 5.25,
                startedAtAppClockSeconds: 1_001,
                endedAtAppClockSeconds: 1_001.4,
                points: stroke?.points ?? []
            )
        )
        model.setAutoAnnotateDictation(false)
        model.updateTldrawSnapshot(
            """
            {"document":{"store":{}},"session":{}}
            """,
            timedShapes: [
                TraceTimedCanvasShape(
                    id: "shape:mouse",
                    startedAtAppClockSeconds: 1_002,
                    endedAtAppClockSeconds: 1_002.4,
                    pathLength: 80
                ),
            ]
        )
        model.receiveTranscriptForTesting(
            TraceVoiceTranscriptSnapshot(
                text: "Sketch this point now.",
                words: [
                    TraceTimedTranscriptionWord(
                        text: "Sketch",
                        startedAtAppClockSeconds: 999.9,
                        endedAtAppClockSeconds: 1_000.4
                    ),
                    TraceTimedTranscriptionWord(
                        text: "point",
                        startedAtAppClockSeconds: 1_001,
                        endedAtAppClockSeconds: 1_001.5
                    ),
                    TraceTimedTranscriptionWord(
                        text: "now",
                        startedAtAppClockSeconds: 1_002,
                        endedAtAppClockSeconds: 1_002.5
                    ),
                ]
            )
        )
        guard document.manifest.strokes[1].transcriptAnnotation == nil,
              document.manifest.timedCanvasShapes?.first?
                .transcriptAnnotation == nil
        else {
            throw probeError(
                "disabled automatic Dictation annotation changed a drawing"
            )
        }
        model.setAutoAnnotateDictation(true)
        guard document.manifest.strokes[1].transcriptAnnotation
            == TraceTranscriptAnnotation(id: 2, wordID: 2),
            document.manifest.timedCanvasShapes?.first?
                .transcriptAnnotation
                == TraceTranscriptAnnotation(id: 3, wordID: 3),
            model.formattedTranscriptForTesting()
                == "Sketch [1] this point [2] now [3]."
        else {
            throw probeError(
                "enabling automatic Dictation annotation did not catch up"
            )
        }
        var copiedTranscript: String?
        model.finishVoiceForCopy { result in
            copiedTranscript = try? result.get()
        }
        guard copiedTranscript
            == "Sketch [1] this point [2] now [3]."
        else {
            throw probeError(
                "copy omitted the persisted annotated transcript"
            )
        }
        try store.save(document)
        let reopened = try store.load(from: document.packageURL)
        guard reopened.manifest.strokes.first?
            .transcriptAnnotation
            == TraceTranscriptAnnotation(id: 1, wordID: 1),
            reopened.manifest.timedCanvasShapes?.first?
                .transcriptAnnotation
                == TraceTranscriptAnnotation(id: 3, wordID: 3),
            reopened.manifest.transcriptWords?.first?
                .endedAtAppClockSeconds == 1_000.4
        else {
            throw probeError(
                "traceboard did not persist timed transcript annotations"
            )
        }
        let previousVoice = document.packageURL.appendingPathComponent(
            "voice.wav"
        )
        let previousTranscript = document.packageURL.appendingPathComponent(
            "transcript.txt"
        )
        try Data([0x52, 0x49, 0x46, 0x46]).write(to: previousVoice)
        try Data("old transcript".utf8).write(to: previousTranscript)
        document.manifest.voiceRecordingFileName = "voice.wav"
        document.manifest.transcriptFileName = "transcript.txt"
        try model.resetVoiceAnnotationForTesting()
        guard document.manifest.transcriptText == nil,
              document.manifest.transcriptWords == nil,
              document.manifest.voiceRecordingFileName == nil,
              document.manifest.transcriptFileName == nil,
              document.manifest.strokes.allSatisfy({
                  $0.transcriptAnnotation == nil
              }),
              document.manifest.timedCanvasShapes?.allSatisfy({
                  $0.transcriptAnnotation == nil
              }) == true,
              !FileManager.default.fileExists(
                  atPath: previousVoice.path
              ),
              !FileManager.default.fileExists(
                  atPath: previousTranscript.path
              )
        else {
            throw probeError(
                "new voice session retained stale transcript links"
            )
        }
        model.stop()
    }

    private static func verifyCompatiblePageCalibrationIntegration() throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        defer {
            try? FileManager.default.removeItem(at: directory)
        }
        let store = TraceDrawingStore(directoryURL: directory)
        let document = try store.createBlank(
            size: NSSize(width: 400, height: 300),
            backingScale: 1,
            backgroundColor: TraceRGBAColor(
                red: 1,
                green: 1,
                blue: 1
            )
        )
        let calibratedPage = PenPageID(
            section: 3,
            owner: 1012,
            note: 3017,
            page: 9
        )
        let currentPage = PenPageID(
            section: 3,
            owner: 1012,
            note: 3017,
            page: 11
        )
        let calibration = CalibratedSurface(
            page: calibratedPage,
            calibration: try NcodeSurfaceCalibration(
                corners: [
                    NcodePoint(x: 0, y: 0),
                    NcodePoint(x: 100, y: 0),
                    NcodePoint(x: 100, y: 200),
                    NcodePoint(x: 0, y: 200),
                ]
            )
        )
        let suite = "TraceCompatiblePage.\(UUID().uuidString)"
        guard let defaults = UserDefaults(suiteName: suite) else {
            throw probeError("could not create compatible-page preferences")
        }
        defer {
            defaults.removePersistentDomain(forName: suite)
        }
        let model = TraceAppModel(
            drawingStore: store,
            defaults: defaults,
            transportFactory: { HardwareFreeNeoTransport() }
        )
        model.prepareDocumentForAnnotationTesting(
            document,
            calibration: calibration
        )
        model.receiveTransportForTesting(
            .status(penStatus(hoverEnabled: true))
        )

        model.receiveInputForTesting(
            .strokeStarted(
                InputStrokeStarted(
                    strokeID: 1,
                    penTimestampMilliseconds: 1_000,
                    receivedWallClockMilliseconds: 1_000,
                    receivedUptimeNanoseconds: 1,
                    inputLatencyMilliseconds: 0,
                    tipType: .normal,
                    color: 0
                )
            )
        )
        model.receiveInputForTesting(
            .sample(
                RawPenSample(
                    id: 1,
                    strokeID: 1,
                    sampleIndex: 0,
                    eventCount: 1,
                    page: currentPage,
                    penTimestampMilliseconds: 1_001,
                    receivedWallClockMilliseconds: 1_001,
                    receivedUptimeNanoseconds: 2,
                    protocolClockDeltaMilliseconds: 0,
                    interArrivalMilliseconds: nil,
                    x: 0,
                    y: 0,
                    force: 426,
                    pressure: 0.5,
                    tiltX: 90,
                    tiltY: 90,
                    twist: 0,
                    continuity: .first
                )
            )
        )
        guard let drawingPoint = document.manifest.strokes.first?.points.first,
              abs(drawingPoint.x - 0.3125) < 0.000_001,
              drawingPoint.y == 0,
              model.currentPageForTesting == currentPage
        else {
            throw probeError(
                "compatible page did not map drawing and retain exact identity"
            )
        }
        model.receiveInputForTesting(
            .strokeCompleted(
                InputStrokeCompleted(
                    strokeID: 1,
                    page: currentPage,
                    startedAtPenMilliseconds: 1_000,
                    endedAtPenMilliseconds: 1_002,
                    durationMilliseconds: 2,
                    sampleCount: 1,
                    opticalErrorCount: 0,
                    reportedDotCount: 1,
                    totalImageCount: 1,
                    processedImageCount: 1,
                    successfulImageCount: 1,
                    sentImageCount: 1,
                    imageRecognitionRate: 1,
                    receivedWallClockMilliseconds: 1_002,
                    receivedUptimeNanoseconds: 3,
                    completionLatencyMilliseconds: 0
                )
            )
        )

        var hover: TraceHoverUpdate?
        model.onHoverUpdate = { hover = $0 }
        model.receiveHoverForTesting(
            RawHoverSample(
                id: 1,
                source: .explicitProtocolEvent,
                eventCount: nil,
                timeDeltaMilliseconds: 0,
                page: currentPage,
                receivedWallClockMilliseconds: 1_003,
                receivedUptimeNanoseconds: 4,
                interArrivalMilliseconds: nil,
                x: 100,
                y: 200,
                force: nil,
                pressure: nil,
                tiltX: nil,
                tiltY: nil,
                twist: nil
            )
        )
        guard let hover,
              abs(hover.point.x - 0.6875) < 0.000_001,
              hover.point.y == 1
        else {
            throw probeError(
                "compatible page did not use calibrated aspect-fit hover"
            )
        }
    }

    private static func persistedDimensions(_ data: Data) -> String {
        guard let representation = NSBitmapImageRep(data: data) else {
            return "invalid"
        }
        return "\(representation.pixelsWide)x\(representation.pixelsHigh)"
    }

    private static func verifyAutomaticCaptureDefaultSize() throws {
        let width = 640
        let height = 480
        let screenshot = try makeScreenshot(
            pixelWidth: width,
            pixelHeight: height
        )
        let now = Date()
        let document = TraceDrawingSession(
            manifest: TraceDrawingManifest(
                id: UUID(),
                createdAt: now,
                updatedAt: now,
                sourceApplicationName: "Automatic Capture Probe",
                sourceWindowTitle: "Default Size",
                screenshotFileName: "screenshot.png",
                screenshotPixelWidth: width,
                screenshotPixelHeight: height,
                sourceWindowBounds: TraceRect(
                    x: 0,
                    y: 0,
                    width: Double(width),
                    height: Double(height)
                ),
                pageKind: .screenshot,
                viewport: TracePageViewport.full,
                strokes: []
            ),
            screenshot: screenshot,
            packageURL: URL(fileURLWithPath: "/dev/null")
        )
        let board = TraceBoardWindowController()
        board.prepareDocumentForPreview(
            document,
            toolState: TraceToolState()
        )
        try verifyBackgroundControlLayout(board, visible: true)
        let size = board.boardContentSizeForPreview
        let originalBounds = document.manifest.sourceWindowBounds
        let originalViewport = document.manifest.viewport
        board.resizeBoardForPreview(
            to: NSSize(
                width: size.width + 120,
                height: size.height + 80
            )
        )
        RunLoop.current.run(
            until: Date().addingTimeInterval(0.05)
        )
        let resized = board.boardContentSizeForPreview
        let chrome = board.boardWindowChromeForPreview
        guard board.isBoardResizableForPreview,
              abs(resized.width - size.width - 120) < 0.5,
              abs(resized.height - size.height - 80) < 0.5
        else {
            throw probeError(
                "native board did not resize its content "
                    + "resizable=\(board.isBoardResizableForPreview) "
                    + "size=\(size)->\(resized)"
            )
        }
        guard chrome.titled,
              chrome.resizable,
              chrome.fullSizeContent,
              chrome.titleHidden,
              chrome.titlebarTransparent,
              chrome.titlebarSeparatorHidden,
              chrome.visibleStandardButtonCount == 0,
              abs(chrome.frameSize.width - chrome.contentSize.width) < 0.5,
              abs(chrome.frameSize.height - chrome.contentSize.height) < 0.5,
              chrome.nativeFrameOwnsEdges,
              chrome.topContentInteractive
        else {
            throw probeError(
                "drawing board did not use visually borderless native chrome "
                    + "\(chrome)"
            )
        }
        guard document.manifest.sourceWindowBounds == originalBounds,
              document.manifest.viewport == originalViewport
        else {
            throw probeError(
                "board resize changed document geometry instead of viewport "
                    + "bounds=\(String(describing: document.manifest.sourceWindowBounds))"
            )
        }
        let toolbarInteraction = board.toolbarInteractionForPreview
        guard !toolbarInteraction.hasWindowShadow,
              !toolbarInteraction.boardMovesFromBackground,
              toolbarInteraction.emptyAreaDrags,
              !toolbarInteraction.controlAreaDrags
        else {
            throw probeError(
                "toolbar and drawing drag regions are not separated"
            )
        }
        let copyControl = board.copyControlForPreview
        var copyActions: [TraceCopyContent] = []
        board.onCopy = {
            copyActions.append($0)
        }
        board.triggerCopyForPreview(.all)
        board.triggerCopyForPreview(.dictation)
        board.triggerCopyForPreview(.image)
        guard copyControl.title.isEmpty,
              copyControl.hasImage,
              copyControl.toolTip == "Copy trace (⌘C)",
              !copyControl.isBordered,
              !copyControl.hasCustomBackground,
              abs(copyControl.width - 24) < 0.5,
              copyControl.hasChevron,
              copyControl.menuTitles == [
                  "Copy Dictation",
                  "Copy Image",
              ],
              copyControl.menuImageCount == 0,
              copyControl.menuOpensBelow,
              abs(copyControl.menuGap - 4) < 0.5,
              copyControl.totalWidth > 34,
              copyActions == [.all, .dictation, .image]
        else {
            throw probeError(
                "copy control is not an icon with its shortcut tooltip "
                    + "title=\(copyControl.title) "
                    + "image=\(copyControl.hasImage) "
                    + "tooltip=\(copyControl.toolTip ?? "nil") "
                    + "width=\(copyControl.width) "
                    + "menu=\(copyControl.menuTitles) "
                    + "below=\(copyControl.menuOpensBelow) "
                    + "gap=\(copyControl.menuGap)"
            )
        }
        guard abs(size.width - Double(width)) < 0.5,
              abs(size.height - Double(height)) < 0.5,
              document.manifest.viewport == TracePageViewport.full
        else {
            throw probeError(
                "automatic capture did not open at screenshot size "
                    + "size=\(size.width)x\(size.height) "
                    + "viewport=\(String(describing: document.manifest.viewport))"
            )
        }
        try verifyProductHoverOverlay(board)
        try verifyDeferredResizePositioning(board)
        try verifyNativeResizeTracking(board)
    }

    private static func verifyPredictionSplitParity() throws {
        let committed = (0..<18).map { pointIndex in
            TraceDrawingPoint(
                x: 0.1 + Double(pointIndex) * 0.035,
                y: 0.45
                    + sin(Double(pointIndex) * 0.35) * 0.12,
                pressure: 0.25 + Double(pointIndex) * 0.02,
                tiltX: nil,
                tiltY: nil,
                twistDegrees: nil,
                connectsToPrevious: pointIndex > 0
            )
        }
        let lastCommitted = committed[committed.count - 1]
        let predicted = (1...4).map { pointIndex in
            TraceDrawingPoint(
                x: lastCommitted.x + Double(pointIndex) * 0.025,
                y: lastCommitted.y + Double(pointIndex) * 0.01,
                pressure: lastCommitted.pressure,
                tiltX: nil,
                tiltY: nil,
                twistDegrees: nil,
                connectsToPrevious: true
            )
        }
        let stroke = TraceDrawingStroke(
            id: 1,
            color: .yellow,
            brush: .highlighter,
            width: 8,
            points: committed
        )
        let combinedStroke = TraceDrawingStroke(
            id: stroke.id,
            color: stroke.color,
            brush: stroke.brush,
            width: stroke.width,
            points: committed + predicted
        )
        let canvas = AnnotationCanvasView(
            frame: NSRect(x: 0, y: 0, width: 640, height: 400)
        )
        let size = NSSize(width: 640, height: 400)
        guard abs(
            canvas.brushAlphaForTesting(.highlighter) - 0.5
        ) < 0.001 else {
            throw probeError(
                "native highlighter opacity is not 50%"
            )
        }
        guard let split = canvas.renderStrokeForTesting(
            stroke,
            predictedPoints: predicted,
            size: size
        ),
        let combined = canvas.renderStrokeForTesting(
            combinedStroke,
            predictedPoints: [],
            size: size
        ),
        split == combined
        else {
            throw probeError(
                "split prediction changed the rendered stroke pixels"
            )
        }
    }

    private static func verifyComposite(
        _ board: TraceBoardWindowController,
        pixelWidth: Int,
        pixelHeight: Int
    ) throws {
        guard let composite = board.compositeImageForPreview(),
              let data = composite.tiffRepresentation,
              let representation = NSBitmapImageRep(data: data),
              representation.pixelsWide == pixelWidth,
              representation.pixelsHigh == pixelHeight
        else {
            throw probeError(
                "the clipboard composite did not preserve source pixels"
            )
        }
        let pixels = inkCounts(composite)
        guard pixels.blue >= 4, pixels.red >= 1 else {
            throw probeError(
                "the clipboard composite omitted committed ink "
                    + "(red \(pixels.red), blue \(pixels.blue))"
            )
        }
        guard let item = TraceClipboardPayload.makeItem(
            image: composite,
            transcript: "Dictation"
        ),
        let png = item.data(forType: .png),
        let tiff = item.data(forType: .tiff),
        TraceClipboardPayload.transcriptMetadata(from: png)
            == "Dictation",
        TraceClipboardPayload.transcriptMetadata(from: tiff)
            == "Dictation",
        let encodedImage = NSImage(data: png),
        let encodedRepresentation = NSBitmapImageRep(data: png),
        encodedRepresentation.pixelsWide == pixelWidth,
        encodedRepresentation.pixelsHigh == pixelHeight,
        item.string(forType: .string) == "Dictation"
        else {
            throw probeError(
                "clipboard image did not retain transcript metadata"
            )
        }
        let encodedPixels = inkCounts(encodedImage)
        guard encodedPixels.blue >= 4, encodedPixels.red >= 1 else {
            throw probeError(
                "metadata encoding changed the clipboard image pixels"
            )
        }
        let isolatedPasteboard = NSPasteboard(
            name: NSPasteboard.Name(
                "TraceClipboardVariants.\(UUID().uuidString)"
            )
        )
        guard TraceClipboardPayload.writeTranscript(
                  "Dictation",
                  to: isolatedPasteboard
              ),
              isolatedPasteboard.string(forType: .string)
                  == "Dictation",
              isolatedPasteboard.data(forType: .png) == nil,
              TraceClipboardPayload.writeImage(
                  composite,
                  to: isolatedPasteboard
              ),
              isolatedPasteboard.data(forType: .png) != nil,
              isolatedPasteboard.string(forType: .string) == nil
        else {
            throw probeError(
                "split Copy did not isolate transcript and image payloads"
            )
        }
    }

    private static func inkCounts(
        _ image: NSImage
    ) -> (red: Int, blue: Int) {
        guard let data = image.tiffRepresentation,
              let representation = NSBitmapImageRep(data: data)
        else {
            return (0, 0)
        }
        var redPixels = 0
        var bluePixels = 0
        for y in stride(
            from: 0,
            to: representation.pixelsHigh,
            by: 3
        ) {
            for x in stride(
                from: 0,
                to: representation.pixelsWide,
                by: 3
            ) {
                guard let color = representation.colorAt(x: x, y: y)?
                    .usingColorSpace(.deviceRGB)
                else {
                    continue
                }
                let red = color.redComponent
                let green = color.greenComponent
                let blue = color.blueComponent
                if red > 0.55,
                   red > green * 1.4,
                   red > blue * 1.4
                {
                    redPixels += 1
                }
                if blue > 0.55,
                   blue > red * 1.4,
                   blue > green * 1.2
                {
                    bluePixels += 1
                }
                if redPixels >= 4, bluePixels >= 4 {
                    return (redPixels, bluePixels)
                }
            }
        }
        return (redPixels, bluePixels)
    }

    private static func probeError(_ message: String) -> NSError {
        NSError(
            domain: "TraceRetainedInkProbe",
            code: 1,
            userInfo: [NSLocalizedDescriptionKey: message]
        )
    }
}

private final class HardwareFreeNeoTransport: NeoTransport {
    var eventHandler: ((NeoTransportEvent) -> Void)?
    let discoveredDevices: [NeoDevice] = []
    let connectionState: PenConnectionState = .idle
    private(set) var hoverRequests: [Bool] = []
    private(set) var statusRequestCount = 0

    func startDiscovery() {}
    func stopDiscovery() {}
    func connect(to deviceID: UUID) {}
    func disconnect() {}
    func requestStatus() {
        statusRequestCount += 1
    }
    func enableOnlineData() {}
    func setCurrentTime(milliseconds: UInt64) {}
    func setHoverEnabled(_ enabled: Bool) {
        hoverRequests.append(enabled)
    }
    func setBeepEnabled(_ enabled: Bool) {}
    func setOfflineDataEnabled(_ enabled: Bool) {}
    func setAutoPowerOnEnabled(_ enabled: Bool) {}
    func setPenCapPowerOffEnabled(_ enabled: Bool) {}
    func setAutoPowerOffMinutes(_ minutes: UInt16) {}
    func setSensitivityStep(_ step: UInt8) {}
}

#endif
