import AppKit
import CoreBluetooth
import NeoInput
import NeoTransport
import TraceAppCore
import TraceCalibration
import TraceGeometry
import TraceStrokeProcessing
import TraceVoice

enum TracePageBackgroundPreferences {
    private static let key = "TraceBlankPageBackgroundColor"

    static func load(
        from defaults: UserDefaults
    ) -> TraceRGBAColor? {
        guard let data = defaults.data(forKey: key) else {
            return nil
        }
        return try? JSONDecoder().decode(
            TraceRGBAColor.self,
            from: data
        )
    }

    static func save(
        _ color: TraceRGBAColor,
        to defaults: UserDefaults
    ) {
        guard let data = try? JSONEncoder().encode(color) else {
            return
        }
        defaults.set(data, forKey: key)
    }
}

enum TraceBlankViewportPreferences {
    static let key = "TraceBlankViewportSize"

    static func load(from defaults: UserDefaults) -> NSSize {
        guard let data = defaults.data(forKey: key),
              let stored = try? JSONDecoder().decode(
                  TraceSize.self,
                  from: data
              )
        else {
            return NSSize(
                width: TraceBlankViewportPolicy.defaultSize.width,
                height: TraceBlankViewportPolicy.defaultSize.height
            )
        }
        let validated = TraceBlankViewportPolicy.validated(stored)
        return NSSize(width: validated.width, height: validated.height)
    }

    static func save(_ size: NSSize, to defaults: UserDefaults) {
        let validated = TraceBlankViewportPolicy.validated(
            TraceSize(width: size.width, height: size.height)
        )
        guard let data = try? JSONEncoder().encode(validated) else {
            return
        }
        defaults.set(data, forKey: key)
    }
}

enum TracePenPreferences {
    private static let hoverEnabledKey = "TraceDesiredPenHoverEnabled"

    static func hoverEnabled(from defaults: UserDefaults) -> Bool? {
        defaults.object(forKey: hoverEnabledKey) as? Bool
    }

    static func saveHoverEnabled(
        _ enabled: Bool,
        to defaults: UserDefaults
    ) {
        defaults.set(enabled, forKey: hoverEnabledKey)
    }
}

enum TraceHoverSyncPolicy {
    static func shouldRequest(
        desired: Bool?,
        reported: Bool,
        requestPending: Bool
    ) -> Bool {
        guard let desired else {
            return false
        }
        return desired != reported && !requestPending
    }

    static func displayedState(
        desired: Bool?,
        reported: Bool
    ) -> Bool {
        desired ?? reported
    }
}

struct TraceAppSettings: Equatable {
    var captureScreenshotOnCapOff = true
    var copyTraceAndCloseOnDisconnect = false
    var copyTraceAndCloseOnCopy = true
    var autoAnnotateDictation = true
    var transcriptAnnotationScale: TraceTranscriptAnnotationScale = .medium
    var launchInMenuBarAtLogin = true
}

enum TraceAppSettingsPreferences {
    private static let captureScreenshotOnCapOffKey =
        "TraceCaptureScreenshotOnCapOff"
    private static let copyOnDisconnectKey =
        "TraceCopyTraceAndCloseOnDisconnect"
    private static let copyOnCopyKey = "TraceCopyTraceAndCloseOnCopy"
    private static let autoAnnotateDictationKey =
        "TraceAutoAnnotateTranscriptions"
    private static let transcriptAnnotationScaleKey =
        "TraceTranscriptAnnotationScale"
    private static let launchInMenuBarAtLoginKey =
        "TraceLaunchInMenuBarAtLogin"
    private static let legacyCloseOnCopyKey = "TraceCloseOnCopy"
    private static let legacyCopyOnCapOnKey = "TraceCopyOnCapOn"

    static func load(from defaults: UserDefaults) -> TraceAppSettings {
        TraceAppSettings(
            captureScreenshotOnCapOff: bool(
                forKey: captureScreenshotOnCapOffKey,
                defaultValue: true,
                defaults: defaults
            ),
            copyTraceAndCloseOnDisconnect:
                (defaults.object(forKey: copyOnDisconnectKey) as? Bool)
                    ?? bool(
                        forKey: legacyCopyOnCapOnKey,
                        defaultValue: false,
                        defaults: defaults
                    ),
            copyTraceAndCloseOnCopy: bool(
                forKey: copyOnCopyKey,
                defaultValue: true,
                defaults: defaults
            ),
            autoAnnotateDictation: bool(
                forKey: autoAnnotateDictationKey,
                defaultValue: true,
                defaults: defaults
            ),
            transcriptAnnotationScale: defaults.string(
                forKey: transcriptAnnotationScaleKey
            ).flatMap(TraceTranscriptAnnotationScale.init(rawValue:))
                ?? .medium,
            launchInMenuBarAtLogin: bool(
                forKey: launchInMenuBarAtLoginKey,
                defaultValue: true,
                defaults: defaults
            )
        )
    }

    static func save(
        _ settings: TraceAppSettings,
        to defaults: UserDefaults
    ) {
        defaults.set(
            settings.captureScreenshotOnCapOff,
            forKey: captureScreenshotOnCapOffKey
        )
        defaults.set(
            settings.copyTraceAndCloseOnDisconnect,
            forKey: copyOnDisconnectKey
        )
        defaults.set(
            settings.copyTraceAndCloseOnCopy,
            forKey: copyOnCopyKey
        )
        defaults.set(
            settings.autoAnnotateDictation,
            forKey: autoAnnotateDictationKey
        )
        defaults.set(
            settings.transcriptAnnotationScale.rawValue,
            forKey: transcriptAnnotationScaleKey
        )
        defaults.set(
            settings.launchInMenuBarAtLogin,
            forKey: launchInMenuBarAtLoginKey
        )
        defaults.removeObject(forKey: legacyCloseOnCopyKey)
        defaults.removeObject(forKey: legacyCopyOnCapOnKey)
    }

    private static func bool(
        forKey key: String,
        defaultValue: Bool,
        defaults: UserDefaults
    ) -> Bool {
        defaults.object(forKey: key) as? Bool ?? defaultValue
    }
}

struct TracePenDisconnectPlan: Equatable {
    let preserveDocumentForCopy: Bool
    let requestCopy: Bool
    let keepDocumentOpenWithoutCopy: Bool
}

enum TraceAppBehaviorPolicy {
    static func shouldCaptureScreenshot(
        settings: TraceAppSettings,
        force: Bool
    ) -> Bool {
        force || settings.captureScreenshotOnCapOff
    }

    static func shouldCloseAfterManualCopy(
        settings: TraceAppSettings
    ) -> Bool {
        settings.copyTraceAndCloseOnCopy
    }

    static func penDisconnectPlan(
        settings: TraceAppSettings,
        hasDocument: Bool,
        keepDocumentOpen: Bool,
        copyAlreadyInFlight: Bool,
        copyRequestPending: Bool
    ) -> TracePenDisconnectPlan {
        let wantsCopy =
            hasDocument && settings.copyTraceAndCloseOnDisconnect
        return TracePenDisconnectPlan(
            preserveDocumentForCopy: hasDocument
                && (
                    wantsCopy
                        || keepDocumentOpen
                        || copyAlreadyInFlight
                        || copyRequestPending
                ),
            requestCopy: wantsCopy
                && !copyAlreadyInFlight
                && !copyRequestPending,
            keepDocumentOpenWithoutCopy:
                hasDocument
                    && !wantsCopy
                    && !keepDocumentOpen
                    && !copyAlreadyInFlight
                    && !copyRequestPending
        )
    }
}

struct TraceAppSnapshot {
    let phase: TraceAppPhase
    let connectionState: PenConnectionState
    let inputEnabled: Bool
    let calibration: CalibratedSurface?
    let calibrationActive: Bool
    let calibrationCorner: CalibrationCorner?
    let calibrationMessage: String?
    let screenCaptureAuthorized: Bool
    let microphoneAuthorized: Bool
    let dictationConfigured: Bool
    let openRouterAPIKeyState: OpenRouterAPIKeyState
    let voiceState: TraceVoiceCaptureState
    let penStatus: PenDeviceStatus?
    let penDeviceInfo: PenDeviceInfo?
    let desiredHoverEnabled: Bool?
    let appSettings: TraceAppSettings
    let canUndo: Bool
    let canRedo: Bool
    let setupVisible: Bool
    let currentDocument: TraceDrawingSession?
    let lastError: String?

}

enum TraceCanvasTool: String, Equatable {
    case select
    case pen
    case highlighter
    case rectangle
}

enum TraceStrokeWidthPolicy {
    static let minimum = 2.0
    static let maximum = 12.0
    static let defaultValue = 5.25

    static func clamped(_ width: Double) -> Double {
        guard width.isFinite else {
            return defaultValue
        }
        return min(maximum, max(minimum, width))
    }
}

struct TraceToolState: Equatable {
    var canvasTool: TraceCanvasTool = .pen
    var color: TraceRGBAColor = .red
    var brush: TraceBrushKind = .pen
    var width: Double = TraceStrokeWidthPolicy.defaultValue
    var gridStyle: TraceGridStyle = .none
    var gridSpacingPoints = TraceGridPolicy.defaultSpacingPoints

    var resettingCanvasToPen: TraceToolState {
        var state = self
        state.canvasTool = .pen
        state.brush = .pen
        return state
    }
}

struct TraceAnnotationUpdate {
    let strokeID: UInt64
    let style: TraceToolState
    let committed: [TraceDrawingPoint]
    let predicted: [TraceDrawingPoint]
    let replacement: [TraceDrawingPoint]?
    let isFinal: Bool
}

struct TraceHoverUpdate: Equatable {
    let point: TracePoint
    let color: TraceRGBAColor
}

enum TraceToolWidthPolicy {
    static func brushScale(for brush: TraceBrushKind) -> Double {
        switch brush {
        case .pen:
            return 1
        case .marker:
            return 1.32
        case .highlighter:
            return 2.15
        }
    }
}

enum TraceProductHoverPolicy {
    static let idleSeconds = 0.5
    static let deadbandPixels = 1.5
    static let diameter: Double = 24
    static let strokeWidth: Double = 2
    static let magnification: Double = 2
    static let opacity: Double = 0.2

    static func canDisplay(
        hoverEnabled: Bool,
        isAnnotating: Bool,
        pageIsCompatible: Bool
    ) -> Bool {
        hoverEnabled
            && isAnnotating
            && pageIsCompatible
    }

    static func shouldMove(
        from current: TracePoint?,
        to proposed: TracePoint,
        backingScale: Double
    ) -> Bool {
        guard let current else {
            return true
        }
        let dx = proposed.x - current.x
        let dy = proposed.y - current.y
        let distancePixels = hypot(dx, dy) * max(1, backingScale)
        return distancePixels >= deadbandPixels
    }
}

struct TraceDocumentPresentation {
    let document: TraceDrawingSession
    let capture: CapturedWindow?
    let activatesProjectOutput: Bool

    init(
        document: TraceDrawingSession,
        capture: CapturedWindow?,
        activatesProjectOutput: Bool = false
    ) {
        self.document = document
        self.capture = capture
        self.activatesProjectOutput = activatesProjectOutput
    }
}

final class TraceAppModel {
    var onStateChange: ((TraceAppSnapshot) -> Void)?
    var onShowOnboarding: (() -> Void)?
    var onPresentDocument: ((TraceDocumentPresentation) -> Void)?
    var onHideBoard: (() -> Void)?
    var onCopyRequested: (() -> Void)?
    var onAnnotationUpdate: ((TraceAnnotationUpdate) -> Void)?
    var onHoverUpdate: ((TraceHoverUpdate?) -> Void)?
    var onDrawingHistoryChange: (() -> Void)?
    var onTranscriptAnnotationsChange: (() -> Void)?
    var onVoiceLevelChange: ((Float) -> Void)?
    var onCalibrationCompleted: ((CalibratedSurface) -> Void)?

    var snapshot: TraceAppSnapshot {
        TraceAppSnapshot(
            phase: stateMachine.phase,
            connectionState: connectionState,
            inputEnabled: inputEnabled,
            calibration: calibratedSurface,
            calibrationActive: calibrationSession != nil,
            calibrationCorner: calibrationSession?.currentCorner,
            calibrationMessage: calibrationMessage,
            screenCaptureAuthorized: captureService.hasPermission,
            microphoneAuthorized:
                voiceController.microphoneAuthorization == .authorized,
            dictationConfigured: voiceController.isConfigured,
            openRouterAPIKeyState: voiceController.apiKeyState,
            voiceState: voiceController.state,
            penStatus: penStatus,
            penDeviceInfo: penDeviceInfo,
            desiredHoverEnabled: desiredHoverEnabled,
            appSettings: appSettings,
            canUndo: drawingHistory.canUndo,
            canRedo: drawingHistory.canRedo,
            setupVisible: setupVisible,
            currentDocument: currentDocument,
            lastError: lastError
        )
    }

    private(set) var toolState = TraceToolState()
    private(set) var newDocumentBackgroundColor = TraceRGBAColor(
        red: 1,
        green: 1,
        blue: 1
    )
    private(set) var preferredBlankViewportSize: NSSize
    private(set) var appSettings = TraceAppSettings()

    // UI probes construct the model; CoreBluetooth must start only with start().
    private let transportFactory: () -> any NeoTransport
    private lazy var transport: any NeoTransport = transportFactory()
    private let normalizer = NeoInputNormalizer()
    private let strokeProcessor = LiveStrokeProcessor(
        mode: .predict,
        interpolationAlgorithm: .circularArc,
        refinementAlgorithm: .smoothPath,
        predictionAlgorithm: .velocity
    )
    private let captureService: WindowCaptureService
    private let drawingStore: TraceDrawingStore
    private let calibrationStore: LocalCalibrationStore
    private let defaults: UserDefaults
    private let voiceController: TraceVoiceCaptureController
    private let openRouterAPIKeyStore: any OpenRouterAPIKeyStoring

    private var stateMachine: TraceAppStateMachine
    private var calibratedSurface: CalibratedSurface?
    private var calibrationSession: SurfaceCalibrationSession?
    private var calibrationMessage: String?
    private var connectionState: PenConnectionState = .idle
    private var penStatus: PenDeviceStatus?
    private var penDeviceInfo: PenDeviceInfo?
    private var desiredHoverEnabled: Bool?
    private var hoverSyncRequestPending = false
    private var inputEnabled = false
    private var currentPage: PenPageID?
    private var currentDocument: TraceDrawingSession?
    private var lastError: String?
    private var isStarted = false
    private var didRequestConnection = false
    private var clockSyncRequested = false
    private var clockSynchronized = false
    private var didEnableInput = false
    private var currentNotificationBatch: NeoNotificationBatch?
    private var captureInput = TraceCaptureEventRouter<NeoInputEvent>()
    private var activeAnnotationStyle: TraceToolState?
    private var activeDocumentStrokeID: UInt64?
    private var activeStrokeStartedAtAppClockSeconds: Double?
    private var setupVisible: Bool
    private var autosaveGate = TraceAutosaveGate()
    private var autosaveWorkItem: DispatchWorkItem?
    private var manualCaptureInFlight = false
    private var copyRequestPending = false
    private var keepDocumentOpenAfterCopy = false
    private var hoverGeneration: UInt64 = 0
    private var hoverClearWorkItem: DispatchWorkItem?
    private var latestHoverPoint: TracePoint?
    private var drawingHistory = TraceDrawingHistory()
    private var strokeHistoryStart: [TraceDrawingStroke]?
    private var strokeIDAllocator = TraceDocumentStrokeIDAllocator(
        existingStrokes: []
    )

    init(
        captureService: WindowCaptureService = WindowCaptureService(),
        drawingStore: TraceDrawingStore = TraceDrawingStore(),
        voiceController: TraceVoiceCaptureController? = nil,
        openRouterAPIKeyStore: any OpenRouterAPIKeyStoring =
            OpenRouterKeychainStore(),
        defaults: UserDefaults = .standard,
        transportFactory: @escaping () -> any NeoTransport = {
            CoreBluetoothNeoTransport()
        },
        paperProfile: String = "b-native-100"
    ) {
        self.captureService = captureService
        self.drawingStore = drawingStore
        self.openRouterAPIKeyStore = openRouterAPIKeyStore
        self.voiceController = voiceController
            ?? TraceVoiceCaptureController(
                apiKeyStore: openRouterAPIKeyStore
            )
        self.defaults = defaults
        self.transportFactory = transportFactory
        toolState.width = TraceStrokeWidthPolicy.clamped(
            (
                defaults.object(forKey: "TraceStrokeWidth")
                    as? NSNumber
            )?.doubleValue ?? TraceStrokeWidthPolicy.defaultValue
        )
        if let rawGridStyle = defaults.string(
            forKey: "TraceGridStyle"
        ),
        let gridStyle = TraceGridStyle(rawValue: rawGridStyle)
        {
            toolState.gridStyle = gridStyle
        }
        let storedGridSpacingPoints = defaults.object(
            forKey: "TraceGridSpacingPoints"
        ) as? Int
        let legacyGridSpacing = defaults.object(
            forKey: "TraceGridSpacingPixels"
        ) as? Int
        toolState.gridSpacingPoints = TraceGridPolicy.clampedSpacing(
            storedGridSpacingPoints
                ?? legacyGridSpacing
                ?? TraceGridPolicy.defaultSpacingPoints
        )
        if storedGridSpacingPoints == nil, legacyGridSpacing != nil {
            defaults.set(
                toolState.gridSpacingPoints,
                forKey: "TraceGridSpacingPoints"
            )
        }
        if let color = TracePageBackgroundPreferences.load(from: defaults) {
            newDocumentBackgroundColor = color
        }
        preferredBlankViewportSize = TraceBlankViewportPreferences.load(
            from: defaults
        )
        desiredHoverEnabled = TracePenPreferences.hoverEnabled(
            from: defaults
        )
        appSettings = TraceAppSettingsPreferences.load(from: defaults)

        let support = FileManager.default.urls(
            for: .applicationSupportDirectory,
            in: .userDomainMask
        ).first ?? FileManager.default.homeDirectoryForCurrentUser
        let calibrationURL = support
            .appendingPathComponent("Trace", isDirectory: true)
            .appendingPathComponent("InputLab", isDirectory: true)
            .appendingPathComponent("calibrations", isDirectory: true)
            .appendingPathComponent("\(paperProfile).json")
        calibrationStore = LocalCalibrationStore(fileURL: calibrationURL)

        let savedCalibration = try? calibrationStore.load()
        calibratedSurface = savedCalibration ?? nil
        let setupSeen = defaults.bool(
            forKey: "TraceOnboardingComplete"
        )
        setupVisible = !setupSeen
        stateMachine = TraceAppStateMachine(
            penConnected: false
        )
        normalizer.eventHandler = { [weak self] event in
            self?.handleInput(event)
        }
        self.voiceController.onStateChange = { [weak self] state in
            guard let self else {
                return
            }
            if case let .failed(message) = state {
                self.lastError =
                    "Trace Dictation failed: \(message)"
            } else if self.lastError?.hasPrefix(
                "Trace Dictation failed"
            ) == true {
                self.lastError = nil
            }
            if self.activeDocumentStrokeID != nil {
                guard case .failed = state else {
                    return
                }
            }
            self.onStateChange?(self.snapshot)
        }
        self.voiceController.onLevelChange = { [weak self] level in
            guard let self, self.activeDocumentStrokeID == nil else {
                return
            }
            self.onVoiceLevelChange?(level)
        }
        self.voiceController.onTranscriptChange = { [weak self] transcript in
            self?.handleTranscriptUpdate(transcript)
        }
    }

#if DEBUG
    func receiveTransportForTesting(_ event: NeoTransportEvent) {
        handleTransport(event)
    }

    func prepareDocumentForHistoryTesting(
        _ document: TraceDrawingSession
    ) {
        currentDocument = document
        drawingHistory.clear()
    }

    func prepareForDocumentCreationTesting() {
        stateMachine = TraceAppStateMachine(
            penConnected: false
        )
        calibrationSession = nil
    }

    func prepareDocumentForAnnotationTesting(
        _ document: TraceDrawingSession,
        calibration: CalibratedSurface
    ) {
        currentDocument = document
        calibratedSurface = calibration
        calibrationSession = nil
        stateMachine = TraceAppStateMachine(
            penConnected: false
        )
        stateMachine.receive(.drawingOpened(document.manifest.id))
        drawingHistory.clear()
        strokeIDAllocator = TraceDocumentStrokeIDAllocator(
            existingStrokes: document.manifest.strokes
        )
    }

    func receiveInputForTesting(_ event: NeoInputEvent) {
        processDrawingInput(event)
    }

    func completeCalibrationForTesting(_ surface: CalibratedSurface) {
        handleCalibration(.completed(surface))
    }

    func receiveHoverForTesting(_ sample: RawHoverSample) {
        handleHover(sample)
    }

    var currentPageForTesting: PenPageID? {
        currentPage
    }

    func receiveTranscriptForTesting(
        _ transcript: TraceVoiceTranscriptSnapshot
    ) {
        handleTranscriptUpdate(transcript)
    }

    func formattedTranscriptForTesting() -> String? {
        guard let currentDocument,
              let transcript = currentDocument.manifest.transcriptText
        else {
            return nil
        }
        return formattedTranscript(
            fallback: transcript,
            document: currentDocument
        )
    }

    func resetVoiceAnnotationForTesting() throws {
        try resetVoiceAnnotationForNewRecording()
    }

    func createCapturedDocumentForTesting(
        _ capture: CapturedWindow
    ) throws -> TraceDrawingSession {
        try drawingStore.create(
            from: capture,
            backgroundColor: newDocumentBackgroundColor
        )
    }
#endif

    func start() {
        guard !isStarted else {
            return
        }
        isStarted = true
        transport.eventHandler = { [weak self] event in
            self?.handleTransport(event)
        }
        onStateChange?(snapshot)
        if setupVisible {
            let screen = NSScreen.main ?? NSScreen.screens.first
            _ = newBlankPage(
                size: preferredBlankViewportSize,
                backingScale: screen?.backingScaleFactor ?? 2,
                activatesProjectOutput: false,
                allowsInitialSetup: true
            )
            onShowOnboarding?()
        }
        transport.startDiscovery()
    }

    func stop() {
        voiceController.cancel()
        try? saveCurrentDocument()
        if isStarted {
            transport.disconnect()
        }
    }

    func requestScreenCaptureAccess() {
        let granted = captureService.requestPermission()
        if granted {
            lastError = nil
        } else if captureService.openPermissionSettings() {
            lastError = "Allow Trace in Screen Recording. If it is already "
                + "enabled, remove that stale row with the minus button and "
                + "relaunch Trace."
        } else {
            lastError = "Open System Settings → Privacy & Security → Screen Recording and allow Trace."
        }
        onStateChange?(snapshot)
    }

    func requestMicrophoneAccess() {
        switch voiceController.microphoneAuthorization {
        case .authorized:
            lastError = nil
            onStateChange?(snapshot)
        case .notDetermined:
            voiceController.requestMicrophoneAccess { [weak self] granted in
                guard let self else {
                    return
                }
                self.lastError = granted
                    ? nil
                    : "Allow Trace in Privacy & Security → Microphone."
                self.onStateChange?(self.snapshot)
            }
        case .denied, .restricted:
            let url = URL(
                string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Microphone"
            )
            if let url, NSWorkspace.shared.open(url) {
                lastError =
                    "Allow Trace in Privacy & Security → Microphone, then return to Trace."
            } else {
                lastError =
                    "Open Privacy & Security → Microphone and allow Trace."
            }
            onStateChange?(snapshot)
        }
    }

    func saveOpenRouterAPIKey(_ apiKey: String) {
        guard voiceController.state.allowsOpenRouterAPIKeyMutation else {
            lastError = TraceVoiceConfigurationError.captureInProgress
                .localizedDescription
            onStateChange?(snapshot)
            return
        }
        do {
            try openRouterAPIKeyStore.saveAPIKey(apiKey)
            try voiceController.reloadConfiguration()
            lastError = nil
        } catch {
            lastError = error.localizedDescription
        }
        onStateChange?(snapshot)
    }

    func removeOpenRouterAPIKey() {
        guard voiceController.state.allowsOpenRouterAPIKeyMutation else {
            lastError = TraceVoiceConfigurationError.captureInProgress
                .localizedDescription
            onStateChange?(snapshot)
            return
        }
        do {
            try openRouterAPIKeyStore.removeAPIKey()
            try voiceController.reloadConfiguration()
            lastError = nil
        } catch {
            lastError = error.localizedDescription
        }
        onStateChange?(snapshot)
    }

    @discardableResult
    func completeOnboarding() -> Bool {
        defaults.set(true, forKey: "TraceOnboardingComplete")
        setupVisible = false
        calibrationSession = nil
        calibrationMessage = nil
        onStateChange?(snapshot)
        return true
    }

    func showOnboarding() {
        if currentDocument == nil {
            let screen = NSScreen.main ?? NSScreen.screens.first
            guard newBlankPage(
                size: preferredBlankViewportSize,
                backingScale: screen?.backingScaleFactor ?? 2,
                activatesProjectOutput: false
            ) else {
                return
            }
        }
        setupVisible = true
        onShowOnboarding?()
        onStateChange?(snapshot)
    }

    func recalibrate() {
        if currentDocument == nil {
            let screen = NSScreen.main ?? NSScreen.screens.first
            guard newBlankPage(
                size: preferredBlankViewportSize,
                backingScale: screen?.backingScaleFactor ?? 2,
                activatesProjectOutput: false
            ) else {
                return
            }
        }
        setupVisible = true
        beginCalibration()
        onShowOnboarding?()
        onStateChange?(snapshot)
    }

    func cancelCalibration() {
        guard calibrationSession != nil else {
            return
        }
        calibrationSession = nil
        calibrationMessage = nil
        setupVisible = true
        onStateChange?(snapshot)
    }

    func armNewCapture() {
        guard saveCurrentDocumentReportingError() else {
            return
        }
        resetAnnotationState()
        voiceController.cancel()
        currentDocument = nil
        drawingHistory.clear()
        stateMachine.receive(.boardClosed)
        lastError = nil
        onHideBoard?()
        beginFrontmostCaptureIfReady(force: true)
        onStateChange?(snapshot)
    }

    @discardableResult
    func newBlankPage(
        size: NSSize,
        backingScale: CGFloat,
        activatesProjectOutput: Bool = true,
        allowsInitialSetup: Bool = false
    ) -> Bool {
        guard stateMachine.phase != .capturing else {
            return false
        }
        do {
            guard saveCurrentDocumentReportingError() else {
                return false
            }
            resetAnnotationState()
            voiceController.cancel()
            let document = try drawingStore.createBlank(
                size: size,
                backingScale: backingScale,
                backgroundColor: newDocumentBackgroundColor
            )
            keepDocumentOpenAfterCopy = false
            currentDocument = document
            drawingHistory.clear()
            strokeIDAllocator = TraceDocumentStrokeIDAllocator(
                existingStrokes: []
            )
            stateMachine.receive(.drawingOpened(document.manifest.id))
            lastError = nil
            autoStartDictationIfEnabled()
            presentDocument(
                TraceDocumentPresentation(
                    document: document,
                    capture: nil,
                    activatesProjectOutput: activatesProjectOutput
                ),
                allowsInitialSetup: allowsInitialSetup
            )
            onStateChange?(snapshot)
            return true
        } catch {
            lastError = error.localizedDescription
            onStateChange?(snapshot)
            return false
        }
    }

    func recordBlankViewportSize(_ size: NSSize) {
        guard currentDocument?.manifest.pageKind == .blank else {
            return
        }
        let validated = TraceBlankViewportPolicy.validated(
            TraceSize(width: size.width, height: size.height)
        )
        preferredBlankViewportSize = NSSize(
            width: validated.width,
            height: validated.height
        )
        TraceBlankViewportPreferences.save(
            preferredBlankViewportSize,
            to: defaults
        )
    }

    func resizeCurrentBlankForCalibration(
        to size: NSSize,
        backingScale: CGFloat
    ) {
        guard let document = currentDocument,
              document.manifest.pageKind == .blank
        else {
            return
        }
        let validated = TraceBlankViewportPolicy.validated(
            TraceSize(width: size.width, height: size.height)
        )
        document.manifest.sourceWindowBounds = TraceRect(
            x: 0,
            y: 0,
            width: validated.width,
            height: validated.height
        )
        document.manifest.screenshotPixelWidth = max(
            1,
            Int((validated.width * backingScale).rounded())
        )
        document.manifest.screenshotPixelHeight = max(
            1,
            Int((validated.height * backingScale).rounded())
        )
        recordBlankViewportSize(
            NSSize(width: validated.width, height: validated.height)
        )
        do {
            try drawingStore.save(document)
        } catch {
            lastError = error.localizedDescription
        }
    }

    func newScreenshotPage() {
        guard stateMachine.phase != .capturing else {
            return
        }
        guard saveCurrentDocumentReportingError() else {
            return
        }
        resetAnnotationState()
        voiceController.cancel()
        keepDocumentOpenAfterCopy = false
        currentDocument = nil
        drawingHistory.clear()
        onHideBoard?()
        beginManualFrontmostCapture()
        onStateChange?(snapshot)
    }

    func updatePageBackground(_ color: TraceRGBAColor) {
        guard let currentDocument else {
            return
        }
        currentDocument.manifest.backgroundColor = color
        newDocumentBackgroundColor = color
        TracePageBackgroundPreferences.save(color, to: defaults)
        scheduleAutosaveAfterIdle(for: currentDocument.manifest.id)
    }

    func setCaptureScreenshotOnCapOff(_ enabled: Bool) {
        guard appSettings.captureScreenshotOnCapOff != enabled else {
            return
        }
        appSettings.captureScreenshotOnCapOff = enabled
        persistAppSettings()
    }

    func setCopyTraceAndCloseOnDisconnect(_ enabled: Bool) {
        guard appSettings.copyTraceAndCloseOnDisconnect != enabled else {
            return
        }
        appSettings.copyTraceAndCloseOnDisconnect = enabled
        persistAppSettings()
    }

    func setCopyTraceAndCloseOnCopy(_ enabled: Bool) {
        guard appSettings.copyTraceAndCloseOnCopy != enabled else {
            return
        }
        appSettings.copyTraceAndCloseOnCopy = enabled
        persistAppSettings()
    }

    func setAutoAnnotateDictation(_ enabled: Bool) {
        guard appSettings.autoAnnotateDictation != enabled else {
            return
        }
        appSettings.autoAnnotateDictation = enabled
        if enabled {
            applyAutomaticTranscriptAnnotations()
        }
        persistAppSettings()
    }

    func setTranscriptAnnotationScale(
        _ scale: TraceTranscriptAnnotationScale
    ) {
        guard appSettings.transcriptAnnotationScale != scale else {
            return
        }
        appSettings.transcriptAnnotationScale = scale
        persistAppSettings()
    }

    func setLaunchInMenuBarAtLogin(_ enabled: Bool) {
        guard appSettings.launchInMenuBarAtLogin != enabled else {
            return
        }
        appSettings.launchInMenuBarAtLogin = enabled
        persistAppSettings()
    }

    func openDrawing(from url: URL) {
        do {
            guard saveCurrentDocumentReportingError() else {
                return
            }
            resetAnnotationState()
            voiceController.cancel()
            let document = try drawingStore.load(from: url)
            keepDocumentOpenAfterCopy = false
            currentDocument = document
            drawingHistory.clear()
            strokeIDAllocator = TraceDocumentStrokeIDAllocator(
                existingStrokes: document.manifest.strokes
            )
            stateMachine.receive(.drawingOpened(document.manifest.id))
            lastError = nil
            presentDocument(
                TraceDocumentPresentation(
                    document: document,
                    capture: nil
                )
            )
        } catch {
            lastError = error.localizedDescription
        }
        onStateChange?(snapshot)
    }

    func closeBoard() {
        guard saveCurrentDocumentReportingError() else {
            return
        }
        resetAnnotationState()
        voiceController.cancel()
        keepDocumentOpenAfterCopy = false
        currentDocument = nil
        drawingHistory.clear()
        stateMachine.receive(.boardClosed)
        onHideBoard?()
        onStateChange?(snapshot)
    }

    func copyCompleted(closeDocument: Bool = true) {
        guard saveCurrentDocumentReportingError() else {
            copyRequestPending = false
            return
        }
        guard closeDocument else {
            voiceController.completeCopy()
            copyRequestPending = false
            onStateChange?(snapshot)
            return
        }
        resetAnnotationState()
        voiceController.completeCopy()
        copyRequestPending = false
        keepDocumentOpenAfterCopy = false
        currentDocument = nil
        drawingHistory.clear()
        stateMachine.receive(.copiedAndHidden)
        onHideBoard?()
        onStateChange?(snapshot)
    }

    func copyFailed() {
        copyRequestPending = false
        if !stateMachine.penConnected, currentDocument != nil {
            keepDocumentOpenAfterCopy = true
        }
    }

    func finishVoiceForCopy(
        completion: @escaping (Result<String?, Error>) -> Void
    ) {
        voiceController.finish { [weak self] result in
            guard let self else {
                return
            }
            do {
                let capture = try result.get()
                if let capture, let currentDocument = self.currentDocument {
                    self.storeTranscript(
                        text: capture.transcript,
                        words: capture.words,
                        in: currentDocument
                    )
                    _ = self.applyAutomaticTranscriptAnnotations()
                    let transcript =
                        self.formattedTranscript(
                            fallback: capture.transcript,
                            document: currentDocument
                        )
                    try self.drawingStore.attachVoice(
                        audioFileURL: capture.audioFileURL,
                        transcript: transcript,
                        to: currentDocument
                    )
                    completion(.success(transcript))
                } else if let currentDocument = self.currentDocument,
                          let transcript =
                              currentDocument.manifest.transcriptText,
                          !transcript.trimmingCharacters(
                              in: .whitespacesAndNewlines
                          ).isEmpty
                {
                    completion(
                        .success(
                            self.formattedTranscript(
                                fallback: transcript,
                                document: currentDocument
                            )
                        )
                    )
                } else {
                    completion(.success(capture?.transcript))
                }
                if self.lastError?.hasPrefix(
                    "Trace could not finish Dictation"
                ) == true {
                    self.lastError = nil
                }
                self.onStateChange?(self.snapshot)
            } catch {
                self.copyFailed()
                self.lastError =
                    "Trace could not finish Dictation: "
                    + error.localizedDescription
                self.onStateChange?(self.snapshot)
                completion(.failure(error))
            }
        }
    }

    func toggleVoiceRecording() {
        do {
            switch voiceController.toggleIntent(
                hasDocument: currentDocument != nil
            ) {
            case .showSetup:
                showOnboarding()
            case .pause:
                voiceController.pause()
            case .resume:
                try voiceController.resume()
            case .restart:
                try startReplacementVoiceRecording(restarting: true)
            case .start:
                try startReplacementVoiceRecording(restarting: false)
            case .ignore:
                return
            }
        } catch {
            lastError =
                "Trace Dictation failed: "
                + error.localizedDescription
            onStateChange?(snapshot)
        }
    }

    func setPenBeepEnabled(_ enabled: Bool) {
        transport.setBeepEnabled(enabled)
    }

    func setPenHoverEnabled(_ enabled: Bool) {
        desiredHoverEnabled = enabled
        TracePenPreferences.saveHoverEnabled(enabled, to: defaults)
        if !enabled {
            clearHover()
        }
        if let penStatus, penStatus.hoverEnabled != enabled {
            hoverSyncRequestPending = true
            transport.setHoverEnabled(enabled)
        } else {
            hoverSyncRequestPending = false
        }
        onStateChange?(snapshot)
    }

    func setPenOfflineDataEnabled(_ enabled: Bool) {
        transport.setOfflineDataEnabled(enabled)
    }

    func setPenAutoPowerOnEnabled(_ enabled: Bool) {
        transport.setAutoPowerOnEnabled(enabled)
    }

    func setPenCapPowerOffEnabled(_ enabled: Bool) {
        transport.setPenCapPowerOffEnabled(enabled)
    }

    func setPenAutoPowerOffMinutes(_ minutes: UInt16) {
        transport.setAutoPowerOffMinutes(minutes)
    }

    func setPenSensitivityStep(_ step: UInt8) {
        transport.setSensitivityStep(step)
    }

    func revealDrawingsFolder() {
        do {
            try FileManager.default.createDirectory(
                at: drawingStore.directoryURL,
                withIntermediateDirectories: true
            )
        } catch {
            lastError = "Trace could not open its drawings folder: "
                + error.localizedDescription
            onStateChange?(snapshot)
            return
        }
        guard NSWorkspace.shared.open(drawingStore.directoryURL) else {
            lastError = "Trace could not open its drawings folder."
            onStateChange?(snapshot)
            return
        }
        if lastError?.hasPrefix(
            "Trace could not open its drawings folder"
        ) == true {
            lastError = nil
            onStateChange?(snapshot)
        }
    }

    func updateToolState(_ state: TraceToolState) {
        var state = state
        state.width = TraceStrokeWidthPolicy.clamped(state.width)
        state.gridSpacingPoints = TraceGridPolicy.clampedSpacing(
            state.gridSpacingPoints
        )
        guard state != toolState else {
            return
        }
        let previous = toolState
        toolState = state
        if latestHoverPoint != nil {
            emitCurrentHover()
        }
        let gridStyleChanged = state.gridStyle != previous.gridStyle
        let gridSpacingChanged =
            state.gridSpacingPoints != previous.gridSpacingPoints
        let strokeWidthChanged = state.width != previous.width
        if strokeWidthChanged {
            defaults.set(
                state.width,
                forKey: "TraceStrokeWidth"
            )
        }
        if gridStyleChanged || gridSpacingChanged {
            let defaults = defaults
            let gridStyleRawValue = state.gridStyle.rawValue
            let gridSpacingPoints = state.gridSpacingPoints
            DispatchQueue.main.async {
                if gridStyleChanged {
                    defaults.set(
                        gridStyleRawValue,
                        forKey: "TraceGridStyle"
                    )
                }
                if gridSpacingChanged {
                    defaults.set(
                        gridSpacingPoints,
                        forKey: "TraceGridSpacingPoints"
                    )
                }
            }
        }
    }

    func saveCurrentDocumentEdits() {
        do {
            try saveCurrentDocument()
            clearSaveError()
            onStateChange?(snapshot)
        } catch {
            reportSaveError(error)
        }
    }

    func updateTldrawSnapshot(
        _ snapshotJSON: String,
        timedShapes: [TraceTimedCanvasShape]
    ) {
        guard let currentDocument else {
            return
        }
        var annotationsByShape: [
            String: TraceTranscriptAnnotation
        ] = [:]
        for shape in currentDocument.manifest.timedCanvasShapes ?? [] {
            if let annotation = shape.transcriptAnnotation {
                annotationsByShape[shape.id] = annotation
            }
        }
        let mergedTimedShapes = timedShapes.map { shape in
            var shape = shape
            shape.transcriptAnnotation = annotationsByShape[shape.id]
            return shape
        }
        let normalizedTimedShapes = mergedTimedShapes.isEmpty
            ? nil
            : mergedTimedShapes
        let snapshotChanged =
            currentDocument.tldrawSnapshotJSON != snapshotJSON
        let timedShapesChanged =
            currentDocument.manifest.timedCanvasShapes
                != normalizedTimedShapes
        guard snapshotChanged || timedShapesChanged else {
            return
        }
        currentDocument.tldrawSnapshotJSON = snapshotJSON
        currentDocument.manifest.timedCanvasShapes =
            normalizedTimedShapes
        let assignedAnnotations = applyAutomaticTranscriptAnnotations()
        if timedShapesChanged, !assignedAnnotations {
            onTranscriptAnnotationsChange?()
        }
        scheduleAutosaveAfterIdle(for: currentDocument.manifest.id)
    }

    func recordManualDrawingEdit(
        before: [TraceDrawingStroke],
        after: [TraceDrawingStroke]
    ) {
        guard let currentDocument,
              activeDocumentStrokeID == nil,
              currentDocument.manifest.strokes == after
        else {
            return
        }
        drawingHistory.record(before: before, after: after)
        scheduleAutosaveAfterIdle(for: currentDocument.manifest.id)
        onStateChange?(snapshot)
    }

    func undoDrawing() {
        guard currentDocument != nil,
              activeDocumentStrokeID == nil,
              !voiceController.state.isFinishing
        else {
            return
        }
        applyDrawingHistory(drawingHistory.undo())
    }

    func redoDrawing() {
        guard currentDocument != nil,
              activeDocumentStrokeID == nil,
              !voiceController.state.isFinishing
        else {
            return
        }
        applyDrawingHistory(drawingHistory.redo())
    }

    private func applyDrawingHistory(
        _ strokes: [TraceDrawingStroke]?
    ) {
        guard let strokes,
              let currentDocument
        else {
            return
        }
        resetAnnotationState()
        currentDocument.manifest.strokes = strokes
        _ = applyAutomaticTranscriptAnnotations()
        onDrawingHistoryChange?()
        scheduleAutosaveAfterIdle(for: currentDocument.manifest.id)
        onStateChange?(snapshot)
    }

    private func handleTransport(_ event: NeoTransportEvent) {
        if case let .notificationBatch(batch) = event {
            currentNotificationBatch = batch
        }
        let arrival = currentNotificationBatch.map {
            InputArrivalTime(
                wallClockMilliseconds: $0.receivedWallClockMilliseconds,
                uptimeNanoseconds: $0.receivedUptimeNanoseconds,
                transportBatchID: $0.id,
                transportBatchFrameCount: $0.frameCount,
                transportBatchByteCount: $0.byteCount
            )
        } ?? .now()
        normalizer.receive(event, at: arrival)

        switch event {
        case let .deviceDiscovered(device):
            guard !didRequestConnection else {
                return
            }
            didRequestConnection = true
            transport.connect(to: device.id)
        case let .connectionState(state, _):
            connectionState = state
            if state == .disconnected
                || state == .reconnecting
                || state == .failed
            {
                let hasDocument = currentDocument != nil
                let copyAlreadyInFlight =
                    voiceController.state.isFinishing
                let plan = TraceAppBehaviorPolicy.penDisconnectPlan(
                    settings: appSettings,
                    hasDocument: hasDocument,
                    keepDocumentOpen: keepDocumentOpenAfterCopy,
                    copyAlreadyInFlight: copyAlreadyInFlight,
                    copyRequestPending: copyRequestPending
                )
                resetConnectionState(
                    cancelVoice: !plan.preserveDocumentForCopy
                )
                if !plan.preserveDocumentForCopy {
                    if saveCurrentDocumentReportingError() {
                        keepDocumentOpenAfterCopy = false
                        if !plan.keepDocumentOpenWithoutCopy {
                            currentDocument = nil
                            drawingHistory.clear()
                            onHideBoard?()
                        }
                    }
                }
                stateMachine.receive(.penDisconnected)
                if plan.keepDocumentOpenWithoutCopy,
                   let currentDocument
                {
                    stateMachine.receive(
                        .drawingOpened(currentDocument.manifest.id)
                    )
                }
                if plan.requestCopy {
                    copyRequestPending = true
                    onCopyRequested?()
                }
            }
        case let .status(status):
            penStatus = status
            if !TraceHoverSyncPolicy.displayedState(
                desired: desiredHoverEnabled,
                reported: status.hoverEnabled
            ) {
                clearHover()
            }
            guard !status.isLocked else {
                lastError = "The pen is locked and cannot be used by Trace."
                onStateChange?(snapshot)
                return
            }
            if TraceHoverSyncPolicy.shouldRequest(
                desired: desiredHoverEnabled,
                reported: status.hoverEnabled,
                requestPending: hoverSyncRequestPending
            ), let desiredHoverEnabled
            {
                hoverSyncRequestPending = true
                transport.setHoverEnabled(desiredHoverEnabled)
            } else if desiredHoverEnabled == status.hoverEnabled {
                hoverSyncRequestPending = false
            }
            if !clockSyncRequested {
                clockSyncRequested = true
                transport.setCurrentTime(
                    milliseconds: UInt64(
                        Date().timeIntervalSince1970 * 1_000
                    )
                )
            } else if clockSynchronized, !didEnableInput {
                enableInput()
            }
        case let .deviceInfo(info):
            penDeviceInfo = info
        case .settingChanged(.timestamp):
            clockSynchronized = true
            enableInput()
        case .settingChanged(.hover):
            hoverSyncRequestPending = false
            transport.requestStatus()
        case .settingChanged:
            transport.requestStatus()
        case .onlineDataEnabled:
            keepDocumentOpenAfterCopy = false
            inputEnabled = true
            stateMachine.receive(.penConnected)
            if let currentDocument {
                stateMachine.receive(
                    .drawingOpened(currentDocument.manifest.id)
                )
            } else {
                beginFrontmostCaptureIfReady()
            }
            if lastError?.hasPrefix("Trace could not autosave") != true {
                lastError = nil
            }
        case let .failure(failure):
            hoverSyncRequestPending = false
            lastError = "\(failure.stage): \(failure.message)"
        default:
            break
        }
        onStateChange?(snapshot)
    }

    private func handleInput(_ event: NeoInputEvent) {
        if case let .hover(sample) = event {
            handleHover(sample)
            return
        }
        if let calibrationSession {
            if let update = calibrationSession.receive(event) {
                handleCalibration(update)
            }
            return
        }
        guard let event = captureInput.route(event) else {
            return
        }

        processDrawingInput(event)
    }

    private func processDrawingInput(_ event: NeoInputEvent) {
        guard !voiceController.state.isFinishing else {
            return
        }
        switch event {
        case let .strokeStarted(start):
            clearHover()
            guard case .annotating = stateMachine.phase else {
                return
            }
            strokeHistoryStart = currentDocument?.manifest.strokes
            cancelScheduledAutosave()
            voiceController.setPerformanceCritical(true)
            activeAnnotationStyle = toolState
            activeDocumentStrokeID = strokeIDAllocator.allocate()
            // Online input starts only after the pen accepts the app clock.
            activeStrokeStartedAtAppClockSeconds =
                Double(start.penTimestampMilliseconds) / 1_000
        case let .pageChanged(page):
            currentPage = page
        case let .sample(sample):
            currentPage = sample.page ?? currentPage
            guard case .annotating = stateMachine.phase,
                  let document = currentDocument,
                  calibratedSurface?.isCalibrationCompatible(
                      with: sample.page
                  ) == true,
                  let style = activeAnnotationStyle,
                  let documentStrokeID = activeDocumentStrokeID
            else {
                return
            }
            let update = strokeProcessor.receive(sample)
            apply(
                update,
                to: document,
                style: style,
                documentStrokeID: documentStrokeID,
                isFinal: false
            )
        case let .strokeCompleted(completion):
            defer {
                strokeHistoryStart = nil
                activeStrokeStartedAtAppClockSeconds = nil
            }
            guard case .annotating = stateMachine.phase,
                  let document = currentDocument,
                  let style = activeAnnotationStyle,
                  let documentStrokeID = activeDocumentStrokeID
            else {
                return
            }
            if let update = strokeProcessor.endStroke() {
                apply(
                    update,
                    to: document,
                    style: style,
                    documentStrokeID: documentStrokeID,
                    isFinal: true
                )
            }
            if let strokeIndex = document.manifest.strokes.firstIndex(
                where: { $0.id == documentStrokeID }
            ) {
                document.manifest.strokes[strokeIndex]
                    .endedAtAppClockSeconds =
                        Double(completion.endedAtPenMilliseconds) / 1_000
            }
            activeAnnotationStyle = nil
            activeDocumentStrokeID = nil
            voiceController.setPerformanceCritical(false)
            _ = applyAutomaticTranscriptAnnotations()
            if let before = strokeHistoryStart,
               before != document.manifest.strokes
            {
                drawingHistory.record(
                    before: before,
                    after: document.manifest.strokes
                )
                onStateChange?(snapshot)
            }
            scheduleAutosaveAfterIdle(for: document.manifest.id)
        case .hover, .opticalError, .anomaly:
            break
        }
    }

    private func handleHover(_ sample: RawHoverSample) {
        let isAnnotating: Bool
        if case .annotating = stateMachine.phase {
            isAnnotating = currentDocument != nil
                && activeDocumentStrokeID == nil
                && !voiceController.state.isFinishing
        } else {
            isAnnotating = false
        }
        guard TraceProductHoverPolicy.canDisplay(
            hoverEnabled: penStatus?.hoverEnabled == true
                && desiredHoverEnabled != false,
            isAnnotating: isAnnotating,
            pageIsCompatible:
                calibratedSurface?.isCalibrationCompatible(
                    with: sample.page
                ) == true
        ),
        let normalized = calibratedSurface?.calibration.normalize(
            NcodePoint(x: sample.x, y: sample.y)
        ),
        (0...1).contains(normalized.x),
        (0...1).contains(normalized.y),
        let projected = projectedPaperPoint(normalized),
        (0...1).contains(projected.x),
        (0...1).contains(projected.y)
        else {
            clearHover()
            return
        }
        hoverClearWorkItem?.cancel()
        hoverGeneration &+= 1
        let generation = hoverGeneration
        latestHoverPoint = TracePoint(
            x: projected.x,
            y: projected.y
        )
        emitCurrentHover()
        let workItem = DispatchWorkItem { [weak self] in
            guard let self, self.hoverGeneration == generation else {
                return
            }
            self.hoverClearWorkItem = nil
            self.latestHoverPoint = nil
            self.onHoverUpdate?(nil)
        }
        hoverClearWorkItem = workItem
        DispatchQueue.main.asyncAfter(
            deadline: .now() + TraceProductHoverPolicy.idleSeconds,
            execute: workItem
        )
    }

    private func handleTranscriptUpdate(
        _ transcript: TraceVoiceTranscriptSnapshot
    ) {
        guard !transcript.text.trimmingCharacters(
                  in: .whitespacesAndNewlines
              ).isEmpty,
              let currentDocument
        else {
            return
        }
        storeTranscript(
            text: transcript.text,
            words: transcript.words,
            in: currentDocument
        )
        _ = applyAutomaticTranscriptAnnotations()
        if activeDocumentStrokeID == nil {
            scheduleAutosaveAfterIdle(for: currentDocument.manifest.id)
        }
        onStateChange?(snapshot)
    }

    private func storeTranscript(
        text: String,
        words: [TraceTimedTranscriptionWord],
        in document: TraceDrawingSession
    ) {
        document.manifest.transcriptText = text
        document.manifest.transcriptWords = words.enumerated().map {
            index, word in
            TraceTranscriptWord(
                id: index + 1,
                text: word.text,
                startedAtAppClockSeconds:
                    word.startedAtAppClockSeconds,
                endedAtAppClockSeconds:
                    word.endedAtAppClockSeconds
            )
        }
    }

    @discardableResult
    private func applyAutomaticTranscriptAnnotations() -> Bool {
        guard appSettings.autoAnnotateDictation,
              let currentDocument,
              let words = currentDocument.manifest.transcriptWords,
              !words.isEmpty
        else {
            return false
        }
        let annotated = TraceTranscriptAnnotationPlanner.annotating(
            strokes: currentDocument.manifest.strokes,
            canvasShapes:
                currentDocument.manifest.timedCanvasShapes ?? [],
            words: words
        )
        guard annotated.strokes != currentDocument.manifest.strokes
                || annotated.canvasShapes
                    != (currentDocument.manifest.timedCanvasShapes ?? [])
        else {
            return false
        }
        currentDocument.manifest.strokes = annotated.strokes
        currentDocument.manifest.timedCanvasShapes =
            annotated.canvasShapes.isEmpty
                ? nil
                : annotated.canvasShapes
        drawingHistory.updateTranscriptMetadata(
            from: annotated.strokes
        )
        onTranscriptAnnotationsChange?()
        if activeDocumentStrokeID == nil {
            scheduleAutosaveAfterIdle(for: currentDocument.manifest.id)
        }
        return true
    }

    private func startReplacementVoiceRecording(
        restarting: Bool
    ) throws {
        if restarting {
            try voiceController.restart()
        } else {
            try voiceController.start()
        }
        do {
            try resetVoiceAnnotationForNewRecording()
        } catch {
            voiceController.cancel()
            throw error
        }
    }

    /// Auto-arms dictation for a newly created trace (blank or captured via
    /// screenshot) when the user has "Start dictation automatically"
    /// enabled, so they don't have to press the mic button manually.
    /// Silently does nothing if the microphone isn't authorized/configured
    /// yet; the user can still start it manually and onboarding covers
    /// first-time setup.
    private func autoStartDictationIfEnabled() {
        guard appSettings.autoAnnotateDictation,
              voiceController.microphoneAuthorization == .authorized,
              voiceController.isConfigured
        else {
            return
        }
        try? startReplacementVoiceRecording(restarting: false)
    }

    private func resetVoiceAnnotationForNewRecording() throws {
        guard let currentDocument else {
            return
        }
        let hadAnnotations =
            currentDocument.manifest.strokes.contains {
                $0.transcriptAnnotation != nil
            }
            || (
                currentDocument.manifest.timedCanvasShapes ?? []
            ).contains {
                $0.transcriptAnnotation != nil
            }
        let hadVoice = currentDocument.manifest.voiceRecordingFileName != nil
            || currentDocument.manifest.transcriptFileName != nil
            || currentDocument.manifest.transcriptText != nil
            || currentDocument.manifest.transcriptWords != nil
            || hadAnnotations
        guard hadVoice else {
            return
        }
        try drawingStore.removeVoiceArtifacts(from: currentDocument)
        currentDocument.manifest.transcriptText = nil
        currentDocument.manifest.transcriptWords = nil
        for index in currentDocument.manifest.strokes.indices {
            currentDocument.manifest.strokes[index]
                .transcriptAnnotation = nil
        }
        if var timedCanvasShapes =
            currentDocument.manifest.timedCanvasShapes
        {
            for index in timedCanvasShapes.indices {
                timedCanvasShapes[index].transcriptAnnotation = nil
            }
            currentDocument.manifest.timedCanvasShapes =
                timedCanvasShapes
        }
        drawingHistory.clearTranscriptAnnotations()
        try drawingStore.save(currentDocument)
        if hadAnnotations {
            onTranscriptAnnotationsChange?()
        }
    }

    private func formattedTranscript(
        fallback: String,
        document: TraceDrawingSession
    ) -> String {
        guard let words = document.manifest.transcriptWords else {
            return fallback
        }
        return TraceTranscriptAnnotationPlanner.annotatedTranscript(
            document.manifest.transcriptText ?? fallback,
            words: words,
            strokes: document.manifest.strokes,
            canvasShapes: document.manifest.timedCanvasShapes ?? []
        )
    }

    private func emitCurrentHover() {
        guard let latestHoverPoint else {
            return
        }
        onHoverUpdate?(
            TraceHoverUpdate(
                point: latestHoverPoint,
                color: toolState.color
            )
        )
    }

    private func clearHover() {
        hoverGeneration &+= 1
        hoverClearWorkItem?.cancel()
        hoverClearWorkItem = nil
        guard latestHoverPoint != nil else {
            return
        }
        latestHoverPoint = nil
        onHoverUpdate?(nil)
    }

    private func beginFrontmostCaptureIfReady(force: Bool = false) {
        guard TraceAppBehaviorPolicy.shouldCaptureScreenshot(
                  settings: appSettings,
                  force: force
              ),
              inputEnabled,
              calibratedSurface != nil,
              calibrationSession == nil,
              currentDocument == nil,
              stateMachine.phase == .armed,
              captureService.hasPermission,
              voiceController.microphoneAuthorization == .authorized,
              voiceController.isConfigured
        else {
            return
        }
        resetAnnotationState()
        voiceController.cancel()
        do {
            try voiceController.start()
        } catch {
            setupVisible = true
            lastError = error.localizedDescription
            onShowOnboarding?()
            onStateChange?(snapshot)
            return
        }
        manualCaptureInFlight = false
        captureInput.startCapture()
        stateMachine.receive(.captureStarted)
        performFrontmostCapture()
    }

    private func beginManualFrontmostCapture() {
        manualCaptureInFlight = false
        guard captureService.hasPermission
        else {
            setupVisible = true
            lastError =
                "Allow Screen Recording before creating a screenshot page."
            onShowOnboarding?()
            return
        }
        captureInput.startCapture()
        manualCaptureInFlight = true
        stateMachine.receive(.manualCaptureStarted)
        performFrontmostCapture()
    }

    private func performFrontmostCapture() {
        captureService.captureFrontmost { [weak self] result in
            guard let self else {
                return
            }
            guard self.stateMachine.phase == .capturing else {
                self.captureInput.cancelCapture()
                self.manualCaptureInFlight = false
                return
            }
            switch result {
            case let .success(capture):
                do {
                    let document = try self.drawingStore.create(
                        from: capture,
                        backgroundColor:
                            self.newDocumentBackgroundColor
                    )
                    self.currentDocument = document
                    if let transcript =
                        self.voiceController.transcriptSnapshot
                    {
                        self.handleTranscriptUpdate(transcript)
                    }
                    self.drawingHistory.clear()
                    self.manualCaptureInFlight = false
                    self.strokeIDAllocator =
                        TraceDocumentStrokeIDAllocator(
                            existingStrokes: []
                        )
                    self.stateMachine.receive(
                        .captureSucceeded(document.manifest.id)
                    )
                    self.lastError = nil
                    self.autoStartDictationIfEnabled()
                    self.presentDocument(
                        TraceDocumentPresentation(
                            document: document,
                            capture: capture,
                            activatesProjectOutput: true
                        )
                    )
                    for event in self.captureInput.finishCapture() {
                        self.processDrawingInput(event)
                    }
                } catch {
                    self.handleCaptureFailure(error)
                }
            case let .failure(error):
                self.handleCaptureFailure(error)
            }
            self.onStateChange?(self.snapshot)
        }
    }

    private func handleCaptureFailure(_ error: Error) {
        captureInput.cancelCapture()
        voiceController.cancel()
        stateMachine.receive(.captureFailed)
        if manualCaptureInFlight {
            manualCaptureInFlight = false
            lastError = [
                error.localizedDescription,
                (error as? LocalizedError)?.recoverySuggestion,
            ].compactMap { $0 }.joined(separator: " ")
            return
        }
        setupVisible = true
        lastError = [
            error.localizedDescription,
            (error as? LocalizedError)?.recoverySuggestion,
        ].compactMap { $0 }.joined(separator: " ")
        onShowOnboarding?()
    }

    private func apply(
        _ update: StrokeRenderUpdate,
        to document: TraceDrawingSession,
        style: TraceToolState,
        documentStrokeID: UInt64,
        isFinal: Bool
    ) {
        let committed = update.committed.compactMap(drawingPoint)
        let predicted = update.predicted.compactMap(drawingPoint)
        let replacement = update.replacement?.compactMap(drawingPoint)
        let strokeIndex = document.manifest.strokes.firstIndex {
            $0.id == documentStrokeID
        }

        if let replacement {
            if let strokeIndex {
                if document.manifest.strokes[strokeIndex]
                    .startedAtAppClockSeconds == nil
                {
                    document.manifest.strokes[strokeIndex]
                        .startedAtAppClockSeconds =
                            activeStrokeStartedAtAppClockSeconds
                }
                document.manifest.strokes[strokeIndex].points = replacement
            } else {
                document.manifest.strokes.append(
                    TraceDrawingStroke(
                        id: documentStrokeID,
                        color: style.color,
                        brush: style.brush,
                        width: style.width,
                        startedAtAppClockSeconds:
                            activeStrokeStartedAtAppClockSeconds,
                        points: replacement
                    )
                )
            }
        } else if !committed.isEmpty {
            if let strokeIndex {
                if document.manifest.strokes[strokeIndex]
                    .startedAtAppClockSeconds == nil
                {
                    document.manifest.strokes[strokeIndex]
                        .startedAtAppClockSeconds =
                            activeStrokeStartedAtAppClockSeconds
                }
                document.manifest.strokes[strokeIndex].points.append(
                    contentsOf: committed
                )
            } else {
                document.manifest.strokes.append(
                    TraceDrawingStroke(
                        id: documentStrokeID,
                        color: style.color,
                        brush: style.brush,
                        width: style.width,
                        startedAtAppClockSeconds:
                            activeStrokeStartedAtAppClockSeconds,
                        points: committed
                    )
                )
            }
        }

        onAnnotationUpdate?(
            TraceAnnotationUpdate(
                strokeID: documentStrokeID,
                style: style,
                committed: committed,
                predicted: predicted,
                replacement: replacement,
                isFinal: isFinal
            )
        )
    }

    private func drawingPoint(_ point: RenderPoint) -> TraceDrawingPoint? {
        guard let normalized = calibratedSurface?.calibration.normalize(
            NcodePoint(x: point.x, y: point.y)
        ),
        let projected = projectedPaperPoint(normalized)
        else {
            return nil
        }
        let sourceNormalized = TracePageViewport.unmap(
            projected,
            through: currentDocument?.manifest.viewport
                ?? TracePageViewport.full
        )
        return TraceDrawingPoint(
            x: sourceNormalized.x,
            y: sourceNormalized.y,
            pressure: point.pressure,
            tiltX: point.tiltX,
            tiltY: point.tiltY,
            twistDegrees: point.twistDegrees,
            connectsToPrevious: point.connectsToPrevious
        )
    }

    private func projectedPaperPoint(_ point: UnitPoint) -> TracePoint? {
        guard let calibration = calibratedSurface?.calibration,
              let document = currentDocument
        else {
            return nil
        }
        let source = document.manifest.sourceWindowBounds.map {
            TraceSize(width: $0.width, height: $0.height)
        } ?? TraceSize(
            width: Double(document.manifest.screenshotPixelWidth),
            height: Double(document.manifest.screenshotPixelHeight)
        )
        let viewport = document.manifest.viewport
            ?? TracePageViewport.full
        let visiblePage = TraceSize(
            width: source.width * viewport.width,
            height: source.height * viewport.height
        )
        let paperFrame = TracePageViewport.centeredFit(
            contentAspectRatio: calibration.estimatedAspectRatio,
            in: visiblePage
        )
        return TracePageViewport.unmap(
            TracePoint(x: point.x, y: point.y),
            through: paperFrame
        )
    }

    private func handleCalibration(_ update: CalibrationUpdate) {
        switch update {
        case let .pageRegistered(page, next):
            currentPage = page
            calibrationMessage = instruction(for: next)
        case .retryPageRegistration:
            calibrationMessage = "Touch once anywhere on the Ncode paper."
        case let .captured(_, _, next):
            calibrationMessage = instruction(for: next)
        case let .retry(corner, _):
            calibrationMessage = "Try the \(corner.displayName) corner again."
        case let .completed(surface):
            calibratedSurface = surface
            calibrationSession = nil
            calibrationMessage = "Paper calibrated."
            try? calibrationStore.save(surface)
            onCalibrationCompleted?(surface)
        }
        onStateChange?(snapshot)
    }

    private func beginCalibration() {
        calibrationSession = SurfaceCalibrationSession()
        calibrationMessage = "Touch once anywhere on the Ncode paper."
        strokeProcessor.reset()
        currentPage = nil
    }

    private func presentDocument(
        _ presentation: TraceDocumentPresentation,
        allowsInitialSetup: Bool = false
    ) {
        toolState = toolState.resettingCanvasToPen
        if !allowsInitialSetup {
            defaults.set(true, forKey: "TraceOnboardingComplete")
            setupVisible = false
            onStateChange?(snapshot)
        }
        onPresentDocument?(presentation)
    }

    private func enableInput() {
        guard !didEnableInput else {
            return
        }
        didEnableInput = true
        transport.enableOnlineData()
    }

    private func resetConnectionState(cancelVoice: Bool = true) {
        normalizer.resetConnectionState()
        clockSyncRequested = false
        clockSynchronized = false
        didEnableInput = false
        inputEnabled = false
        penStatus = nil
        penDeviceInfo = nil
        hoverSyncRequestPending = false
        currentPage = nil
        currentNotificationBatch = nil
        captureInput.cancelCapture()
        manualCaptureInFlight = false
        if cancelVoice {
            voiceController.cancel()
        }
        resetAnnotationState()
    }

    private func persistAppSettings() {
        TraceAppSettingsPreferences.save(appSettings, to: defaults)
        onStateChange?(snapshot)
    }

    private func resetAnnotationState() {
        clearHover()
        cancelScheduledAutosave()
        activeAnnotationStyle = nil
        activeDocumentStrokeID = nil
        activeStrokeStartedAtAppClockSeconds = nil
        strokeHistoryStart = nil
        strokeProcessor.reset()
        voiceController.setPerformanceCritical(false)
    }

    private func saveCurrentDocument() throws {
        cancelScheduledAutosave()
        try writeCurrentDocument()
    }

    private func writeCurrentDocument() throws {
        if let currentDocument {
            try drawingStore.save(currentDocument)
        }
    }

    private func scheduleAutosaveAfterIdle(for documentID: UUID) {
        autosaveWorkItem?.cancel()
        let token = autosaveGate.schedule()
        let workItem = DispatchWorkItem { [weak self] in
            guard let self,
                  self.autosaveGate.isCurrent(token),
                  self.activeDocumentStrokeID == nil,
                  self.currentDocument?.manifest.id == documentID
            else {
                return
            }
            self.autosaveWorkItem = nil
            do {
                try self.writeCurrentDocument()
                self.clearSaveError()
            } catch {
                self.reportSaveError(error)
            }
        }
        autosaveWorkItem = workItem
        DispatchQueue.main.asyncAfter(
            deadline: .now() + TraceAutosavePolicy.idleDelaySeconds,
            execute: workItem
        )
    }

    private func cancelScheduledAutosave() {
        autosaveWorkItem?.cancel()
        autosaveWorkItem = nil
        autosaveGate.cancel()
    }

    private func saveCurrentDocumentReportingError() -> Bool {
        do {
            try saveCurrentDocument()
            clearSaveError()
            return true
        } catch {
            reportSaveError(error)
            return false
        }
    }

    private func reportSaveError(_ error: Error) {
        lastError = "Trace could not autosave this drawing: "
            + error.localizedDescription
            + " The board will stay open so the work is not discarded."
        onStateChange?(snapshot)
    }

    private func clearSaveError() {
        if lastError?.hasPrefix("Trace could not autosave") == true {
            lastError = nil
        }
    }

    private func instruction(for corner: CalibrationCorner) -> String {
        "Touch the \(corner.displayName) paper corner."
    }

    func refreshAuthorizations() {
        if captureService.hasPermission,
           lastError?.contains("Screen Recording") == true
        {
            lastError = nil
        }
        if voiceController.microphoneAuthorization == .authorized,
           lastError?.contains("Microphone") == true
        {
            lastError = nil
        }
        onStateChange?(snapshot)
    }
}
