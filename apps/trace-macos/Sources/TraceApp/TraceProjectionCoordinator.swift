import AppKit
import CoreGraphics
import IOKit.pwr_mgt
import TraceAppCore

enum TraceProjectionMode: String, CaseIterable {
    case system
    case mirror
    case project
}

enum TraceProjectionOutput: Equatable {
    case hidden
    case black
    case document
}

enum TraceProjectionPolicy {
    static func presentationDisplayIDs(
        allDisplayIDs: [CGDirectDisplayID],
        workingDisplayID: CGDirectDisplayID
    ) -> [CGDirectDisplayID] {
        guard allDisplayIDs.count > 1 else {
            return []
        }
        return allDisplayIDs.filter { $0 != workingDisplayID }
    }

    static func mode(
        for displayKey: String,
        selectedDisplayKey: String?,
        selectedMode: TraceProjectionMode
    ) -> TraceProjectionMode {
        displayKey == selectedDisplayKey ? selectedMode : .system
    }

    static func editorIsVisible(in mode: TraceProjectionMode) -> Bool {
        mode != .project
    }

    static func output(
        mode: TraceProjectionMode,
        hasDocument: Bool,
        projectDocumentActivated: Bool
    ) -> TraceProjectionOutput {
        switch mode {
        case .system:
            return .hidden
        case .mirror:
            return hasDocument ? .document : .hidden
        case .project:
            return hasDocument && projectDocumentActivated
                ? .document
                : .black
        }
    }

    static func shouldHoldDisplayAwake(
        mode: TraceProjectionMode,
        hasDocument: Bool,
        projectDocumentActivated: Bool
    ) -> Bool {
        guard hasDocument else {
            return false
        }
        return mode != .project || projectDocumentActivated
    }

    static func menuTitle(
        for mode: TraceProjectionMode,
        systemPreferenceDescription: String
    ) -> String {
        switch mode {
        case .system:
            return "System preference — "
                + systemPreferenceDescription
        case .mirror:
            return "Mirror"
        case .project:
            return "Project"
        }
    }

    static func contentFrame(
        source: TraceSize,
        output: TraceSize
    ) -> TraceRect {
        guard source.width > 0,
              source.height > 0,
              output.width > 0,
              output.height > 0
        else {
            return TraceRect(x: 0, y: 0, width: 0, height: 0)
        }
        let scale = min(
            output.width / source.width,
            output.height / source.height
        )
        let width = source.width * scale
        let height = source.height * scale
        return TraceRect(
            x: round((output.width - width) / 2),
            y: round((output.height - height) / 2),
            width: width,
            height: height
        )
    }
}

final class TraceProjectionMenuAction: NSObject {
    let displayKey: String
    let mode: TraceProjectionMode

    init(displayKey: String, mode: TraceProjectionMode) {
        self.displayKey = displayKey
        self.mode = mode
    }
}

struct TraceProjectionDisplay {
    let key: String
    let name: String
    let displayID: CGDirectDisplayID
    let screen: NSScreen

    var systemPreferenceDescription: String {
        CGDisplayIsInMirrorSet(displayID) != 0
            ? "Mirrored"
            : "Extended"
    }
}

enum TraceProjectionPreferences {
    private static let displayKey = "TraceProjectionDisplayKey"
    private static let modeKey = "TraceProjectionMode"

    static func load(
        from defaults: UserDefaults
    ) -> (displayKey: String?, mode: TraceProjectionMode) {
        (
            displayKey: defaults.string(forKey: displayKey),
            mode: defaults.string(forKey: modeKey)
                .flatMap(TraceProjectionMode.init(rawValue:))
                ?? .system
        )
    }

    static func save(
        displayKey: String?,
        mode: TraceProjectionMode,
        to defaults: UserDefaults
    ) {
        defaults.set(displayKey, forKey: self.displayKey)
        defaults.set(mode.rawValue, forKey: modeKey)
    }
}

final class TraceProjectionCoordinator {
    var onDisplaysChange: (() -> Void)?
    var onEditorVisibilityChange: ((Bool) -> Void)?
    var workingScreenProvider: (() -> NSScreen?)?

    private(set) var displays: [TraceProjectionDisplay] = []

    private let defaults: UserDefaults
    private let projectionWindow = TraceProjectionWindowController()
    private let displayActivity = TraceDisplayActivity()
    private var selectedDisplayKey: String?
    private var selectedMode: TraceProjectionMode
    private var currentDocument: TraceDrawingSession?
    private var currentToolState = TraceToolState()
    private var screenObserver: NSObjectProtocol?
    private var editorIsVisible = true
    private var projectDocumentActivated = false

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        let saved = TraceProjectionPreferences.load(from: defaults)
        selectedDisplayKey = saved.displayKey
        selectedMode = saved.mode
    }

    func start() {
        guard screenObserver == nil else {
            return
        }
        screenObserver = NotificationCenter.default.addObserver(
            forName: NSApplication.didChangeScreenParametersNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            self?.refreshDisplays()
        }
        refreshDisplays()
    }

    func stop() {
        if let screenObserver {
            NotificationCenter.default.removeObserver(screenObserver)
            self.screenObserver = nil
        }
        currentDocument = nil
        projectDocumentActivated = false
        projectionWindow.hideProjection()
        displayActivity.end()
        editorIsVisible = true
    }

    func mode(for display: TraceProjectionDisplay) -> TraceProjectionMode {
        TraceProjectionPolicy.mode(
            for: display.key,
            selectedDisplayKey: selectedDisplayKey,
            selectedMode: selectedMode
        )
    }

    func setMode(
        _ mode: TraceProjectionMode,
        for display: TraceProjectionDisplay
    ) {
        selectedDisplayKey = display.key
        selectedMode = mode
        if mode == .project {
            projectDocumentActivated = false
        }
        TraceProjectionPreferences.save(
            displayKey: selectedDisplayKey,
            mode: selectedMode,
            to: defaults
        )
        updateDisplayActivity()
        applyPresentation()
        onDisplaysChange?()
    }

    func present(
        _ document: TraceDrawingSession,
        toolState: TraceToolState,
        activatesProjectOutput: Bool
    ) {
        let documentChanged =
            currentDocument?.manifest.id != document.manifest.id
        currentDocument = document
        currentToolState = toolState
        if selectedMode == .project {
            if activatesProjectOutput {
                projectDocumentActivated = true
            } else if documentChanged {
                projectDocumentActivated = false
            }
        }
        editorIsVisible = true
        refreshDisplays()
    }

    func hideProjection() {
        currentDocument = nil
        projectDocumentActivated = false
        displayActivity.end()
        editorIsVisible = true
        applyPresentation()
    }

    func apply(_ update: TraceAnnotationUpdate) {
        projectionWindow.apply(update)
    }

    func updateHover(_ update: TraceHoverUpdate?) {
        projectionWindow.updateHover(update)
    }

    func updateToolState(_ state: TraceToolState) {
        currentToolState = state
        projectionWindow.updateToolState(state)
    }

    func refreshBackground(_ color: TraceRGBAColor) {
        projectionWindow.refreshBackground(color)
    }

    func refreshGeometry() {
        projectionWindow.refreshGeometry()
    }

    func refreshDrawingHistory() {
        projectionWindow.refreshDrawingHistory()
    }

    func refreshTldrawSnapshot() {
        projectionWindow.refreshTldrawSnapshot()
    }

    func refreshTranscriptAnnotations() {
        projectionWindow.refreshTranscriptAnnotations()
    }

    func updateTranscriptAnnotationScale(
        _ scale: TraceTranscriptAnnotationScale
    ) {
        projectionWindow.updateTranscriptAnnotationScale(scale)
    }

    func workingDisplayDidChange() {
        refreshDisplays()
    }

    private func refreshDisplays() {
        let availableScreens = NSScreen.screens.compactMap { screen
            -> (screen: NSScreen, displayID: CGDirectDisplayID)? in
            guard let number = screen.deviceDescription[
                NSDeviceDescriptionKey("NSScreenNumber")
            ] as? NSNumber else {
                return nil
            }
            return (screen, CGDirectDisplayID(number.uint32Value))
        }
        let workingDisplayID = displayID(
            for: workingScreenProvider?()
                ?? NSScreen.main
                ?? availableScreens.first?.screen
        ) ?? CGMainDisplayID()
        let presentationIDs = Set(
            TraceProjectionPolicy.presentationDisplayIDs(
                allDisplayIDs: availableScreens.map(\.displayID),
                workingDisplayID: workingDisplayID
            )
        )
        displays = availableScreens.compactMap { screen, displayID in
            guard presentationIDs.contains(displayID) else {
                return nil
            }
            return TraceProjectionDisplay(
                key: displayKey(
                    displayID: displayID,
                    name: screen.localizedName
                ),
                name: screen.localizedName,
                displayID: displayID,
                screen: screen
            )
        }
        updateDisplayActivity()
        applyPresentation()
        onDisplaysChange?()
    }

    private func displayID(
        for screen: NSScreen?
    ) -> CGDirectDisplayID? {
        guard let number = screen?.deviceDescription[
            NSDeviceDescriptionKey("NSScreenNumber")
        ] as? NSNumber else {
            return nil
        }
        return CGDirectDisplayID(number.uint32Value)
    }

    private func applyPresentation() {
        guard let display = displays.first(where: {
            $0.key == selectedDisplayKey
        })
        else {
            projectionWindow.hideProjection()
            if currentDocument != nil {
                updateEditorVisibility(true)
            }
            return
        }
        let output = TraceProjectionPolicy.output(
            mode: selectedMode,
            hasDocument: currentDocument != nil,
            projectDocumentActivated: projectDocumentActivated
        )
        switch output {
        case .hidden:
            projectionWindow.hideProjection()
            if currentDocument != nil {
                updateEditorVisibility(true)
            }
        case .black:
            projectionWindow.presentBlack(on: display.screen)
            if currentDocument != nil {
                updateEditorVisibility(false)
            }
        case .document:
            guard let currentDocument else {
                projectionWindow.presentBlack(on: display.screen)
                return
            }
            projectionWindow.present(
                currentDocument,
                toolState: currentToolState,
                on: display.screen
            )
            updateEditorVisibility(
                TraceProjectionPolicy.editorIsVisible(in: selectedMode)
            )
        }
    }

    private func updateDisplayActivity() {
        let selectedDisplayAvailable = displays.contains {
            $0.key == selectedDisplayKey
        }
        let shouldHold = TraceProjectionPolicy.shouldHoldDisplayAwake(
            mode: selectedMode,
            hasDocument: currentDocument != nil,
            projectDocumentActivated: projectDocumentActivated
        ) && (
            selectedMode == .system
                ? !displays.isEmpty
                : selectedDisplayAvailable
        )
        if shouldHold {
            displayActivity.begin()
        } else {
            displayActivity.end()
        }
    }

    private func updateEditorVisibility(_ visible: Bool) {
        guard editorIsVisible != visible else {
            return
        }
        editorIsVisible = visible
        onEditorVisibilityChange?(visible)
    }

    private func displayKey(
        displayID: CGDirectDisplayID,
        name: String
    ) -> String {
        [
            String(CGDisplayVendorNumber(displayID)),
            String(CGDisplayModelNumber(displayID)),
            String(CGDisplaySerialNumber(displayID)),
            name,
        ].joined(separator: "-")
    }
}

private final class TraceDisplayActivity {
    private var displaySleepAssertion: IOPMAssertionID = 0
    private var userActivityAssertion: IOPMAssertionID = 0

    func begin() {
        if displaySleepAssertion == 0 {
            let result = IOPMAssertionCreateWithName(
                kIOPMAssertionTypePreventUserIdleDisplaySleep as CFString,
                IOPMAssertionLevel(kIOPMAssertionLevelOn),
                "Trace external display presentation" as CFString,
                &displaySleepAssertion
            )
            if result != kIOReturnSuccess {
                displaySleepAssertion = 0
            }
        }
        let result = IOPMAssertionDeclareUserActivity(
            "Trace external display presentation" as CFString,
            kIOPMUserActiveLocal,
            &userActivityAssertion
        )
        if result != kIOReturnSuccess {
            userActivityAssertion = 0
        }
    }

    func end() {
        if displaySleepAssertion != 0 {
            IOPMAssertionRelease(displaySleepAssertion)
            displaySleepAssertion = 0
        }
        if userActivityAssertion != 0 {
            IOPMAssertionRelease(userActivityAssertion)
            userActivityAssertion = 0
        }
    }

    deinit {
        end()
    }
}
