import AppKit
import Darwin
import NeoTransport
import ServiceManagement
import TraceAppCore
import UniformTypeIdentifiers

struct TraceCanvasImage {
    let image: NSImage
    let name: String
}

enum TraceOpenFileRequest {
    case drawing(URL)
    case images([TraceCanvasImage])
}

enum TraceOpenFilePolicy {
    static func request(
        for filenames: [String]
    ) -> TraceOpenFileRequest? {
        let urls = filenames.map(URL.init(fileURLWithPath:))
        guard !urls.isEmpty else {
            return nil
        }
        if urls.count == 1,
           let url = urls.first,
           url.pathExtension
                .caseInsensitiveCompare("traceboard") == .orderedSame
        {
            return .drawing(url)
        }

        var images: [TraceCanvasImage] = []
        images.reserveCapacity(urls.count)
        for url in urls {
            let resourceType = try? url.resourceValues(
                forKeys: [.contentTypeKey]
            ).contentType
            let contentType = resourceType
                ?? UTType(filenameExtension: url.pathExtension)
            guard contentType?.conforms(to: .image) == true,
                  let image = NSImage(contentsOf: url),
                  image.size.width > 0,
                  image.size.height > 0
            else {
                return nil
            }
            images.append(
                TraceCanvasImage(
                    image: image,
                    name: url.lastPathComponent
                )
            )
        }
        return .images(images)
    }
}

enum TraceOpenFileCoordinator {
    static func handle(
        _ request: TraceOpenFileRequest,
        openDrawing: (URL) -> Void,
        openImages: ([TraceCanvasImage]) -> Bool
    ) -> Bool {
        switch request {
        case let .drawing(url):
            openDrawing(url)
            return true
        case let .images(images):
            return openImages(images)
        }
    }
}

@MainActor
final class TraceOpenFileLifecycle {
    typealias Completion = (Bool) -> Void
    typealias Handler = ([String], @escaping Completion) -> Void

    private struct Delivery {
        let filenames: [String]
        let completion: Completion
    }

    private var pending: [Delivery] = []
    private var handler: Handler?

    func receive(
        _ filenames: [String],
        completion: @escaping Completion = { _ in }
    ) {
        let delivery = Delivery(
            filenames: filenames,
            completion: completion
        )
        guard let handler else {
            pending.append(delivery)
            return
        }
        handler(delivery.filenames, delivery.completion)
    }

    func activate(_ handler: @escaping Handler) {
        precondition(self.handler == nil)
        self.handler = handler
        let deliveries = pending
        pending.removeAll()
        for delivery in deliveries {
            handler(delivery.filenames, delivery.completion)
        }
    }
}

enum TraceOpenFileForwarding {
    static let notificationName = Notification.Name(
        "com.traceproject.app.open-files"
    )
    private static let filenamesKey = "filenames"

    static func payload(for filenames: [String]) -> [String: Any] {
        [filenamesKey: filenames]
    }

    static func filenames(from payload: [AnyHashable: Any]?) -> [String]? {
        guard let filenames = payload?[filenamesKey] as? [String],
              !filenames.isEmpty,
              filenames.allSatisfy({ !$0.isEmpty })
        else {
            return nil
        }
        return filenames
    }
}

enum TracePenMenuPresentation {
    static func title(
        deviceInfo: PenDeviceInfo?,
        batteryPercent: UInt8?
    ) -> String {
        guard let batteryPercent else {
            return deviceInfo == nil
                ? "Pen disconnected"
                : "\(displayName(for: deviceInfo)) · Connecting"
        }
        return "\(displayName(for: deviceInfo)) · \(batteryPercent)%"
    }

    static func displayName(for deviceInfo: PenDeviceInfo?) -> String {
        guard let deviceInfo else {
            return "NeoPen"
        }
        let model = deviceInfo.modelName.uppercased()
        let subName = deviceInfo.subName.uppercased()
        if model == "NWP-F50"
            || model == "NWP-F51"
            || subName == "M1"
            || subName.contains("_M1")
        {
            return "NeoPen M1+"
        }
        if !deviceInfo.subName.isEmpty {
            return deviceInfo.subName
        }
        return deviceInfo.modelName.isEmpty
            ? "NeoPen"
            : deviceInfo.modelName
    }
}

enum TraceAppSettingsMenuPresentation {
    static let connectedSection = "When pen is connected"
    static let captureScreenshot = "Capture screenshot"
    static let disconnectedSection = "When pen is disconnected"
    static let copyTraceAndClose = "Copy trace and close app"
    static let onCopySection = "On copy (cmd+c)"
    static let dictationSection = "Dictation"
    static let autoAnnotateDictation = "Annotate dictation automatically"
    static let annotationScale = "Annotation scale"
    static let launchInMenuBarAtLogin = "Launch in menu bar at login"
    static let copyEditMenuItemClosing = "Copy trace and close"
    static let copyEditMenuItemKeepingOpen = "Copy trace"

    static func copyEditMenuItemTitle(closesDocument: Bool) -> String {
        closesDocument ? copyEditMenuItemClosing : copyEditMenuItemKeepingOpen
    }

    @MainActor
    static func applyPenVisibility(
        isConnected: Bool,
        to items: [NSMenuItem]
    ) {
        for item in items {
            item.isHidden = !isConnected
        }
    }

    static func annotationScaleTitle(
        _ scale: TraceTranscriptAnnotationScale
    ) -> String {
        switch scale {
        case .small:
            return "Small (75%)"
        case .medium:
            return "Medium (100%)"
        case .large:
            return "Large (150%)"
        }
    }
}

enum TraceAppMenuPresentation {
    static let newBlankTrace = "New Blank trace"
    static let newScreenshotTrace = "New Screenshot trace"
    static let openTraces = "Open traces..."
    static let setup = "Setup"
}

enum TraceStatusItemPresentation {
    static let restingSymbolName = "pencil.tip"
    static let activeSymbolName = "pencil.tip.crop.circle.fill"

    static func symbolName(for phase: TraceAppPhase) -> String {
        switch phase {
        case .waitingForPen, .armed:
            return restingSymbolName
        case .capturing, .annotating:
            return activeSymbolName
        }
    }
}

enum TracePasteboardImageError: LocalizedError {
    case unsupportedFile(String)
    case unreadableFile(String)
    case noImage

    var errorDescription: String? {
        switch self {
        case let .unsupportedFile(name):
            return "\(name) is not a supported image file."
        case let .unreadableFile(name):
            return "Trace could not read the image file \(name)."
        case .noImage:
            return "The clipboard does not contain an image."
        }
    }
}

enum TracePasteboardImage {
    static func read(
        from pasteboard: NSPasteboard
    ) -> Result<[TraceCanvasImage], TracePasteboardImageError> {
        let fileURLs = (pasteboard.pasteboardItems ?? []).compactMap {
            item -> URL? in
            guard let value = item.string(forType: .fileURL),
                  let url = URL(string: value),
                  url.isFileURL
            else {
                return nil
            }
            return url
        }
        if !fileURLs.isEmpty {
            var images: [TraceCanvasImage] = []
            images.reserveCapacity(fileURLs.count)
            for url in fileURLs {
                let resourceType = try? url.resourceValues(
                    forKeys: [.contentTypeKey]
                ).contentType
                let contentType = resourceType
                    ?? UTType(filenameExtension: url.pathExtension)
                guard contentType?.conforms(to: .image) == true else {
                    return .failure(
                        .unsupportedFile(url.lastPathComponent)
                    )
                }
                guard let image = NSImage(contentsOf: url),
                      image.size.width > 0,
                      image.size.height > 0
                else {
                    return .failure(
                        .unreadableFile(url.lastPathComponent)
                    )
                }
                images.append(
                    TraceCanvasImage(
                        image: image,
                        name: url.lastPathComponent
                    )
                )
            }
            return .success(images)
        }

        let images = (
            pasteboard.readObjects(
                forClasses: [NSImage.self],
                options: nil
            ) as? [NSImage] ?? []
        ).filter {
            $0.size.width > 0 && $0.size.height > 0
        }
        guard !images.isEmpty else {
            return .failure(.noImage)
        }
        return .success(
            images.enumerated().map { index, image in
                TraceCanvasImage(
                    image: image,
                    name: images.count == 1
                        ? "Pasted image"
                        : "Pasted image \(index + 1)"
                )
            }
        )
    }

    static func canRead(from pasteboard: NSPasteboard) -> Bool {
        if (pasteboard.pasteboardItems ?? []).contains(where: {
            $0.availableType(from: [.fileURL]) != nil
        }) {
            return true
        }
        return pasteboard.canReadObject(
            forClasses: [NSImage.self],
            options: nil
        )
    }
}

@MainActor
final class TraceAppDelegate:
    NSObject,
    NSApplicationDelegate,
    NSMenuItemValidation
{
    private enum DrawingEditSource {
        case native
        case tldraw
    }

    private let model = TraceAppModel()
    private let board = TraceBoardWindowController()
    private let projection = TraceProjectionCoordinator()
    private let globalShortcuts = TraceGlobalShortcutManager()
    private var statusItem: NSStatusItem?
    private weak var statusMenu: NSMenu?
    private var statusShortcutMenuItems:
        [TraceGlobalShortcutAction: [NSMenuItem]] = [:]
    private var fileShortcutMenuItems:
        [TraceGlobalShortcutAction: [NSMenuItem]] = [:]
    private var projectionMenuItems: [NSMenuItem] = []
    private var projectionMenuAnchor: NSMenuItem?
    private var penSettingsItem: NSMenuItem?
    private var penStatusItem: NSMenuItem?
    private var penBeepItem: NSMenuItem?
    private var penHoverItem: NSMenuItem?
    private var penOfflineItem: NSMenuItem?
    private var penAutoPowerItem: NSMenuItem?
    private var penCapPowerItem: NSMenuItem?
    private var penSensitivityMenuItem: NSMenuItem?
    private var penAutoOffItems: [NSMenuItem] = []
    private var penSensitivityItems: [NSMenuItem] = []
    private var captureOnCapOffItem: NSMenuItem?
    private var copyOnDisconnectItem: NSMenuItem?
    private var penAppSettingsItems: [NSMenuItem] = []
    private var copyOnCopyItem: NSMenuItem?
    private var autoAnnotateDictationItem: NSMenuItem?
    private var launchInMenuBarAtLoginItem: NSMenuItem?
    private var copyEditItem: NSMenuItem?
    private var transcriptAnnotationScaleItems:
        [TraceTranscriptAnnotationScale: NSMenuItem] = [:]
    private var copyProgress = TraceDocumentCopyProgress()
    private var undoEditSources: [DrawingEditSource] = []
    private var redoEditSources: [DrawingEditSource] = []
    private var terminationFlushInProgress = false
    private var terminationReady = false
    private var liveSessionLock: TracePenSessionLock?
    private let openFileLifecycle = TraceOpenFileLifecycle()
    private var openFileForwardingObserver: NSObjectProtocol?
    private var startupErrorWorkItem: DispatchWorkItem?
    private var forwardedOpenFiles = false

    func applicationDidFinishLaunching(_ notification: Notification) {
#if DEBUG
        let environment = ProcessInfo.processInfo.environment
        let isUIPreview = environment["TRACE_UI_SNAPSHOT"] != nil
            || environment["TRACE_UI_COMPOSITE"] != nil
            || environment["TRACE_UI_NO_HARDWARE"] == "1"
            || environment["TRACE_RETAINED_INK_PROBE"] == "1"
            || environment["TRACE_PRODUCT_TLDRAW_PROBE"] == "1"
#else
        let isUIPreview = false
#endif
        if !isUIPreview {
            do {
                liveSessionLock = try TracePenSessionLock()
            } catch {
                becomeOpenFileForwarder(startupError: error)
                return
            }
            startOpenFileForwardingListener()
        }
#if DEBUG
        if environment["TRACE_PRODUCT_TLDRAW_PROBE"] == "1" {
            NSApp.setActivationPolicy(.accessory)
            Task { @MainActor in
                do {
                    try await ProductTldrawProbe.run()
                    print("product tldraw probe passed")
                    NSApp.terminate(nil)
                } catch {
                    fputs(
                        "product tldraw probe failed: "
                            + error.localizedDescription
                            + "\n",
                        stderr
                    )
                    exit(1)
                }
            }
            return
        }
#endif
        configureBoard()
        configureStatusItem()
        configureMainMenu()
        if !isUIPreview {
            do {
                try updateLaunchInMenuBarAtLogin(
                    enabled:
                        model.snapshot.appSettings.launchInMenuBarAtLogin
                )
            } catch {
                showSettingsError(
                    "Trace could not update its launch-at-login setting: "
                        + error.localizedDescription
                )
            }
        }
        projection.onDisplaysChange = { [weak self] in
            self?.refreshProjectionMenu()
        }
        projection.onEditorVisibilityChange = { [weak self] visible in
            self?.board.setEditorVisible(visible)
        }
        projection.workingScreenProvider = { [weak self] in
            self?.board.workingScreen
        }
        model.onStateChange = { [weak self] snapshot in
            self?.update(snapshot)
        }
        model.onShowOnboarding = { [weak self] in
            guard let self else {
                return
            }
            NSApp.setActivationPolicy(.accessory)
            self.board.showOnboarding(
                self.model.snapshot,
                shortcuts: self.globalShortcuts.snapshot
            )
        }
        model.onPresentDocument = {
            [weak self] presentation in
            guard let self else {
                return
            }
            self.prepareForDocumentPresentation()
            NSApp.setActivationPolicy(.regular)
            var toolState = self.model.toolState
#if DEBUG
            if let rawGridStyle = ProcessInfo.processInfo.environment[
                "TRACE_UI_GRID"
            ],
            let gridStyle = TraceGridStyle(rawValue: rawGridStyle)
            {
                toolState.gridStyle = gridStyle
            }
            if let rawGridSpacing = ProcessInfo.processInfo.environment[
                "TRACE_UI_GRID_SPACING"
            ],
            let gridSpacing = Int(rawGridSpacing)
            {
                toolState.gridSpacingPoints = TraceGridPolicy.clampedSpacing(
                    gridSpacing
                )
            }
#endif
            self.board.present(
                presentation.document,
                capture: presentation.capture,
                toolState: toolState
            )
            self.projection.present(
                presentation.document,
                toolState: toolState,
                activatesProjectOutput:
                    presentation.activatesProjectOutput
            )
        }
        model.onHideBoard = { [weak self] in
            self?.board.hideBoard()
            self?.projection.hideProjection()
            NSApp.setActivationPolicy(.accessory)
        }
        model.onCopyRequested = { [weak self] in
            guard let self else { return }
            self.copyCurrentDrawing(
                closesDocument:
                    TraceAppBehaviorPolicy.shouldCloseAfterManualCopy(
                        settings: self.model.snapshot.appSettings
                    )
            )
        }
        model.onAnnotationUpdate = { [weak self] update in
            self?.board.apply(update)
            self?.projection.apply(update)
            if update.isFinal {
                self?.recordDrawingEdit(.native)
            }
        }
        model.onHoverUpdate = { [weak self] update in
            self?.board.updateHover(update)
            self?.projection.updateHover(update)
        }
        model.onDrawingHistoryChange = { [weak self] in
            self?.board.refreshDrawingHistory()
            self?.projection.refreshDrawingHistory()
        }
        model.onTranscriptAnnotationsChange = { [weak self] in
            self?.board.refreshTranscriptAnnotations()
            self?.projection.refreshTranscriptAnnotations()
        }
        model.onVoiceLevelChange = { [weak self] level in
            self?.board.updateVoiceLevel(level)
        }
        openFileLifecycle.activate { [weak self] filenames, completion in
            self?.handleOpenFiles(filenames, completion: completion)
        }
        if !isUIPreview {
            configureGlobalShortcuts()
            model.start()
        }
        projection.start()
#if DEBUG
        if ProcessInfo.processInfo.environment[
            "TRACE_UI_CALIBRATION"
        ] == "1" {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                self.model.recalibrate()
            }
        } else if ProcessInfo.processInfo.environment[
            "TRACE_UI_ONBOARDING"
        ] == "1" {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                self.model.showOnboarding()
            }
        }
        if let documentPath = ProcessInfo.processInfo.environment[
            "TRACE_UI_DOCUMENT"
        ] {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) {
                self.model.openDrawing(
                    from: URL(fileURLWithPath: documentPath)
                )
            }
        }
        if let snapshotPath = ProcessInfo.processInfo.environment[
            "TRACE_UI_SNAPSHOT"
        ] {
            DispatchQueue.main.asyncAfter(deadline: .now() + 1) {
                try? self.board.writeSnapshot(
                    to: URL(fileURLWithPath: snapshotPath)
                )
                NSApp.terminate(nil)
            }
        }
        if let compositePath = ProcessInfo.processInfo.environment[
            "TRACE_UI_COMPOSITE"
        ] {
            DispatchQueue.main.asyncAfter(deadline: .now() + 1) {
                try? self.board.writeComposite(
                    to: URL(fileURLWithPath: compositePath)
                )
                NSApp.terminate(nil)
            }
        }
        if let rawStrokeIDs = ProcessInfo.processInfo.environment[
            "TRACE_UI_SELECTED_STROKE"
        ] {
            let strokeIDs = Set(
                rawStrokeIDs
                    .split(separator: ",")
                    .compactMap { UInt64($0) }
            )
            guard !strokeIDs.isEmpty else {
                return
            }
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                self.board.selectStrokesForPreview(strokeIDs)
                if let rawMove = ProcessInfo.processInfo.environment[
                    "TRACE_UI_MOVE_SELECTED"
                ] {
                    let values = rawMove
                        .split(separator: ",")
                        .compactMap { Double($0) }
                    if values.count == 2 {
                        self.board.moveSelectedStrokesForPreview(
                            delta: TracePoint(
                                x: values[0],
                                y: values[1]
                            )
                        )
                    }
                }
                if ProcessInfo.processInfo.environment[
                    "TRACE_UI_DELETE_SELECTED"
                ] == "1" {
                    self.board.deleteSelectedStrokesForPreview()
                }
            }
        }
        if ProcessInfo.processInfo.environment[
            "TRACE_RETAINED_INK_PROBE"
        ] == "1" {
            DispatchQueue.main.async {
                do {
                    try TraceRetainedInkProbe.run(
                        board: self.board,
                        setCopyProgress: {
                            self.setCopyProgressForTesting($0)
                        }
                    )
                    NSApp.terminate(nil)
                } catch {
                    fputs(
                        "retained-ink probe failed: "
                            + error.localizedDescription
                            + "\n",
                        stderr
                    )
                    exit(1)
                }
            }
        }
#endif
    }

    func applicationWillTerminate(_ notification: Notification) {
        if let openFileForwardingObserver {
            DistributedNotificationCenter.default().removeObserver(
                openFileForwardingObserver
            )
        }
        globalShortcuts.stop()
        projection.stop()
        model.stop()
    }

    func applicationShouldTerminate(
        _ sender: NSApplication
    ) -> NSApplication.TerminateReply {
        if terminationReady {
            return .terminateNow
        }
        if terminationFlushInProgress {
            return .terminateLater
        }
        guard model.snapshot.currentDocument != nil else {
            return .terminateNow
        }
        terminationFlushInProgress = true
        board.flushTldrawSnapshot { [weak self, weak sender] in
            guard let self, let sender else {
                return
            }
            self.terminationReady = true
            self.terminationFlushInProgress = false
            sender.reply(toApplicationShouldTerminate: true)
        }
        return .terminateLater
    }

    func applicationDidBecomeActive(_ notification: Notification) {
        model.refreshAuthorizations()
    }

    func applicationShouldTerminateAfterLastWindowClosed(
        _ sender: NSApplication
    ) -> Bool {
        false
    }

    func applicationSupportsSecureRestorableState(
        _ app: NSApplication
    ) -> Bool {
        true
    }

    func application(
        _ sender: NSApplication,
        openFiles filenames: [String]
    ) {
        openFileLifecycle.receive(filenames) { [weak sender] opened in
            sender?.reply(
                toOpenOrPrint: opened ? .success : .failure
            )
        }
    }

    private func handleOpenFiles(
        _ filenames: [String],
        completion: @escaping (Bool) -> Void
    ) {
        guard let request = TraceOpenFilePolicy.request(
                  for: filenames
              )
        else {
            completion(false)
            return
        }
        withFlushedTldrawSnapshot { [weak self] in
            guard let self else {
                completion(false)
                return
            }
            let opened = TraceOpenFileCoordinator.handle(
                request,
                openDrawing: self.model.openDrawing(from:),
                openImages: self.openImageSelection
            )
            completion(opened)
        }
    }

    private func startOpenFileForwardingListener() {
        openFileForwardingObserver = DistributedNotificationCenter.default()
            .addObserver(
                forName: TraceOpenFileForwarding.notificationName,
                object: nil,
                queue: .main
            ) { [weak self] notification in
                guard let filenames = TraceOpenFileForwarding.filenames(
                          from: notification.userInfo
                      )
                else {
                    return
                }
                MainActor.assumeIsolated {
                    self?.openFileLifecycle.receive(filenames)
                }
            }
    }

    private func becomeOpenFileForwarder(startupError: Error) {
        openFileLifecycle.activate { [weak self] filenames, completion in
            DistributedNotificationCenter.default().postNotificationName(
                TraceOpenFileForwarding.notificationName,
                object: nil,
                userInfo: TraceOpenFileForwarding.payload(
                    for: filenames
                ),
                deliverImmediately: true
            )
            self?.forwardedOpenFiles = true
            self?.startupErrorWorkItem?.cancel()
            completion(true)
            NSApp.terminate(nil)
        }

        let workItem = DispatchWorkItem { [weak self] in
            guard let self, !self.forwardedOpenFiles else {
                return
            }
            self.showStartupError(startupError)
            NSApp.terminate(nil)
        }
        startupErrorWorkItem = workItem
        DispatchQueue.main.asyncAfter(
            deadline: .now() + 0.5,
            execute: workItem
        )
    }

    private func configureBoard() {
        board.onClose = { [weak self] in
            self?.model.closeBoard()
        }
        board.onToolChange = { [weak self] state in
            self?.model.updateToolState(state)
            self?.projection.updateToolState(state)
        }
        board.onDocumentEdited = { [weak self] before, after in
            self?.recordDrawingEdit(.native)
            self?.model.recordManualDrawingEdit(
                before: before,
                after: after
            )
        }
        board.onTldrawSnapshotChange = {
            [weak self] snapshotJSON, timedShapes in
            self?.model.updateTldrawSnapshot(
                snapshotJSON,
                timedShapes: timedShapes
            )
            self?.projection.refreshTldrawSnapshot()
        }
        board.onTldrawUserEdit = { [weak self] count in
            guard let self else {
                return
            }
            for _ in 0..<max(1, count) {
                self.recordDrawingEdit(.tldraw)
            }
        }
        board.onCopy = { [weak self] content in
            guard let self else { return }
            self.copyCurrentDrawing(
                content,
                closesDocument:
                    TraceAppBehaviorPolicy.shouldCloseAfterManualCopy(
                        settings: self.model.snapshot.appSettings
                    )
            )
        }
        board.onCompleteOnboarding = { [weak self] in
            self?.model.completeOnboarding()
        }
        board.onRequestScreenAccess = { [weak self] in
            self?.model.requestScreenCaptureAccess()
        }
        board.onRequestMicrophoneAccess = { [weak self] in
            self?.model.requestMicrophoneAccess()
        }
        board.onSaveOpenRouterAPIKey = { [weak self] apiKey in
            self?.model.saveOpenRouterAPIKey(apiKey)
        }
        board.onRemoveOpenRouterAPIKey = { [weak self] in
            self?.model.removeOpenRouterAPIKey()
        }
        board.onToggleVoiceRecording = { [weak self] in
            self?.model.toggleVoiceRecording()
        }
        board.onBackgroundColorChange = { [weak self] color in
            self?.model.updatePageBackground(color)
            self?.projection.refreshBackground(color)
        }
        board.onWorkingScreenChange = { [weak self] in
            self?.projection.workingDisplayDidChange()
        }
        board.onRecalibrate = { [weak self] in
            self?.model.recalibrate()
        }
        board.onCancelCalibration = { [weak self] in
            self?.model.cancelCalibration()
        }
        board.onBlankViewportResize = { [weak self] size in
            self?.model.recordBlankViewportSize(size)
        }
        board.onGlobalShortcutsChange = { [weak self] in
            self?.globalShortcuts.shortcutsDidChange()
        }
        model.onCalibrationCompleted = { [weak self] surface in
            guard let self,
                  let size = self.board.calibratedBlankViewportSize(
                      aspectRatio:
                          surface.calibration.estimatedAspectRatio
                  )
            else {
                return
            }
            let backingScale =
                self.board.workingScreen?.backingScaleFactor ?? 2
            self.model.resizeCurrentBlankForCalibration(
                to: size,
                backingScale: backingScale
            )
            self.board.applyCurrentDocumentGeometry()
            self.projection.refreshGeometry()
        }
    }

    private func configureStatusItem() {
        let item = NSStatusBar.system.statusItem(
            withLength: NSStatusItem.squareLength
        )
        item.button?.image = statusImage(
            named: TraceStatusItemPresentation.restingSymbolName,
            description: "Trace"
        )
        item.button?.image?.isTemplate = true

        let menu = NSMenu()

        let showBoard = NSMenuItem(
            title: TraceAppMenuPresentation.newBlankTrace,
            action: #selector(showBoard),
            keyEquivalent: ""
        )
        showBoard.target = self
        menu.addItem(showBoard)

        let capture = NSMenuItem(
            title: TraceAppMenuPresentation.newScreenshotTrace,
            action: #selector(newCapture),
            keyEquivalent: ""
        )
        capture.target = self
        menu.addItem(capture)
        statusShortcutMenuItems = [
            .newBlankTrace: [showBoard],
            .captureFrontmostApp: [capture],
        ]
        TraceGlobalShortcutMenuPresentation.apply(
            globalShortcuts.snapshot,
            to: statusShortcutMenuItems
        )
        menu.addItem(.separator())

        let open = NSMenuItem(
            title: TraceAppMenuPresentation.openTraces,
            action: #selector(revealDrawings),
            keyEquivalent: "o"
        )
        open.target = self
        menu.addItem(open)
        menu.addItem(.separator())

        let setup = NSMenuItem(
            title: TraceAppMenuPresentation.setup,
            action: #selector(showSetup),
            keyEquivalent: ","
        )
        setup.target = self
        menu.addItem(setup)

        let penSettings = NSMenuItem(
            title: "Pen disconnected",
            action: nil,
            keyEquivalent: ""
        )
        let penMenu = NSMenu(title: "Pen")
        let penStatus = NSMenuItem(
            title: "Pen disconnected",
            action: nil,
            keyEquivalent: ""
        )
        penStatus.isEnabled = false
        penMenu.addItem(penStatus)
        penMenu.addItem(.separator())
        let beep = penToggleItem(
            title: "Blip Sound",
            action: #selector(togglePenBeep(_:))
        )
        let hover = penToggleItem(
            title: "Hover Mode",
            action: #selector(togglePenHover(_:))
        )
        let offline = penToggleItem(
            title: "Store Drawings in Pen Memory",
            action: #selector(togglePenOfflineStorage(_:))
        )
        let autoPower = penToggleItem(
            title: "Auto Power On",
            action: #selector(togglePenAutoPower(_:))
        )
        let capPower = penToggleItem(
            title: "Power Off with Cap",
            action: #selector(togglePenCapPower(_:))
        )
        [beep, hover, offline, autoPower, capPower].forEach(
            penMenu.addItem
        )
        penMenu.addItem(.separator())

        let autoOff = NSMenuItem(
            title: "Auto Power Off",
            action: nil,
            keyEquivalent: ""
        )
        let autoOffMenu = NSMenu(title: "Auto Power Off")
        penAutoOffItems = [1, 10, 20, 30, 40].map { minutes in
            let item = NSMenuItem(
                title: "\(minutes) min",
                action: #selector(changePenAutoOff(_:)),
                keyEquivalent: ""
            )
            item.target = self
            item.representedObject = minutes
            autoOffMenu.addItem(item)
            return item
        }
        autoOff.submenu = autoOffMenu
        penMenu.addItem(autoOff)

        let sensitivity = NSMenuItem(
            title: "Pressure Sensitivity",
            action: nil,
            keyEquivalent: ""
        )
        let sensitivityMenu = NSMenu(title: "Pressure Sensitivity")
        penSensitivityItems = (0...3).map { step in
            let item = NSMenuItem(
                title: "Level \(step)",
                action: #selector(changePenSensitivity(_:)),
                keyEquivalent: ""
            )
            item.target = self
            item.representedObject = step
            sensitivityMenu.addItem(item)
            return item
        }
        sensitivity.submenu = sensitivityMenu
        penMenu.addItem(sensitivity)
        penSettings.submenu = penMenu
        penSettings.isHidden = true
        menu.addItem(penSettings)
        penSettingsItem = penSettings
        penStatusItem = penStatus
        penBeepItem = beep
        penHoverItem = hover
        penOfflineItem = offline
        penAutoPowerItem = autoPower
        penCapPowerItem = capPower
        penSensitivityMenuItem = sensitivity

        let appSettings = NSMenuItem(
            title: "Settings",
            action: nil,
            keyEquivalent: ""
        )
        let appSettingsMenu = NSMenu(title: "Settings")
        let connectedSection = NSMenuItem(
            title: TraceAppSettingsMenuPresentation.connectedSection,
            action: nil,
            keyEquivalent: ""
        )
        connectedSection.isEnabled = false
        appSettingsMenu.addItem(connectedSection)
        let captureOnCapOff = penToggleItem(
            title: TraceAppSettingsMenuPresentation.captureScreenshot,
            action: #selector(toggleCaptureOnCapOff(_:))
        )
        appSettingsMenu.addItem(captureOnCapOff)
        let connectedSeparator = NSMenuItem.separator()
        appSettingsMenu.addItem(connectedSeparator)
        let disconnectedSection = NSMenuItem(
            title: TraceAppSettingsMenuPresentation.disconnectedSection,
            action: nil,
            keyEquivalent: ""
        )
        disconnectedSection.isEnabled = false
        appSettingsMenu.addItem(disconnectedSection)
        let copyOnDisconnect = penToggleItem(
            title: TraceAppSettingsMenuPresentation.copyTraceAndClose,
            action: #selector(toggleCopyOnDisconnect(_:))
        )
        appSettingsMenu.addItem(copyOnDisconnect)
        let disconnectedSeparator = NSMenuItem.separator()
        appSettingsMenu.addItem(disconnectedSeparator)
        let onCopySection = NSMenuItem(
            title: TraceAppSettingsMenuPresentation.onCopySection,
            action: nil,
            keyEquivalent: ""
        )
        onCopySection.isEnabled = false
        appSettingsMenu.addItem(onCopySection)
        let copyOnCopy = penToggleItem(
            title: TraceAppSettingsMenuPresentation.copyTraceAndClose,
            action: #selector(toggleCopyOnCopy(_:))
        )
        appSettingsMenu.addItem(copyOnCopy)
        appSettingsMenu.addItem(.separator())
        let dictationSection = NSMenuItem(
            title: TraceAppSettingsMenuPresentation.dictationSection,
            action: nil,
            keyEquivalent: ""
        )
        dictationSection.isEnabled = false
        appSettingsMenu.addItem(dictationSection)
        let autoAnnotateDictation = penToggleItem(
            title:
                TraceAppSettingsMenuPresentation
                    .autoAnnotateDictation,
            action: #selector(toggleAutoAnnotateDictation(_:))
        )
        appSettingsMenu.addItem(autoAnnotateDictation)
        let annotationScale = NSMenuItem(
            title: TraceAppSettingsMenuPresentation.annotationScale,
            action: nil,
            keyEquivalent: ""
        )
        let annotationScaleMenu = NSMenu(
            title: TraceAppSettingsMenuPresentation.annotationScale
        )
        for scale in TraceTranscriptAnnotationScale.allCases {
            let item = NSMenuItem(
                title:
                    TraceAppSettingsMenuPresentation
                        .annotationScaleTitle(scale),
                action: #selector(changeTranscriptAnnotationScale(_:)),
                keyEquivalent: ""
            )
            item.target = self
            item.representedObject = scale.rawValue
            annotationScaleMenu.addItem(item)
            transcriptAnnotationScaleItems[scale] = item
        }
        annotationScale.submenu = annotationScaleMenu
        appSettingsMenu.addItem(annotationScale)
        appSettingsMenu.addItem(.separator())
        let launchInMenuBarAtLogin = penToggleItem(
            title:
                TraceAppSettingsMenuPresentation
                    .launchInMenuBarAtLogin,
            action: #selector(toggleLaunchInMenuBarAtLogin(_:))
        )
        appSettingsMenu.addItem(launchInMenuBarAtLogin)
        appSettings.submenu = appSettingsMenu
        menu.addItem(appSettings)
        captureOnCapOffItem = captureOnCapOff
        copyOnDisconnectItem = copyOnDisconnect
        penAppSettingsItems = [
            connectedSection,
            captureOnCapOff,
            connectedSeparator,
            disconnectedSection,
            copyOnDisconnect,
            disconnectedSeparator,
        ]
        TraceAppSettingsMenuPresentation.applyPenVisibility(
            isConnected: false,
            to: penAppSettingsItems
        )
        copyOnCopyItem = copyOnCopy
        autoAnnotateDictationItem = autoAnnotateDictation
        launchInMenuBarAtLoginItem = launchInMenuBarAtLogin
        let projectionAnchor = NSMenuItem.separator()
        menu.addItem(projectionAnchor)
        projectionMenuAnchor = projectionAnchor

        let quit = NSMenuItem(
            title: "Quit Trace",
            action: #selector(quit),
            keyEquivalent: "q"
        )
        quit.target = self
        menu.addItem(quit)

        item.menu = menu
        statusItem = item
        statusMenu = menu
        refreshProjectionMenu()
    }

    private func configureMainMenu() {
        let main = NSMenu()
        let appMenuItem = NSMenuItem()
        main.addItem(appMenuItem)
        let appMenu = NSMenu()
        appMenu.addItem(
            withTitle: "About Trace",
            action: #selector(NSApplication.orderFrontStandardAboutPanel(_:)),
            keyEquivalent: ""
        )
        appMenu.addItem(.separator())
        let quitItem = NSMenuItem(
            title: "Quit Trace",
            action: #selector(quit),
            keyEquivalent: "q"
        )
        quitItem.target = self
        appMenu.addItem(quitItem)
        appMenuItem.submenu = appMenu

        let fileItem = NSMenuItem()
        main.addItem(fileItem)
        let fileMenu = NSMenu(title: "File")
        let blankItem = NSMenuItem(
            title: TraceAppMenuPresentation.newBlankTrace,
            action: #selector(showBoard),
            keyEquivalent: ""
        )
        blankItem.target = self
        fileMenu.addItem(blankItem)
        let newItem = NSMenuItem(
            title: TraceAppMenuPresentation.newScreenshotTrace,
            action: #selector(newCapture),
            keyEquivalent: ""
        )
        newItem.target = self
        fileMenu.addItem(newItem)
        fileShortcutMenuItems = [
            .newBlankTrace: [blankItem],
            .captureFrontmostApp: [newItem],
        ]
        TraceGlobalShortcutMenuPresentation.apply(
            globalShortcuts.snapshot,
            to: fileShortcutMenuItems
        )
        fileMenu.addItem(.separator())
        let openItem = NSMenuItem(
            title: TraceAppMenuPresentation.openTraces,
            action: #selector(revealDrawings),
            keyEquivalent: "o"
        )
        openItem.target = self
        fileMenu.addItem(openItem)
        fileMenu.addItem(.separator())
        let closeItem = NSMenuItem(
            title: "Close trace",
            action: #selector(closeBoard),
            keyEquivalent: "w"
        )
        closeItem.target = self
        fileMenu.addItem(closeItem)
        fileItem.submenu = fileMenu

        let editItem = NSMenuItem()
        main.addItem(editItem)
        let editMenu = NSMenu(title: "Edit")
        let undoItem = NSMenuItem(
            title: "Undo",
            action: #selector(undoDrawing(_:)),
            keyEquivalent: "z"
        )
        undoItem.target = self
        editMenu.addItem(undoItem)
        let redoItem = NSMenuItem(
            title: "Redo",
            action: #selector(redoDrawing(_:)),
            keyEquivalent: "z"
        )
        redoItem.keyEquivalentModifierMask = [.command, .shift]
        redoItem.target = self
        editMenu.addItem(redoItem)
        editMenu.addItem(.separator())
        let copyItem = NSMenuItem(
            title: TraceAppSettingsMenuPresentation.copyEditMenuItemTitle(
                closesDocument:
                    TraceAppBehaviorPolicy.shouldCloseAfterManualCopy(
                        settings: model.snapshot.appSettings
                    )
            ),
            action: #selector(copyDrawing),
            keyEquivalent: "c"
        )
        copyItem.target = self
        editMenu.addItem(copyItem)
        copyEditItem = copyItem
        let pasteItem = NSMenuItem(
            title: "Paste image",
            action: #selector(pasteImage(_:)),
            keyEquivalent: "v"
        )
        pasteItem.target = self
        editMenu.addItem(pasteItem)
        editItem.submenu = editMenu
        NSApp.mainMenu = main
    }

    private func update(_ snapshot: TraceAppSnapshot) {
        board.updateVoiceState(
            snapshot.voiceState,
            dictationConfigured:
                snapshot.dictationConfigured
        )
        updatePenSettings(
            snapshot.penStatus,
            deviceInfo: snapshot.penDeviceInfo,
            desiredHoverEnabled: snapshot.desiredHoverEnabled
        )
        updateAppSettings(snapshot.appSettings)
        board.updateOnboarding(
            snapshot,
            shortcuts: globalShortcuts.snapshot
        )
        statusItem?.button?.image = statusImage(
            named: TraceStatusItemPresentation.symbolName(
                for: snapshot.phase
            ),
            description: statusText(snapshot)
        )
        statusItem?.button?.image?.isTemplate = true
    }

    private func configureGlobalShortcuts() {
        globalShortcuts.onAction = { [weak self] action in
            guard let self else {
                return
            }
            TraceGlobalShortcutActionDispatch.perform(
                action,
                newBlankTrace: { self.showBoard() },
                captureFrontmostApp: { self.newCapture() }
            )
        }
        globalShortcuts.onChange = { [weak self] shortcuts in
            guard let self else {
                return
            }
            TraceGlobalShortcutMenuPresentation.apply(
                shortcuts,
                to: self.statusShortcutMenuItems
            )
            TraceGlobalShortcutMenuPresentation.apply(
                shortcuts,
                to: self.fileShortcutMenuItems
            )
            self.board.updateOnboarding(
                self.model.snapshot,
                shortcuts: shortcuts
            )
        }
        globalShortcuts.start()
    }

    private func statusText(_ snapshot: TraceAppSnapshot) -> String {
        if let error = snapshot.lastError {
            return "Trace — \(error)"
        }
        switch snapshot.phase {
        case .waitingForPen:
            return snapshot.appSettings.captureScreenshotOnCapOff
                ? "Trace — Remove cap to capture front window"
                : "Trace — Remove cap to connect pen"
        case .armed:
            return snapshot.appSettings.captureScreenshotOnCapOff
                ? "Trace — Cycle cap or press ⌘N for a new capture"
                : "Trace — Pen ready · Press ⌘N for a screenshot"
        case .capturing:
            return "Trace — Capturing window"
        case .annotating:
            switch snapshot.voiceState {
            case .transcribing:
                return "Trace — Preparing dictation"
            case .recording:
                return "Trace — Annotating · Recording"
            case .paused:
                return "Trace — Voice recording stopped"
            case .failed:
                return "Trace — Dictation needs retry"
            default:
                return "Trace — Annotating"
            }
        }
    }

    private func statusImage(
        named symbolName: String,
        description: String
    ) -> NSImage? {
        NSImage(
            systemSymbolName: symbolName,
            accessibilityDescription: description
        ) ?? NSImage(
            systemSymbolName: "pencil",
            accessibilityDescription: description
        )
    }

    private func penToggleItem(
        title: String,
        action: Selector
    ) -> NSMenuItem {
        let item = NSMenuItem(
            title: title,
            action: action,
            keyEquivalent: ""
        )
        item.target = self
        return item
    }

    private func updatePenSettings(
        _ status: PenDeviceStatus?,
        deviceInfo: PenDeviceInfo?,
        desiredHoverEnabled: Bool?
    ) {
        let enabled = status != nil
        penSettingsItem?.isHidden = !enabled
        penSettingsItem?.isEnabled = enabled
        TraceAppSettingsMenuPresentation.applyPenVisibility(
            isConnected: enabled,
            to: penAppSettingsItems
        )
        penSettingsItem?.title = TracePenMenuPresentation.title(
            deviceInfo: deviceInfo,
            batteryPercent: status?.batteryPercent
        )
        guard let status else {
            penStatusItem?.title = "Pen disconnected"
            return
        }
        penStatusItem?.title = [
            "Storage \(status.usedStoragePercent)%",
            "Max force \(status.maxForce)",
        ].joined(separator: " · ")
        penBeepItem?.state = status.beepEnabled ? .on : .off
        penHoverItem?.state = TraceHoverSyncPolicy.displayedState(
            desired: desiredHoverEnabled,
            reported: status.hoverEnabled
        ) ? .on : .off
        penOfflineItem?.state = status.offlineDataEnabled ? .on : .off
        penAutoPowerItem?.state = status.autoPowerOnEnabled ? .on : .off
        penCapPowerItem?.state =
            status.penCapPowerOffEnabled ? .on : .off
        for item in penAutoOffItems {
            item.state = item.representedObject as? Int
                == Int(status.autoPowerOffMinutes) ? .on : .off
        }
        let sensitivityWritable =
            deviceInfo?.pressureSensorType == 0
        penSensitivityMenuItem?.title = sensitivityWritable
            ? "Pressure Sensitivity"
            : "Pressure Sensitivity (Read-only)"
        for item in penSensitivityItems {
            item.state = item.representedObject as? Int
                == status.pressureSensitivityStep.map(Int.init)
                ? .on
                : .off
            item.isEnabled = status.pressureSensitivityStep != nil
                && sensitivityWritable
        }
    }

    private func updateAppSettings(_ settings: TraceAppSettings) {
        captureOnCapOffItem?.state =
            settings.captureScreenshotOnCapOff ? .on : .off
        copyOnDisconnectItem?.state =
            settings.copyTraceAndCloseOnDisconnect ? .on : .off
        copyOnCopyItem?.state =
            settings.copyTraceAndCloseOnCopy ? .on : .off
        autoAnnotateDictationItem?.state =
            settings.autoAnnotateDictation ? .on : .off
        launchInMenuBarAtLoginItem?.state =
            settings.launchInMenuBarAtLogin ? .on : .off
        copyEditItem?.title =
            TraceAppSettingsMenuPresentation.copyEditMenuItemTitle(
                closesDocument:
                    TraceAppBehaviorPolicy.shouldCloseAfterManualCopy(
                        settings: settings
                    )
            )
        for (scale, item) in transcriptAnnotationScaleItems {
            item.state = settings.transcriptAnnotationScale == scale
                ? .on
                : .off
        }
        board.updateTranscriptAnnotationScale(
            settings.transcriptAnnotationScale
        )
        projection.updateTranscriptAnnotationScale(
            settings.transcriptAnnotationScale
        )
    }

    private func refreshProjectionMenu() {
        guard let statusMenu,
              let projectionMenuAnchor
        else {
            return
        }
        for item in projectionMenuItems {
            statusMenu.removeItem(item)
        }
        projectionMenuItems.removeAll(keepingCapacity: true)
        guard let anchorIndex = statusMenu.items.firstIndex(
            where: { $0 === projectionMenuAnchor }
        ) else {
            return
        }
        var insertionIndex = anchorIndex
        if !projection.displays.isEmpty {
            let separator = NSMenuItem.separator()
            statusMenu.insertItem(separator, at: insertionIndex)
            projectionMenuItems.append(separator)
            insertionIndex += 1
        }
        for display in projection.displays {
            let parent = NSMenuItem(
                title: display.name,
                action: nil,
                keyEquivalent: ""
            )
            let submenu = NSMenu(title: display.name)
            for mode in TraceProjectionMode.allCases {
                let item = NSMenuItem(
                    title: TraceProjectionPolicy.menuTitle(
                        for: mode,
                        systemPreferenceDescription:
                            display.systemPreferenceDescription
                    ),
                    action: #selector(changeProjectionMode(_:)),
                    keyEquivalent: ""
                )
                item.target = self
                item.representedObject = TraceProjectionMenuAction(
                    displayKey: display.key,
                    mode: mode
                )
                item.state = projection.mode(for: display) == mode
                    ? .on
                    : .off
                submenu.addItem(item)
            }
            parent.submenu = submenu
            statusMenu.insertItem(parent, at: insertionIndex)
            projectionMenuItems.append(parent)
            insertionIndex += 1
        }
    }

    @objc private func showBoard() {
        let screen = NSScreen.main ?? NSScreen.screens.first
        withFlushedTldrawSnapshot { [weak self] in
            guard let self else {
                return
            }
            self.model.newBlankPage(
                size: self.model.preferredBlankViewportSize,
                backingScale: screen?.backingScaleFactor ?? 2
            )
        }
    }

    @objc private func newCapture() {
        withFlushedTldrawSnapshot { [weak self] in
            self?.model.newScreenshotPage()
        }
    }

    @objc private func toggleCaptureOnCapOff(_ sender: NSMenuItem) {
        model.setCaptureScreenshotOnCapOff(sender.state != .on)
    }

    @objc private func toggleCopyOnDisconnect(_ sender: NSMenuItem) {
        model.setCopyTraceAndCloseOnDisconnect(sender.state != .on)
    }

    @objc private func toggleCopyOnCopy(_ sender: NSMenuItem) {
        model.setCopyTraceAndCloseOnCopy(sender.state != .on)
    }

    @objc private func toggleAutoAnnotateDictation(
        _ sender: NSMenuItem
    ) {
        model.setAutoAnnotateDictation(sender.state != .on)
    }

    @objc private func changeTranscriptAnnotationScale(
        _ sender: NSMenuItem
    ) {
        guard let rawValue = sender.representedObject as? String,
              let scale = TraceTranscriptAnnotationScale(
                  rawValue: rawValue
              )
        else {
            return
        }
        model.setTranscriptAnnotationScale(scale)
    }

    @objc private func toggleLaunchInMenuBarAtLogin(
        _ sender: NSMenuItem
    ) {
        let enabled = sender.state != .on
        do {
            try updateLaunchInMenuBarAtLogin(enabled: enabled)
            model.setLaunchInMenuBarAtLogin(enabled)
        } catch {
            showSettingsError(
                "Trace could not update its launch-at-login setting: "
                    + error.localizedDescription
            )
        }
    }

    private func updateLaunchInMenuBarAtLogin(
        enabled: Bool
    ) throws {
        if enabled {
            // .requiresApproval means the service is already registered and
            // pending the user's action in System Settings; calling
            // register() again throws "already registered".
            if SMAppService.mainApp.status == .notRegistered {
                try SMAppService.mainApp.register()
            }
        } else if SMAppService.mainApp.status != .notRegistered {
            try SMAppService.mainApp.unregister()
        }
    }

    @objc private func changeProjectionMode(_ sender: NSMenuItem) {
        guard let action = sender.representedObject
            as? TraceProjectionMenuAction,
              let display = projection.displays.first(where: {
                  $0.key == action.displayKey
              })
        else {
            return
        }
        projection.setMode(action.mode, for: display)
    }

    @objc private func togglePenBeep(_ sender: NSMenuItem) {
        model.setPenBeepEnabled(sender.state != .on)
    }

    @objc private func togglePenHover(_ sender: NSMenuItem) {
        model.setPenHoverEnabled(sender.state != .on)
    }

    @objc private func togglePenOfflineStorage(_ sender: NSMenuItem) {
        model.setPenOfflineDataEnabled(sender.state != .on)
    }

    @objc private func togglePenAutoPower(_ sender: NSMenuItem) {
        model.setPenAutoPowerOnEnabled(sender.state != .on)
    }

    @objc private func togglePenCapPower(_ sender: NSMenuItem) {
        model.setPenCapPowerOffEnabled(sender.state != .on)
    }

    @objc private func changePenAutoOff(_ sender: NSMenuItem) {
        guard let minutes = sender.representedObject as? Int else {
            return
        }
        model.setPenAutoPowerOffMinutes(UInt16(minutes))
    }

    @objc private func changePenSensitivity(_ sender: NSMenuItem) {
        guard let step = sender.representedObject as? Int else {
            return
        }
        model.setPenSensitivityStep(UInt8(step))
    }

    @objc private func showSetup() {
        model.showOnboarding()
    }

    @objc private func closeBoard() {
        withFlushedTldrawSnapshot { [weak self] in
            self?.model.closeBoard()
        }
    }

    @objc private func revealDrawings() {
        model.revealDrawingsFolder()
    }

    @objc private func copyDrawing(_ sender: Any?) {
        copyCurrentDrawing(
            .all,
            closesDocument:
                TraceAppBehaviorPolicy.shouldCloseAfterManualCopy(
                    settings: model.snapshot.appSettings
                )
        )
    }

    @objc private func undoDrawing(_ sender: Any?) {
        if let textView = NSApp.keyWindow?.firstResponder as? NSTextView,
           textView.isEditable
        {
            textView.undoManager?.undo()
            return
        }
        if let source = undoEditSources.last {
            let handled: Bool
            switch source {
            case .native:
                handled = model.snapshot.canUndo
                if handled {
                    model.undoDrawing()
                }
            case .tldraw:
                handled = board.undoTldrawIfAvailable()
            }
            if handled {
                undoEditSources.removeLast()
                redoEditSources.append(source)
                return
            }
        }
        if board.undoTldrawIfAvailable() {
            return
        }
        model.undoDrawing()
    }

    @objc private func redoDrawing(_ sender: Any?) {
        if let textView = NSApp.keyWindow?.firstResponder as? NSTextView,
           textView.isEditable
        {
            textView.undoManager?.redo()
            return
        }
        if let source = redoEditSources.last {
            let handled: Bool
            switch source {
            case .native:
                handled = model.snapshot.canRedo
                if handled {
                    model.redoDrawing()
                }
            case .tldraw:
                handled = board.redoTldrawIfAvailable()
            }
            if handled {
                redoEditSources.removeLast()
                undoEditSources.append(source)
                return
            }
        }
    }

    @objc private func pasteImage(_ sender: Any?) {
        if let textView = NSApp.keyWindow?.firstResponder as? NSTextView,
           textView.isEditable
        {
            textView.paste(sender)
            return
        }
        let images: [TraceCanvasImage]
        switch TracePasteboardImage.read(from: .general) {
        case let .success(decoded):
            images = decoded
        case let .failure(error):
            NSLog("Trace paste rejected: %@", error.localizedDescription)
            NSSound.beep()
            return
        }
        if board.insertImages(images) {
            return
        }
        NSSound.beep()
    }

    func validateMenuItem(_ menuItem: NSMenuItem) -> Bool {
        let textUndoManager = (
            NSApp.keyWindow?.firstResponder as? NSTextView
        ).flatMap { $0.isEditable ? $0.undoManager : nil }
        switch menuItem.action {
        case #selector(undoDrawing(_:)):
            return textUndoManager?.canUndo
                ?? (board.canUndoTldraw || model.snapshot.canUndo)
        case #selector(redoDrawing(_:)):
            if let textUndoManager {
                return textUndoManager.canRedo
            }
            guard let source = redoEditSources.last else {
                return false
            }
            switch source {
            case .native:
                return model.snapshot.canRedo
            case .tldraw:
                return board.canRedoTldraw
            }
        case #selector(pasteImage(_:)):
            if textUndoManager != nil {
                return true
            }
            return model.snapshot.currentDocument != nil
                && TracePasteboardImage.canRead(from: .general)
        default:
            return true
        }
    }

    private func recordDrawingEdit(_ source: DrawingEditSource) {
        undoEditSources.append(source)
        redoEditSources.removeAll(keepingCapacity: true)
    }

    private func withFlushedTldrawSnapshot(
        _ action: @escaping () -> Void
    ) {
        guard model.snapshot.currentDocument != nil else {
            action()
            return
        }
        board.flushTldrawSnapshot(completion: action)
    }

    private func prepareForDocumentPresentation() {
        if copyProgress.cancelForDocumentPresentation() {
            board.setCopyFinalizationActive(false)
        }
        undoEditSources.removeAll(keepingCapacity: true)
        redoEditSources.removeAll(keepingCapacity: true)
    }

    private func openImageSelection(
        _ images: [TraceCanvasImage]
    ) -> Bool {
        guard !images.isEmpty else {
            return false
        }
        let screen = NSScreen.main ?? NSScreen.screens.first
        guard model.newBlankPage(
                  size: model.preferredBlankViewportSize,
                  backingScale: screen?.backingScaleFactor ?? 2,
                  activatesProjectOutput: false
              )
        else {
            return false
        }
        return board.insertImages(images)
    }

    private func copyCurrentDrawing(
        _ content: TraceCopyContent = .all,
        closesDocument: Bool = true
    ) {
        guard let documentID =
                model.snapshot.currentDocument?.manifest.id,
              !model.snapshot.voiceState.isFinishing
        else {
            model.copyFailed()
            NSSound.beep()
            return
        }
        guard beginCopyProgress(for: documentID) else {
            return
        }
        board.flushTldrawSnapshot { [weak self] in
            guard let self else {
                return
            }
            guard self.model.snapshot.currentDocument?.manifest.id
                    == documentID
            else {
                self.endCopyProgress(for: documentID)
                return
            }
            self.beginCopy(
                content,
                documentID: documentID,
                closesDocument: closesDocument
            )
        }
    }

    private func beginCopy(
        _ content: TraceCopyContent,
        documentID: UUID,
        closesDocument: Bool
    ) {
        if content == .image {
            completeCopy(
                content,
                transcript: nil,
                documentID: documentID,
                closesDocument: closesDocument
            )
            return
        }
        model.finishVoiceForCopy { [weak self] result in
            guard let self else {
                return
            }
            guard case let .success(transcript) = result else {
                if self.model.snapshot.currentDocument?.manifest.id
                    != documentID
                {
                    self.endCopyProgress(for: documentID)
                    return
                }
                self.failCopy(for: documentID)
                return
            }
            self.completeCopy(
                content,
                transcript: transcript,
                documentID: documentID,
                closesDocument: closesDocument
            )
        }
    }

    private func completeCopy(
        _ content: TraceCopyContent,
        transcript: String?,
        documentID: UUID,
        closesDocument: Bool
    ) {
        guard model.snapshot.currentDocument?.manifest.id
                == documentID
        else {
            endCopyProgress(for: documentID)
            return
        }
        switch content {
        case .all:
            board.compositeImage { [weak self] image in
                guard let self else {
                    return
                }
                guard self.model.snapshot.currentDocument?.manifest.id
                        == documentID
                else {
                    self.endCopyProgress(for: documentID)
                    return
                }
                guard let image else {
                    self.failCopy(for: documentID)
                    return
                }
                self.finishCopy(
                    self.board.copyComposite(
                        image,
                        transcript: transcript
                    ),
                    documentID: documentID,
                    closesDocument: closesDocument
                )
            }
            return
        case .dictation:
            guard let transcript else {
                failCopy(for: documentID)
                return
            }
            finishCopy(
                TraceClipboardPayload.writeTranscript(
                    transcript,
                    to: .general
                ),
                documentID: documentID,
                closesDocument: closesDocument
            )
        case .image:
            board.compositeImage { [weak self] image in
                guard let self else {
                    return
                }
                guard self.model.snapshot.currentDocument?.manifest.id
                        == documentID
                else {
                    self.endCopyProgress(for: documentID)
                    return
                }
                guard let image else {
                    self.failCopy(for: documentID)
                    return
                }
                self.finishCopy(
                    TraceClipboardPayload.writeImage(
                        image,
                        to: .general
                    ),
                    documentID: documentID,
                    closesDocument: closesDocument
                )
            }
            return
        }
    }

    private func finishCopy(
        _ copied: Bool,
        documentID: UUID,
        closesDocument: Bool
    ) {
        guard copied else {
            failCopy(for: documentID)
            return
        }
        guard model.snapshot.currentDocument?.manifest.id
                == documentID
        else {
            endCopyProgress(for: documentID)
            return
        }
        model.copyCompleted(closeDocument: closesDocument)
        endCopyProgress(for: documentID)
    }

    private func failCopy(for documentID: UUID) {
        endCopyProgress(for: documentID)
        model.copyFailed()
        NSSound.beep()
    }

    private func beginCopyProgress(for documentID: UUID) -> Bool {
        guard copyProgress.begin(for: documentID) else {
            return false
        }
        board.setCopyFinalizationActive(true)
        return true
    }

    private func endCopyProgress(for documentID: UUID) {
        guard copyProgress.end(for: documentID) else {
            return
        }
        board.setCopyFinalizationActive(false)
    }

#if DEBUG
    private func setCopyProgressForTesting(_ active: Bool) {
        if active {
            _ = beginCopyProgress(for: UUID())
        } else {
            _ = copyProgress.cancelForDocumentPresentation()
            board.setCopyFinalizationActive(false)
        }
    }
#endif

    @objc private func quit() {
        NSApp.terminate(nil)
    }

    private func showStartupError(_ error: Error) {
        let alert = NSAlert()
        alert.alertStyle = .warning
        alert.messageText = "Trace could not access the pen"
        alert.informativeText = error.localizedDescription
        alert.runModal()
    }

    private func showSettingsError(_ message: String) {
        let alert = NSAlert()
        alert.alertStyle = .warning
        alert.messageText = "Trace could not update Settings"
        alert.informativeText = message
        alert.runModal()
    }
}

private final class TracePenSessionLock {
    private let fileDescriptor: Int32

    init() throws {
        let fileURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("com.traceproject.pen.live.lock")
        let descriptor = Darwin.open(
            fileURL.path,
            O_CREAT | O_RDWR,
            S_IRUSR | S_IWUSR
        )
        guard descriptor >= 0 else {
            throw CocoaError(.fileWriteUnknown)
        }
        guard flock(descriptor, LOCK_EX | LOCK_NB) == 0 else {
            Darwin.close(descriptor)
            throw TracePenLockError.alreadyOwned
        }
        fileDescriptor = descriptor
    }

    deinit {
        flock(fileDescriptor, LOCK_UN)
        Darwin.close(fileDescriptor)
    }
}

private enum TracePenLockError: LocalizedError {
    case alreadyOwned

    var errorDescription: String? {
        "Another Trace process is already using the Neo Smartpen."
    }
}
