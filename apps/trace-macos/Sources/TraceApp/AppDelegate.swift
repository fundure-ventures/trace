import AppKit
import TraceLogging
import Darwin
import NeoTransport
import ServiceManagement
import TraceAppCore
import UniformTypeIdentifiers
import TraceCLICore

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
    static let copyTraceAndClose = "Close window after copy"
    static let onCopySection = "Copy"
    static let copyFormat = "Format"
    static let dictationSection = "Dictation"
    static let autoAnnotateDictation = "Start dictation automatically"
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
    NSMenuItemValidation,
    NSMenuDelegate
{
    private enum DrawingEditSource {
        case native
        case tldraw
    }

    private let model = TraceAppModel()
    private let board = TraceBoardWindowController()
    private let projection = TraceProjectionCoordinator()
    private let globalShortcuts = TraceGlobalShortcutManager()
    private let deviceScreenshots = DeviceScreenshotService()
    private var screenshotMenuItems: [NSMenuItem] = []
    private var openScreenshotMenus = Set<ObjectIdentifier>()
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
    private var copyFormatOnCopyItems: [TraceCopyContent: NSMenuItem] = [:]
    private var copyProgress = TraceDocumentCopyProgress()
    private var latestCopyID: UUID?
    private var undoEditSources: [DrawingEditSource] = []
    private var redoEditSources: [DrawingEditSource] = []
    private var terminationFlushInProgress = false
    private var terminationReady = false
    private var liveSessionLock: TracePenSessionLock?
    private var cliServer: TraceCLIServer?
    private let cliWindowCapture = WindowCaptureService()
    private var cliActionGate = TraceCLIActionGate()
    private let openFileLifecycle = TraceOpenFileLifecycle()
    private var openFileForwardingObserver: NSObjectProtocol?
    private var startupErrorWorkItem: DispatchWorkItem?
    private var forwardedOpenFiles = false
    private var persistDebugLogItems: [NSMenuItem] = []

    func applicationDidFinishLaunching(_ notification: Notification) {
#if DEBUG
        let environment = ProcessInfo.processInfo.environment
        let runsProductProbe = ["1", "text", "framing"].contains(
            environment["TRACE_PRODUCT_TLDRAW_PROBE"] ?? ""
        )
        let isUIPreview = environment["TRACE_UI_SNAPSHOT"] != nil
            || environment["TRACE_UI_COMPOSITE"] != nil
            || environment["TRACE_UI_NO_HARDWARE"] == "1"
            || environment["TRACE_RETAINED_INK_PROBE"] == "1"
            || environment["TRACE_PROGRESSIVE_COPY_PROBE"] == "1"
            || runsProductProbe
#else
        let isUIPreview = false
#endif
        if !isUIPreview {
            do {
                liveSessionLock = try TracePenSessionLock()
            } catch {
                TraceLogger.shared.record(.debug, category: .lifecycle, "Forwarding launch to existing Trace instance")
                becomeOpenFileForwarder(startupError: error)
                return
            }
            startOpenFileForwardingListener()
        }
        TraceLogger.shared.record(.notice, category: .lifecycle, "Trace started")
#if DEBUG
        if environment["TRACE_PROGRESSIVE_COPY_PROBE"] == "1" {
            Task { @MainActor in
                do {
                    try await TraceRetainedInkProbe.runProgressiveCopyChecks()
                    print("progressive copy probe passed")
                    NSApp.terminate(nil)
                } catch {
                    fputs("progressive copy probe failed: \(error)\n", stderr)
                    exit(1)
                }
            }
            return
        }
        if runsProductProbe {
            NSApp.setActivationPolicy(.accessory)
            Task { @MainActor in
                do {
                    try await ProductTldrawProbe.run(
                        textToolsOnly:
                            environment["TRACE_PRODUCT_TLDRAW_PROBE"] == "text",
                        framingOnly:
                            environment["TRACE_PRODUCT_TLDRAW_PROBE"] == "framing"
                    )
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
        deviceScreenshots.onDevicesChange = { [weak self] in
            guard let self, self.openScreenshotMenus.isEmpty else { return }
            self.refreshScreenshotMenus()
        }
        if !isUIPreview {
            deviceScreenshots.start()
        }
        if !isUIPreview {
            do {
                try updateLaunchInMenuBarAtLogin(
                    enabled:
                        model.snapshot.appSettings.launchInMenuBarAtLogin
                )
            } catch {
                TraceLogger.shared.record(.error, category: .lifecycle, "Launch-at-login update failed", error: error)
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
        if !isUIPreview {
            startCLIServer()
        }
#if DEBUG
        if ProcessInfo.processInfo.environment["TRACE_CLI_PROBE"] == "1",
           let cliServer
        {
            cliServer.runProbe { passed in
                print(passed ? "CLI IPC probe passed" : "CLI IPC probe failed")
            }
            return
        }
#endif
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
        deviceScreenshots.stop()
        projection.stop()
        model.stop()
        TraceLogger.shared.record(.notice, category: .lifecycle, "Trace stopped")
        do { try TraceLogger.shared.flush() }
        catch { fputs("Trace local logs could not be fully saved.\n", stderr) }
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
                openDrawing: { _ = self.model.openDrawing(from: $0) },
                openImages: { self.openImageSelection($0) }
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

    private func startCLIServer() {
        let identifier = Bundle.main.bundleIdentifier ?? "com.traceproject.app"
        let server = TraceCLIServer(bundleIdentifier: identifier)
        cliServer = server
        server.start { [weak self] request, completion in
            guard let self else {
                completion(
                    TraceCLIReply(ok: false, code: "unavailable", message: "Trace is unavailable."))
                return
            }
            self.handleCLIRequest(request, completion: completion)
        }
    }

    private func handleCLIRequest(
        _ request: TraceCLIRequest,
        completion: @escaping (TraceCLIReply) -> Void
    ) {
        let readOnly = request.action == .devices
        let actionID = readOnly ? nil : cliActionGate.begin()
        guard readOnly || actionID != nil else {
            completion(TraceCLIReply(ok: false, code: "busy", message: "Trace is busy with another CLI action."))
            return
        }
        let replyGate = TraceCLIReplyGate { [weak self] reply in
            DispatchQueue.main.async {
                if let actionID {
                    _ = self?.cliActionGate.finish(actionID)
                }
                completion(reply)
            }
        }
        let timeout = DispatchWorkItem {
            replyGate.send(
                TraceCLIReply(
                    ok: false,
                    code: "timeout",
                    message: "Trace action timed out."
                ))
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 119, execute: timeout)
        performCLIRequest(request) { reply in
            timeout.cancel()
            replyGate.send(reply)
        }
    }

    private func performCLIRequest(
        _ request: TraceCLIRequest,
        completion: @escaping (TraceCLIReply) -> Void
    ) {
        guard let action = request.action else {
            completion(
                TraceCLIReply(ok: false, code: "invalidRequest", message: "Invalid CLI request."))
            return
        }
        switch action {
        case .newTrace:
            let screen = NSScreen.main ?? NSScreen.screens.first
            withFlushedTldrawSnapshot { [weak self] in
                guard let self else {
                    completion(TraceCLIReply(ok: false, code: "unavailable"))
                    return
                }
                let created = self.model.newBlankPage(
                    size: self.model.preferredBlankViewportSize,
                    backingScale: screen?.backingScaleFactor ?? 2,
                    noRecording: request.noRecording
                )
                completion(TraceCLIReply(ok: created, code: created ? nil : "actionFailed"))
            }
        case .capture:
            if model.snapshot.currentDocument == nil {
                _ = model.newScreenshotPage(
                    noRecording: request.noRecording,
                    excludingOwnerPIDs: Set(request.excludePIDs)
                ) { result in
                    switch result {
                    case .success:
                        completion(TraceCLIReply(ok: true))
                    case let .failure(error):
                        completion(
                            TraceCLIReply(
                                ok: false,
                                code: "actionFailed",
                                message: error.localizedDescription
                            ))
                    }
                }
            } else {
                let documentID = model.snapshot.currentDocument?.manifest.id
                cliWindowCapture.captureFrontmost(
                    excludingOwnerPIDs: Set(request.excludePIDs)
                ) { [weak self] result in
                    guard let self else {
                        completion(TraceCLIReply(ok: false, code: "unavailable"))
                        return
                    }
                    do {
                        let captured = try result.get()
                        guard TraceCLIActionPolicy.isCurrentDocument(
                            expectedID: documentID,
                            currentID: self.model.snapshot.currentDocument?.manifest.id
                        ) else {
                            completion(
                                TraceCLIReply(
                                    ok: false,
                                    code: "actionFailed",
                                    message: "The open trace changed during capture."
                                ))
                            return
                        }
                        let image = NSImage(
                            cgImage: captured.cgImage,
                            size: NSSize(
                                width: captured.cgImage.width,
                                height: captured.cgImage.height
                            )
                        )
                        self.insertCLIImages(
                            [TraceCanvasImage(image: image, name: captured.descriptor.ownerName)],
                            expectedDocumentID: documentID
                        ) { inserted in
                            if inserted { self.board.setEditorVisible(true) }
                            completion(
                                TraceCLIReply(
                                    ok: inserted,
                                    code: inserted ? nil : "actionFailed",
                                    message: inserted ? nil : "Could not insert the capture."
                                ))
                        }
                    } catch {
                        completion(
                            TraceCLIReply(
                                ok: false, code: "actionFailed", message: error.localizedDescription
                            ))
                    }
                }
            }
        case .devices:
            deviceScreenshots.refresh { [weak self] in
                completion(TraceCLIReply(ok: true, devices: self?.cliDevices ?? []))
            }
        case let .captureDevice(name):
            TraceCLIRefreshPolicy.resolveAfterRefresh(
                captureOrigin: { self.model.snapshot.currentDocument?.manifest.id },
                refresh: { [weak self] completion in
                    guard let self else {
                        completion()
                        return
                    }
                    self.deviceScreenshots.refresh(completion: completion)
                },
                resolve: { [weak self] in self?.matchDevice(named: name) }
            ) { [weak self] expectedDocumentID, device in
                guard let self else {
                    completion(TraceCLIReply(ok: false, code: "unavailable"))
                    return
                }
                guard let device else {
                    completion(
                        TraceCLIReply(
                            ok: false,
                            code: "unknownDevice",
                            message: "Unknown, ambiguous, or unavailable device: \(name)",
                            devices: self.cliDevices
                        ))
                    return
                }
                self.captureCLIDevice(
                    device,
                    expectedDocumentID: expectedDocumentID,
                    noRecording: request.noRecording,
                    completion: completion
                )
            }
        case .copy:
            guard model.snapshot.currentDocument != nil else {
                completion(
                    TraceCLIReply(ok: false, code: "noDocument", message: "No trace is open."))
                return
            }
            let format: TraceCopyContent
            switch request.format {
            case .imageDictation: format = .all
            case .image: format = .image
            case .dictation: format = .dictation
            case .pdf: format = .document
            }
            copyCurrentDrawing(
                format,
                closesDocument: TraceAppBehaviorPolicy.shouldCloseAfterManualCopy(
                    settings: model.snapshot.appSettings
                )
            ) { copied in
                completion(
                    TraceCLIReply(
                        ok: copied,
                        code: copied ? nil : "actionFailed",
                        message: copied ? nil : "Could not copy the open trace."
                    ))
            }
        case let .openDocument(path):
            guard readableFiles([path]) else {
                completion(
                    TraceCLIReply(
                        ok: false, code: "fileNotFound",
                        message: "File not found or unreadable: \(path)"))
                return
            }
            withFlushedTldrawSnapshot { [weak self] in
                guard let self else {
                    completion(TraceCLIReply(ok: false, code: "unavailable"))
                    return
                }
                let opened = self.model.openDrawing(from: URL(fileURLWithPath: path))
                completion(
                    TraceCLIReply(
                        ok: opened,
                        code: opened ? nil : "actionFailed",
                        message: opened ? nil : "Could not open the traceboard."
                    ))
            }
        case let .openImages(paths):
            guard readableFiles(paths) else {
                completion(
                    TraceCLIReply(
                        ok: false, code: "fileNotFound",
                        message: "An image file is missing or unreadable."))
                return
            }
            guard case let .images(images)? = TraceOpenFilePolicy.request(for: paths) else {
                completion(
                    TraceCLIReply(
                        ok: false, code: "unreadable", message: "The image files could not be read."
                    ))
                return
            }
            let expectedDocumentID = model.snapshot.currentDocument?.manifest.id
            withFlushedTldrawSnapshot { [weak self] in
                guard let self else {
                    completion(TraceCLIReply(ok: false, code: "unavailable"))
                    return
                }
                guard TraceCLIActionPolicy.isCurrentDocument(
                    expectedID: expectedDocumentID,
                    currentID: self.model.snapshot.currentDocument?.manifest.id
                ) else {
                    completion(
                        TraceCLIReply(
                            ok: false,
                            code: "actionFailed",
                            message: "The open trace changed while importing images."
                        ))
                    return
                }
                if expectedDocumentID != nil {
                    self.insertCLIImages(images, expectedDocumentID: expectedDocumentID) { inserted in
                        completion(
                            TraceCLIReply(
                                ok: inserted,
                                code: inserted ? nil : "actionFailed",
                                message: inserted ? nil : "Could not insert the images."
                            ))
                    }
                    return
                }
                let screen = NSScreen.main ?? NSScreen.screens.first
                guard
                    self.model.newBlankPage(
                        size: self.model.preferredBlankViewportSize,
                        backingScale: screen?.backingScaleFactor ?? 2,
                        activatesProjectOutput: false,
                        noRecording: request.noRecording
                    )
                else {
                    completion(TraceCLIReply(ok: false, code: "actionFailed"))
                    return
                }
                let expectedDocumentID = self.model.snapshot.currentDocument?.manifest.id
                self.insertCLIImages(images, expectedDocumentID: expectedDocumentID) { inserted in
                    completion(
                        TraceCLIReply(
                            ok: inserted,
                            code: inserted ? nil : "actionFailed",
                            message: inserted ? nil : "Could not insert the images."
                        ))
                }
            }
        case let .export(destination):
            exportCLI(format: request.format, destination: destination, completion: completion)
        }
    }

    private var cliDevices: [TraceCLIDevice] {
        deviceScreenshots.devices.map {
            TraceCLIDevice(
                name: $0.name,
                identifier: $0.identifier,
                unavailableReason: $0.unavailableReason
            )
        }
    }

    private func captureCLIDevice(
        _ device: TraceScreenshotDevice,
        expectedDocumentID: UUID?,
        noRecording: Bool,
        completion: @escaping (TraceCLIReply) -> Void
    ) {
        deviceScreenshots.capture(device) { [weak self] result in
            guard let self else {
                completion(TraceCLIReply(ok: false, code: "unavailable"))
                return
            }
            do {
                let image = try result.get()
                guard TraceCLIActionPolicy.isCurrentDocument(
                    expectedID: expectedDocumentID,
                    currentID: self.model.snapshot.currentDocument?.manifest.id
                ) else {
                    completion(
                        TraceCLIReply(
                            ok: false,
                            code: "actionFailed",
                            message: "The open trace changed during capture."
                        ))
                    return
                }
                if expectedDocumentID == nil {
                    let screen = NSScreen.main ?? NSScreen.screens.first
                    guard self.model.newBlankPage(
                        size: self.model.preferredBlankViewportSize,
                        backingScale: screen?.backingScaleFactor ?? 2,
                        activatesProjectOutput: false,
                        noRecording: noRecording
                    ) else {
                        completion(TraceCLIReply(ok: false, code: "actionFailed"))
                        return
                    }
                }
                let targetDocumentID = self.model.snapshot.currentDocument?.manifest.id
                guard let targetDocumentID else {
                    completion(TraceCLIReply(ok: false, code: "actionFailed"))
                    return
                }
                self.insertCLIImages(
                    [TraceCanvasImage(image: image, name: device.menuTitle)],
                    expectedDocumentID: targetDocumentID
                ) { inserted in
                    if inserted { self.board.setEditorVisible(true) }
                    completion(
                        TraceCLIReply(
                            ok: inserted,
                            code: inserted ? nil : "actionFailed"
                        ))
                }
            } catch {
                completion(
                    TraceCLIReply(
                        ok: false,
                        code: "actionFailed",
                        message: error.localizedDescription
                    ))
            }
        }
    }

    private func matchDevice(named name: String) -> TraceScreenshotDevice? {
        let value = name.lowercased()
        let exactName = deviceScreenshots.devices.filter { $0.name.lowercased() == value }
        if exactName.count == 1 {
            return exactName[0].unavailableReason == nil ? exactName[0] : nil
        }
        if exactName.count > 1 { return nil }
        let exactIdentifier = deviceScreenshots.devices.filter {
            $0.identifier.lowercased() == value
        }
        if exactIdentifier.count == 1 {
            return exactIdentifier[0].unavailableReason == nil ? exactIdentifier[0] : nil
        }
        guard exactIdentifier.isEmpty else { return nil }
        let prefix = deviceScreenshots.devices.filter {
            $0.name.lowercased().hasPrefix(value)
                || $0.identifier.lowercased().hasPrefix(value)
        }
        return prefix.count == 1 && prefix[0].unavailableReason == nil ? prefix[0] : nil
    }

    private func readableFiles(_ paths: [String]) -> Bool {
        paths.allSatisfy {
            FileManager.default.isReadableFile(atPath: $0)
        }

    }

    private func insertCLIImages(
        _ images: [TraceCanvasImage],
        expectedDocumentID: UUID?,
        attempt: Int = 0,
        completion: @escaping (Bool) -> Void
    ) {
        guard TraceCLIActionPolicy.isCurrentDocument(
            expectedID: expectedDocumentID,
            currentID: model.snapshot.currentDocument?.manifest.id
        ) else {
            completion(false)
            return
        }
        if board.insertImages(images, atViewportCenter: true) {
            guard TraceCLIActionPolicy.isCurrentDocument(
                expectedID: expectedDocumentID,
                currentID: model.snapshot.currentDocument?.manifest.id
            ) else {
                completion(false)
                return
            }
            completion(true)
            return
        }
        guard attempt < 49 else {
            completion(false)
            return
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) { [weak self] in
            guard let self else {
                completion(false)
                return
            }
            self.insertCLIImages(
                images,
                expectedDocumentID: expectedDocumentID,
                attempt: attempt + 1,
                completion: completion
            )
        }
    }

    private func compositeImageForDocument(
        expectedDocumentID: UUID,
        attempt: Int = 0,
        completion: @escaping (NSImage?) -> Void
    ) {
        guard TraceCLIActionPolicy.isCurrentDocument(
            expectedID: expectedDocumentID,
            currentID: model.snapshot.currentDocument?.manifest.id
        ) else {
            completion(nil)
            return
        }
        board.compositeImage { [weak self] image in
            guard let self else {
                completion(nil)
                return
            }
            guard TraceCLIActionPolicy.isCurrentDocument(
                expectedID: expectedDocumentID,
                currentID: self.model.snapshot.currentDocument?.manifest.id
            ) else {
                completion(nil)
                return
            }
            if image != nil || attempt >= 49 {
                completion(image)
                return
            }
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                self.compositeImageForDocument(
                    expectedDocumentID: expectedDocumentID,
                    attempt: attempt + 1,
                    completion: completion
                )
            }
        }
    }

    private func exportCLI(
        format: TraceCLIFormat,
        destination: String,
        completion: @escaping (TraceCLIReply) -> Void
    ) {
        guard let document = model.snapshot.currentDocument else {
            completion(TraceCLIReply(ok: false, code: "noDocument", message: "No trace is open."))
            return
        }
        let expectedDocumentID = document.manifest.id
        let needsTranscript = format != .image
        let finish: (String?) -> Void = { [weak self] transcript in
            guard let self else {
                completion(TraceCLIReply(ok: false, code: "unavailable"))
                return
            }
            guard TraceCLIActionPolicy.isCurrentDocument(
                expectedID: expectedDocumentID,
                currentID: self.model.snapshot.currentDocument?.manifest.id
            ) else {
                completion(
                    TraceCLIReply(
                        ok: false,
                        code: "actionFailed",
                        message: "The open trace changed during export."
                    ))
                return
            }
            if format == .dictation {
                guard let transcript, !transcript.isEmpty else {
                    completion(
                        TraceCLIReply(
                            ok: false, code: "actionFailed", message: "No dictation is available."))
                    return
                }
                let file = self.cliDestination(
                    destination,
                    baseName: document.packageURL.deletingPathExtension().lastPathComponent,
                    extension: "txt"
                )
                completion(
                    TraceCLIReply(
                        ok: true,
                        exports: [
                            TraceCLIExport(filename: file.path, data: Data(transcript.utf8))
                        ]))
                return
            }
            self.compositeImageForDocument(expectedDocumentID: expectedDocumentID) { image in
                guard let image else {
                    completion(
                        TraceCLIReply(
                            ok: false, code: "actionFailed", message: "Could not render the trace.")
                    )
                    return
                }
                let imageItem = TraceClipboardPayload.makeItem(image: image, transcript: transcript)
                guard let imageData = imageItem?.data(forType: .png) else {
                    completion(
                        TraceCLIReply(
                            ok: false, code: "actionFailed",
                            message: "Could not encode the trace image."))
                    return
                }
                let baseName = document.packageURL.deletingPathExtension().lastPathComponent
                var exports = [
                    TraceCLIExport(
                        filename: self.cliDestination(
                            destination, baseName: baseName, extension: "png"
                        ).path,
                        data: imageData
                    )
                ]
                if format == .imageDictation, let transcript, !transcript.isEmpty {
                    exports.append(
                        TraceCLIExport(
                            filename: self.cliDestination(
                                destination, baseName: baseName, extension: "txt", sibling: true
                            ).path,
                            data: Data(transcript.utf8)
                        ))
                } else if format == .pdf {
                    guard
                        let data = TraceClipboardPayload.makeDocumentData(
                            image: image, transcript: transcript)
                    else {
                        completion(
                            TraceCLIReply(
                                ok: false, code: "actionFailed",
                                message: "Could not create the PDF."))
                        return
                    }
                    exports = [
                        TraceCLIExport(
                            filename: self.cliDestination(
                                destination, baseName: baseName, extension: "pdf"
                            ).path,
                            data: data
                        )
                    ]
                }
                completion(TraceCLIReply(ok: true, exports: exports))
            }
        }
        if needsTranscript {
            model.finishVoiceForCopy(expectedDocumentID: expectedDocumentID) { result in
                switch result {
                case let .success(transcript): finish(transcript)
                case .failure:
                    completion(
                        TraceCLIReply(
                            ok: false, code: "actionFailed", message: "Could not finish dictation.")
                    )
                }
            }
        } else {
            finish(nil)
        }
    }

    private func cliDestination(
        _ rawPath: String,
        baseName: String,
        extension fileExtension: String,
        sibling: Bool = false
    ) -> URL {
        let requested = URL(fileURLWithPath: rawPath)
        let isFilename = !requested.pathExtension.isEmpty
        if isFilename {
            let base = requested.deletingPathExtension()
            if sibling {
                return base.deletingLastPathComponent()
                    .appendingPathComponent("\(base.lastPathComponent).txt")
            }
            return base.appendingPathExtension(fileExtension)
        }
        return requested.appendingPathComponent("\(baseName).\(fileExtension)")
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
        menu.delegate = self

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
        screenshotMenuItems.append(capture)
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
        let copyFormat = NSMenuItem(
            title: TraceAppSettingsMenuPresentation.copyFormat,
            action: nil,
            keyEquivalent: ""
        )
        let copyFormatMenu = NSMenu(
            title: TraceAppSettingsMenuPresentation.copyFormat
        )
        for format in TraceCopyContent.allCases {
            let item = NSMenuItem(
                title: format.menuTitle,
                action: #selector(changeCopyFormatOnCopy(_:)),
                keyEquivalent: ""
            )
            item.target = self
            item.representedObject = format.rawValue
            copyFormatMenu.addItem(item)
            copyFormatOnCopyItems[format] = item
        }
        copyFormat.submenu = copyFormatMenu
        appSettingsMenu.addItem(copyFormat)
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
        menu.addItem(diagnosticsMenuItem())
        menu.addItem(.separator())

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
        appMenu.addItem(diagnosticsMenuItem())
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
        fileMenu.delegate = self
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
        screenshotMenuItems.append(newItem)
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

    private func diagnosticsMenuItem() -> NSMenuItem {
        let item = NSMenuItem(title: "Diagnostics", action: nil, keyEquivalent: "")
        let menu = NSMenu(title: "Diagnostics")
        let persist = NSMenuItem(
            title: "Persist Debug Logs",
            action: #selector(toggleDebugLogPersistence(_:)),
            keyEquivalent: ""
        )
        persist.target = self
        persist.state = TraceLogger.shared.persistDebugLogs ? .on : .off
        persist.toolTip = "Keep verbose diagnostic events locally across app launches."
        persistDebugLogItems.append(persist)
        menu.addItem(persist)
        let open = NSMenuItem(title: "Open Logs", action: #selector(openLogs), keyEquivalent: "")
        open.target = self
        menu.addItem(open)
        item.submenu = menu
        return item
    }

    @objc private func toggleDebugLogPersistence(_ sender: NSMenuItem) {
        let enabled = sender.state != .on
        if !enabled {
            TraceLogger.shared.record(.notice, category: .lifecycle, "Debug log persistence disabled")
        }
        UserDefaults.standard.set(enabled, forKey: TraceLogger.debugPreferenceKey)
        TraceLogger.shared.setPersistDebugLogs(enabled)
        for item in persistDebugLogItems { item.state = enabled ? .on : .off }
        if enabled {
            TraceLogger.shared.record(.notice, category: .lifecycle, "Debug log persistence enabled")
        }
    }

    @objc private func openLogs() {
        do {
            try TraceLogger.shared.prepareDirectory()
            guard NSWorkspace.shared.open(TraceLogger.shared.directory) else {
                throw CocoaError(.fileReadUnknown)
            }
        } catch {
            TraceLogger.shared.record(.error, category: .lifecycle, "Opening logs failed", error: error)
            showSettingsError("Trace could not open its logs folder: " + error.localizedDescription)
        }
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
        for (format, item) in copyFormatOnCopyItems {
            item.state = settings.copyFormatOnCopy == format ? .on : .off
        }
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

    func menuWillOpen(_ menu: NSMenu) {
        if screenshotMenuItems.contains(where: { $0.submenu === menu }) {
            deviceScreenshots.warmAvailableIOSDevices()
            return
        }
        refreshScreenshotMenus()
        openScreenshotMenus.insert(ObjectIdentifier(menu))
        deviceScreenshots.refresh()
    }

    func menuDidClose(_ menu: NSMenu) {
        openScreenshotMenus.remove(ObjectIdentifier(menu))
    }

    private func refreshScreenshotMenus() {
        let app = NSWorkspace.shared.frontmostApplication
        let applicationName = WindowCaptureService().frontmostApplicationName
            ?? (app?.processIdentifier != ProcessInfo.processInfo.processIdentifier
                ? app?.bundleURL?.lastPathComponent : nil)
            ?? "frontmost app"
        for item in screenshotMenuItems {
            TraceDeviceScreenshotMenu.configure(
                item,
                devices: deviceScreenshots.devices,
                applicationName: applicationName,
                target: self,
                desktopAction: #selector(newCapture),
                deviceAction: #selector(captureDeviceScreenshot(_:)),
                capturing: deviceScreenshots.isCapturing
            )
        }
    }

    @objc private func captureDeviceScreenshot(_ sender: NSMenuItem) {
        guard let device = sender.representedObject as? TraceScreenshotDevice else {
            NSSound.beep()
            return
        }
        let documentID = model.snapshot.currentDocument?.manifest.id
        deviceScreenshots.capture(device) { [weak self] result in
            guard let self else { return }
            do {
                let image = try result.get()
                guard self.model.snapshot.currentDocument?.manifest.id == documentID else {
                    throw TraceDeviceScreenshotError.failed(
                        "The open trace changed during capture. Capture again to insert into the current trace."
                    )
                }
                let inserted = TraceDeviceScreenshotMenu.insert(
                    hasDocument: documentID != nil,
                    createDocument: {
                        let screen = NSScreen.main ?? NSScreen.screens.first
                        return self.model.newBlankPage(
                            size: self.model.preferredBlankViewportSize,
                            backingScale: screen?.backingScaleFactor ?? 2,
                            activatesProjectOutput: false
                        )
                    },
                    insertImage: {
                        self.board.insertImages(
                            [TraceCanvasImage(image: image, name: device.menuTitle)],
                            atViewportCenter: true
                        )
                    }
                )
                guard inserted else {
                    throw TraceDeviceScreenshotError.failed("Trace could not insert the device screenshot.")
                }
                self.board.setEditorVisible(true)
            } catch {
                TraceLogger.shared.record(.error, category: .capture, "Device screenshot failed", error: error)
                let alert = NSAlert()
                alert.alertStyle = .warning
                alert.messageText = "Trace could not capture the device"
                alert.informativeText = error.localizedDescription
                alert.runModal()
            }
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

    @objc private func changeCopyFormatOnCopy(_ sender: NSMenuItem) {
        guard let rawValue = sender.representedObject as? String,
              let format = TraceCopyContent(rawValue: rawValue)
        else {
            return
        }
        model.setCopyFormatOnCopy(format)
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
            TraceLogger.shared.record(.error, category: .lifecycle, "Launch-at-login update failed", error: error)
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
        TraceLogger.shared.record(.debug, category: .clipboard, "Copy requested")
        if let textView = NSApp.keyWindow?.firstResponder as? NSTextView,
           textView.isSelectable
        {
            textView.copy(sender)
            return
        }
        let documentID = model.snapshot.currentDocument?.manifest.id
        Task { @MainActor [weak self] in
            guard let self else {
                return
            }
            do {
                if try await board.copySelectionIfAvailable() {
                    return
                }
                guard model.snapshot.currentDocument?.manifest.id == documentID else {
                    return
                }
                copyCurrentDrawing(
                    model.snapshot.appSettings.copyFormatOnCopy,
                    closesDocument:
                        TraceAppBehaviorPolicy.shouldCloseAfterManualCopy(
                            settings: model.snapshot.appSettings
                        )
                )
            } catch {
                TraceLogger.shared.record(.error, category: .clipboard, "Copy rejected", error: error)
                NSSound.beep()
            }
        }
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
        TraceLogger.shared.record(.debug, category: .clipboard, "Paste requested")
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
            TraceLogger.shared.record(.error, category: .clipboard, "Paste rejected", error: error)
            NSSound.beep()
            return
        }
        if board.insertImages(images) {
            return
        }
        TraceLogger.shared.record(.error, category: .clipboard, "Pasted images could not be inserted")
        NSSound.beep()
    }

    func validateMenuItem(_ menuItem: NSMenuItem) -> Bool {
        let textUndoManager = (
            NSApp.keyWindow?.firstResponder as? NSTextView
        ).flatMap { $0.isEditable ? $0.undoManager : nil }
        switch menuItem.action {
        case #selector(captureDeviceScreenshot(_:)):
            guard let device = menuItem.representedObject as? TraceScreenshotDevice else {
                return false
            }
            return !deviceScreenshots.isCapturing && device.unavailableReason == nil
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
        _ images: [TraceCanvasImage],
        noRecording: Bool = false
    ) -> Bool {
        guard !images.isEmpty else {
            return false
        }
        let screen = NSScreen.main ?? NSScreen.screens.first
        guard model.newBlankPage(
                  size: model.preferredBlankViewportSize,
                  backingScale: screen?.backingScaleFactor ?? 2,
                  activatesProjectOutput: false,
                  noRecording: noRecording
              )
        else {
            return false
        }
        return board.insertImages(images)
    }

    private func copyCurrentDrawing(
        _ content: TraceCopyContent = .all,
        closesDocument: Bool = true,
        completion: ((Bool) -> Void)? = nil
    ) {
        guard let documentID =
                model.snapshot.currentDocument?.manifest.id,
              !model.snapshot.voiceState.isFinishing
        else {
            model.copyFailed()
            NSSound.beep()
            completion?(false)
            return
        }
        guard beginCopyProgress(for: documentID) else {
            completion?(false)
            return
        }
        latestCopyID = UUID()
        let dictationDeadline = ProcessInfo.processInfo.systemUptime + 3
        board.flushTldrawSnapshot { [weak self] in
            guard let self else {
                completion?(false)
                return
            }
            guard self.model.snapshot.currentDocument?.manifest.id
                    == documentID
            else {
                self.endCopyProgress(for: documentID)
                completion?(false)
                return
            }
            self.beginCopy(
                content,
                documentID: documentID,
                dictationDeadline: dictationDeadline,
                closesDocument: closesDocument,
                completion: completion
            )
        }
    }

    private func beginCopy(
        _ content: TraceCopyContent,
        documentID: UUID,
        dictationDeadline: TimeInterval,
        closesDocument: Bool,
        completion: ((Bool) -> Void)?
    ) {
        if content == .image {
            completeCopy(
                content,
                transcript: nil,
                documentID: documentID,
                closesDocument: closesDocument,
                completion: completion
            )
            return
        }
        beginProgressiveCopy(
            content, documentID: documentID,
            dictationDeadline: dictationDeadline,
            closesDocument: closesDocument, completion: completion
        )
    }

    private func beginProgressiveCopy(
        _ content: TraceCopyContent,
        documentID: UUID,
        dictationDeadline: TimeInterval,
        closesDocument: Bool,
        completion: ((Bool) -> Void)?
    ) {
        let copyID = latestCopyID
        let transcript = model.availableTranscriptForCopy
        let pendingVoice = model.detachVoiceForCopy()
        let timeout = max(
            0, dictationDeadline - ProcessInfo.processInfo.systemUptime
        )
        if content == .dictation, transcript == nil {
            endCopyProgress(for: documentID)
            guard let pendingVoice else {
                failCopy(for: documentID)
                completion?(false)
                return
            }
            let changeCount = NSPasteboard.general.changeCount
            model.finishBackgroundVoiceCopy(pendingVoice, timeout: timeout) { [weak self] result in
                guard let self else { return }
                let value: TraceBackgroundVoiceCopyResult
                do {
                    value = try result.get()
                } catch {
                    if self.latestCopyID == copyID {
                        self.showCopyStatus(
                            "Error", detail: error.localizedDescription,
                            documentID: documentID
                        )
                    }
                    completion?(false)
                    return
                }
                guard value.isComplete, let text = value.transcript,
                      !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                else {
                    if self.latestCopyID == copyID {
                        self.showCopyStatus(
                            "Partial",
                            detail: "No Dictation was copied. Available audio was retained.",
                            documentID: documentID
                        )
                    }
                    completion?(false)
                    return
                }
                guard NSPasteboard.general.changeCount == changeCount,
                      self.latestCopyID == copyID
                else {
                    completion?(false)
                    return
                }
                guard TraceClipboardPayload.writeTranscript(text, to: .general) else {
                    TraceLogger.shared.record(
                        .error, category: .clipboard,
                        "Background Dictation clipboard write failed"
                    )
                    self.showCopyStatus(
                        "Error", detail: "Dictation was saved but could not be copied.",
                        documentID: documentID
                    )
                    completion?(false)
                    return
                }
                if self.model.snapshot.currentDocument?.manifest.id == documentID,
                   self.model.snapshot.voiceState == .idle {
                    self.model.copyCompleted(closeDocument: closesDocument)
                }
                self.showCopyStatus(
                    "Copied", detail: "Dictation copied.", documentID: documentID
                )
                completion?(true)
            }
            return
        }
        let clipboardCopy = TraceProgressiveClipboardCopy()
        let fileName = model.snapshot.currentDocument?
            .packageURL.deletingPathExtension()
            .appendingPathExtension("pdf").lastPathComponent
            ?? TraceClipboardPayload.defaultDocumentFileName
        if let pendingVoice {
            model.finishBackgroundVoiceCopy(pendingVoice, timeout: timeout) { [weak self] result in
                guard let self else { return }
                switch result {
                case let .success(value):
                    if value.isComplete {
                        clipboardCopy.complete(
                            transcript: value.transcript
                        )
                    } else {
                        clipboardCopy.finishWithoutUpdate()
                    }
                case .failure:
                    clipboardCopy.finishWithoutUpdate(status: .failed)
                }
                if clipboardCopy.hasInitialCopy, self.latestCopyID == copyID {
                    self.showCopyStatus(
                        clipboardCopy.status.label,
                        detail: clipboardCopy.status.detail,
                        documentID: documentID
                    )
                }
            }
        }
        let copyImage: (NSImage?) -> Void = { [weak self] image in
            guard let self else { return }
            guard self.model.snapshot.currentDocument?.manifest.id == documentID,
                  content == .dictation || image != nil
            else {
                self.failCopy(for: documentID)
                completion?(false)
                return
            }
            let copied = clipboardCopy.copyInitial(
                transcript: transcript
            ) { text in
                switch content {
                case .all:
                    guard let image else { return false }
                    return TraceClipboardPayload.write(
                        image: image, transcript: text, to: .general
                    )
                case .document:
                    guard let image else { return false }
                    return TraceClipboardPayload.writeDocument(
                        image: image, transcript: text,
                        suggestedFileName: fileName, to: .general
                    )
                case .dictation:
                    guard let text else { return false }
                    return TraceClipboardPayload.writeTranscript(text, to: .general)
                case .image:
                    return false
                }
            }
            self.finishCopy(
                copied, documentID: documentID,
                closesDocument: closesDocument, completion: completion
            )
            if copied {
                let status = pendingVoice == nil
                    ? TraceProgressiveCopyStatus.copied
                    : clipboardCopy.status
                self.showCopyStatus(
                    status.label,
                    detail: status.detail,
                    documentID: documentID
                )
            }
        }
        if content == .dictation {
            copyImage(nil)
        } else {
            compositeImageForDocument(
                expectedDocumentID: documentID,
                completion: copyImage
            )
        }
    }

    private func showCopyStatus(
        _ label: String,
        detail: String,
        documentID: UUID
    ) {
        statusItem?.button?.toolTip = detail
        if model.snapshot.currentDocument?.manifest.id == documentID {
            board.showCopyStatus(label, detail: detail)
        }
    }

    private func completeCopy(
        _ content: TraceCopyContent,
        transcript: String?,
        documentID: UUID,
        closesDocument: Bool,
        completion: ((Bool) -> Void)?
    ) {
        guard model.snapshot.currentDocument?.manifest.id
                == documentID
        else {
            endCopyProgress(for: documentID)
            completion?(false)
            return
        }
        switch content {
        case .all:
            compositeImageForDocument(expectedDocumentID: documentID) { [weak self] image in
                guard let self else {
                    return
                }
                guard self.model.snapshot.currentDocument?.manifest.id
                        == documentID
                else {
                    self.endCopyProgress(for: documentID)
                    completion?(false)
                    return
                }
                guard let image else {
                    self.failCopy(for: documentID)
                    completion?(false)
                    return
                }
                self.finishCopy(
                    self.board.copyComposite(
                        image,
                        transcript: transcript
                    ),
                    documentID: documentID,
                    closesDocument: closesDocument,
                    completion: completion
                )
            }
            return
        case .dictation:
            guard let transcript else {
                failCopy(for: documentID)
                completion?(false)
                return
            }
            finishCopy(
                TraceClipboardPayload.writeTranscript(
                    transcript,
                    to: .general
                ),
                documentID: documentID,
                closesDocument: closesDocument,
                completion: completion
            )
        case .image:
            compositeImageForDocument(expectedDocumentID: documentID) { [weak self] image in
                guard let self else {
                    return
                }
                guard self.model.snapshot.currentDocument?.manifest.id
                        == documentID
                else {
                    self.endCopyProgress(for: documentID)
                    completion?(false)
                    return
                }
                guard let image else {
                    self.failCopy(for: documentID)
                    completion?(false)
                    return
                }
                self.finishCopy(
                    TraceClipboardPayload.writeImage(
                        image,
                        to: .general
                    ),
                    documentID: documentID,
                    closesDocument: closesDocument,
                    completion: completion
                )
            }
            return
        case .document:
            let suggestedFileName = model.snapshot.currentDocument.map {
                $0.packageURL
                    .deletingPathExtension()
                    .appendingPathExtension("pdf")
                    .lastPathComponent
            } ?? TraceClipboardPayload.defaultDocumentFileName
            compositeImageForDocument(expectedDocumentID: documentID) { [weak self] image in
                guard let self else {
                    return
                }
                guard self.model.snapshot.currentDocument?.manifest.id
                        == documentID
                else {
                    self.endCopyProgress(for: documentID)
                    completion?(false)
                    return
                }
                guard let image else {
                    self.failCopy(for: documentID)
                    completion?(false)
                    return
                }
                self.finishCopy(
                    self.board.copyDocument(
                        image,
                        transcript: transcript,
                        suggestedFileName: suggestedFileName
                    ),
                    documentID: documentID,
                    closesDocument: closesDocument,
                    completion: completion
                )
            }
            return
        }
    }

    private func finishCopy(
        _ copied: Bool,
        documentID: UUID,
        closesDocument: Bool,
        completion: ((Bool) -> Void)?
    ) {
        guard copied else {
            failCopy(for: documentID)
            completion?(false)
            return
        }
        guard model.snapshot.currentDocument?.manifest.id
                == documentID
        else {
            endCopyProgress(for: documentID)
            completion?(false)
            return
        }
        model.copyCompleted(closeDocument: closesDocument)
        endCopyProgress(for: documentID)
        completion?(true)
    }

    private func failCopy(for documentID: UUID) {
        TraceLogger.shared.record(.error, category: .clipboard, "Drawing copy failed")
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
        TraceLogger.shared.record(.error, category: .lifecycle, "Startup pen access failed", error: error)
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
