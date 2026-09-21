import AppKit
import CoreText
import KeyboardShortcuts
import NeoTransport
import QuartzCore
import TraceAppCore
import TraceCalibration
import TraceVoice

/*
 THESIS: The captured page remains the entire window; tldraw is an invisible
 interaction engine, never a second product shell.
 OWN-WORLD: Source pixels, four Trace colors, one graphite tool pill, native
 zoomable ink, and no tldraw chrome.
 STORY: Capture or open a blank page, draw with mouse or Neo, place images,
 then copy and return to the menu-bar agent.
 FIRST VIEWPORT: A selectable screenshot or native blank background fills
 the borderless canvas while Trace's toolbar floats above; imported images
 and ink live inside that same page space.
 FORM: Hidden-UI tldraw with Trace controls and a fixed native Metal overlay.
 */
enum TraceProductCanvasPolicy {
    static func usesTldraw(
        environment: [String: String],
        debugBuild: Bool
    ) -> Bool {
        _ = environment
        _ = debugBuild
        return true
    }
}

final class TraceBoardWindowController: NSWindowController, NSWindowDelegate {
    private static let toolbarHeight: CGFloat = 48
    private static let initialToolbarSize = NSSize(
        width: 1,
        height: toolbarHeight
    )
    private static let toolbarGap: CGFloat = 10
    private static let boardMargin: CGFloat = 18

    var onClose: (() -> Void)?
    var onToolChange: ((TraceToolState) -> Void)?
    var onDocumentEdited: ((
        [TraceDrawingStroke],
        [TraceDrawingStroke]
    ) -> Void)?
    var onTldrawSnapshotChange: ((
        String,
        [TraceTimedCanvasShape]
    ) -> Void)?
    var onTldrawUserEdit: ((Int) -> Void)?
    var onCopy: ((TraceCopyContent) -> Void)?
    var onCompleteOnboarding: (() -> Void)?
    var onRequestScreenAccess: (() -> Void)?
    var onRequestMicrophoneAccess: (() -> Void)?
    var onSaveOpenRouterAPIKey: ((String) -> Void)?
    var onRemoveOpenRouterAPIKey: (() -> Void)?
    var onToggleVoiceRecording: (() -> Void)?
    var onBackgroundColorChange: ((TraceRGBAColor) -> Void)?
    var onWorkingScreenChange: (() -> Void)?
    var onRecalibrate: (() -> Void)?
    var onCancelCalibration: (() -> Void)?
    var onBlankViewportResize: ((NSSize) -> Void)?
    var onGlobalShortcutsChange: (() -> Void)?

    private let drawingController = DrawingBoardViewController()
    private let transitionController = CaptureTransitionController()
    private let annotationToolbar = FloatingAnnotationToolbar()
    private let setupPanel = SetupPanelView()
    private let toolbarWindow = TraceToolbarPanel(
        contentRect: NSRect(
            origin: .zero,
            size: TraceBoardWindowController.initialToolbarSize
        ),
        styleMask: [.borderless, .nonactivatingPanel],
        backing: .buffered,
        defer: false
    )
    private let setupWindow = TraceToolbarPanel(
        contentRect: NSRect(
            origin: .zero,
            size: NSSize(width: 360, height: 420)
        ),
        styleMask: [.titled, .closable, .utilityWindow],
        backing: .buffered,
        defer: false
    )
    private var showingDocument = false
    private var isPositioningToolbar = false
    private var toolbarPositionScheduled = false
    private var toolbarBoardRepositionRequested = false
    private var setupRequested = false
    private var currentDrawingSession: TraceDrawingSession?
    private var applicationResignObserver: NSObjectProtocol?
    private var blankCanvasRevealPending = false
    private var currentToolState = TraceToolState()
#if DEBUG
    private var suppressFloatingToolbarOrderingForTesting = false
    private var toolbarRevealAnimatedForTesting = false
    private var toolbarPresentedForTesting = false

    func prepareOnboardingForPreview(
        _ snapshot: TraceAppSnapshot,
        shortcuts: TraceGlobalShortcutsSnapshot =
            TraceGlobalShortcutsSnapshot(),
        backgroundColor: TraceRGBAColor = TraceRGBAColor(
            red: 1,
            green: 1,
            blue: 1
        )
    ) {
        transitionController.cancel()
        let store = TraceDrawingStore(
            directoryURL: FileManager.default.temporaryDirectory
                .appendingPathComponent("TraceSetupPreview", isDirectory: true)
        )
        guard let document = try? store.createBlank(
            size: NSSize(width: 900, height: 650),
            backingScale: 1,
            backgroundColor: backgroundColor
        ) else {
            return
        }
        showingDocument = true
        suppressFloatingToolbarOrderingForTesting = true
        configureDocumentWindow(document)
        drawingController.setDocument(document, toolState: TraceToolState())
        annotationToolbar.setToolState(TraceToolState())
        window?.contentViewController = drawingController
        blankCanvasRevealPending = false
        toolbarRevealAnimatedForTesting = false
        toolbarPresentedForTesting = true
        window?.alphaValue = 1
        resizeForDocument(document)
        updateOnboarding(snapshot, shortcuts: shortcuts)
        configureToolbar(
            contentView: annotationToolbar,
            size: annotationToolbar.preferredSize
        )
        positionAnnotationToolbar()
    }

    private var toolbarPositionCountForTesting = 0
#endif

    init() {
        let window = TraceBoardWindow(
            contentRect: NSRect(x: 0, y: 0, width: 980, height: 660),
            styleMask: [.titled, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )
        window.setNativeResizingEnabled(false)
        window.isOpaque = false
        window.backgroundColor = .clear
        window.hasShadow = true
        window.isMovableByWindowBackground = false
        window.collectionBehavior = [.moveToActiveSpace, .fullScreenAuxiliary]
        window.animationBehavior = .utilityWindow
        super.init(window: window)
        window.delegate = self
        window.onPointerDown = { [weak self] in
            self?.annotationToolbar.dismissBackgroundPicker()
        }
        toolbarWindow.isOpaque = false
        toolbarWindow.backgroundColor = .clear
        toolbarWindow.hasShadow = false
        toolbarWindow.ignoresMouseEvents = false
        toolbarWindow.becomesKeyOnlyIfNeeded = true
        toolbarWindow.collectionBehavior = [
            .moveToActiveSpace,
            .fullScreenAuxiliary,
            .transient,
        ]
        annotationToolbar.frame = toolbarWindow.contentView?.bounds
            ?? NSRect(
                origin: .zero,
                size: Self.initialToolbarSize
            )
        annotationToolbar.autoresizingMask = [.width, .height]
        toolbarWindow.contentView = annotationToolbar
        toolbarWindow.onPointerDown = { [weak self] point in
            self?.annotationToolbar.handleToolbarPointerDown(
                at: point
            )
        }
        setupWindow.title = "Trace Setup"
        setupWindow.isOpaque = true
        setupWindow.backgroundColor = .windowBackgroundColor
        setupWindow.hasShadow = true
        setupWindow.ignoresMouseEvents = false
        setupWindow.becomesKeyOnlyIfNeeded = true
        setupWindow.isFloatingPanel = true
        setupWindow.hidesOnDeactivate = false
        setupWindow.delegate = self
        setupWindow.collectionBehavior = [
            .moveToActiveSpace,
            .fullScreenAuxiliary,
            .transient,
        ]
        setupWindow.contentView = setupPanel
        setupPanel.onRequestScreenAccess = { [weak self] in
            self?.onRequestScreenAccess?()
        }
        setupPanel.onRequestMicrophoneAccess = { [weak self] in
            self?.onRequestMicrophoneAccess?()
        }
        setupPanel.onSaveOpenRouterAPIKey = { [weak self] apiKey in
            self?.onSaveOpenRouterAPIKey?(apiKey)
        }
        setupPanel.onRemoveOpenRouterAPIKey = { [weak self] in
            self?.onRemoveOpenRouterAPIKey?()
        }
        setupPanel.onRecalibrate = { [weak self] in
            self?.onRecalibrate?()
        }
        setupPanel.onGlobalShortcutsChange = { [weak self] in
            self?.onGlobalShortcutsChange?()
        }
        applicationResignObserver = NotificationCenter.default.addObserver(
            forName: NSApplication.didResignActiveNotification,
            object: NSApp,
            queue: .main
        ) { [weak self] _ in
            self?.annotationToolbar.dismissBackgroundPicker()
        }

        annotationToolbar.onToolChange = { [weak self] state in
            self?.currentToolState = state
            self?.drawingController.setToolState(state)
            self?.drawingController.focusTldrawCanvas()
            self?.onToolChange?(state)
        }
        drawingController.onDocumentEdited = {
            [weak self] before, after in
            self?.onDocumentEdited?(before, after)
        }
        drawingController.onTldrawSnapshotChange = {
            [weak self] snapshot, timedShapes in
            self?.onTldrawSnapshotChange?(snapshot, timedShapes)
        }
        drawingController.onTldrawUserEdit = { [weak self] count in
            self?.onTldrawUserEdit?(count)
        }
        drawingController.onTldrawToolChange = { [weak self] state in
            self?.currentToolState = state
            self?.annotationToolbar.setToolState(state)
            self?.onToolChange?(state)
        }
        drawingController.onTldrawTemporaryToolChange = {
            [weak self] tool in
            self?.annotationToolbar.setTemporaryCanvasTool(tool)
        }
        drawingController.onTldrawPresentationReady = {
            [weak self] available in
            self?.finishBlankCanvasReveal(
                rendererAvailable: available
            )
        }
        annotationToolbar.onCopy = { [weak self] content in
            self?.onCopy?(content)
        }
        annotationToolbar.onClose = { [weak self] in
            guard let self else {
                return
            }
            let documentID = currentDrawingSession?.manifest.id
            flushTldrawSnapshot { [weak self] in
                guard let self,
                      currentDrawingSession?.manifest.id == documentID
                else {
                    return
                }
                onClose?()
            }
        }
        annotationToolbar.onToggleVoiceRecording = { [weak self] in
            self?.onToggleVoiceRecording?()
        }
        annotationToolbar.onBackgroundColorChange = { [weak self] color in
            self?.onBackgroundColorChange?(color)
            self?.drawingController.setBackgroundColor(color)
        }
        annotationToolbar.onPreferredSizeChange = { [weak self] in
            self?.refreshAnnotationToolbarSize()
        }
        drawingController.onCancelCalibration = { [weak self] in
            self?.onCancelCalibration?()
        }
    }

    required init?(coder: NSCoder) {
        nil
    }

    deinit {
        if let applicationResignObserver {
            NotificationCenter.default.removeObserver(
                applicationResignObserver
            )
        }
    }

    func showOnboarding(
        _ snapshot: TraceAppSnapshot,
        shortcuts: TraceGlobalShortcutsSnapshot =
            TraceGlobalShortcutsSnapshot()
    ) {
        updateOnboarding(snapshot, shortcuts: shortcuts)
        guard showingDocument else {
            return
        }
        showWindow(nil)
        window?.makeKeyAndOrderFront(nil)
        showAnnotationToolbar()
        showSetupPanelIfNeeded(snapshot)
        NSApp.activate(ignoringOtherApps: true)
    }

    func updateOnboarding(
        _ snapshot: TraceAppSnapshot,
        shortcuts: TraceGlobalShortcutsSnapshot =
            TraceGlobalShortcutsSnapshot()
    ) {
        setupRequested = snapshot.setupVisible && !snapshot.calibrationActive
        drawingController.updateSetup(snapshot, shortcuts: shortcuts)
        setupPanel.update(snapshot, shortcuts: shortcuts)
        configureSetupPanel(preservingTopLeft: setupWindow.isVisible)
        guard showingDocument else {
            return
        }
        if setupRequested {
            showSetupPanelIfNeeded(snapshot)
        } else {
            hideSetupPanel()
        }
    }

    func present(
        _ document: TraceDrawingSession,
        capture: CapturedWindow?,
        toolState: TraceToolState
    ) {
        showingDocument = true
#if DEBUG
        suppressFloatingToolbarOrderingForTesting = false
        toolbarRevealAnimatedForTesting = false
        toolbarPresentedForTesting = false
#endif
        blankCanvasRevealPending =
            capture == nil
                && BlankCanvasLoadingPolicy.waitsForRenderer(
                    pageKind: document.manifest.pageKind,
                    usesTldraw:
                        drawingController.usesTldrawProductCanvas
                )
        configureDocumentWindow(document)
        currentToolState = toolState
        annotationToolbar.setToolState(toolState)
        window?.contentViewController = drawingController
        resizeForDocument(document)
        if let capture, let window {
            window.setFrame(
                CaptureTransitionPolicy.finalBoardFrame(
                    sourceFrame: capture.sourceScreenFrame,
                    defaultFrame: window.frame
                ),
                display: true
            )
        }
        window?.alphaValue = capture == nil ? 1 : 0
        showWindow(nil)
        window?.layoutIfNeeded()
        drawingController.setDocument(
            document,
            toolState: toolState
        )
        NSApp.activate(ignoringOtherApps: true)

        guard let capture else {
            window?.makeKeyAndOrderFront(nil)
            showCapturelessToolbarIfReady()
            return
        }
        transitionController.animate(
            capture: capture,
            boardWindow: window,
            revealToolbar: { [weak self] animated in
                self?.showAnnotationToolbar(
                    animated: animated,
                    allowBoardReposition: false
                )
            },
            completion: {}
        )
    }

    func apply(_ update: TraceAnnotationUpdate) {
        annotationToolbar.dismissBackgroundPicker()
        drawingController.apply(update)
    }

    func updateHover(_ update: TraceHoverUpdate?) {
        drawingController.setHover(update)
    }

    func updateVoiceState(
        _ state: TraceVoiceCaptureState,
        dictationConfigured: Bool = true
    ) {
        annotationToolbar.setVoiceState(
            state,
            dictationConfigured: dictationConfigured
        )
    }

    func setCopyFinalizationActive(_ active: Bool) {
        annotationToolbar.setVoicePresentationSuppressed(active)
    }

    func updateVoiceLevel(_ level: Float) {
        annotationToolbar.setVoiceLevel(level)
    }

    func refreshDocumentGeometry() {
        guard let document = currentDrawingSession else {
            return
        }
        drawingController.refreshDocumentGeometry()
        let viewport = document.manifest.viewport
            ?? TracePageViewport.full
        let usesRoundedCorners =
            document.manifest.pageKind == .blank
                || viewport == TracePageViewport.full
        drawingController.setCornerRadius(
            usesRoundedCorners
                ? CGFloat(
                    document.manifest.sourceWindowCornerRadius ?? 0
                )
                : 0
        )
    }

    func refreshDrawingHistory() {
        drawingController.refreshDrawingHistory()
    }

    func refreshTldrawSnapshot() {
        drawingController.refreshTldrawSnapshot()
    }

    func refreshTranscriptAnnotations() {
        drawingController.refreshTranscriptAnnotations()
    }

    func updateTranscriptAnnotationScale(
        _ scale: TraceTranscriptAnnotationScale
    ) {
        drawingController.updateTranscriptAnnotationScale(scale)
    }

    func compositeImage(
        completion: @escaping (NSImage?) -> Void
    ) {
        guard showingDocument else {
            completion(nil)
            return
        }
        drawingController.compositeImage(completion: completion)
    }

    @discardableResult
    func insertImage(_ image: NSImage) -> Bool {
        drawingController.insertImage(image)
    }

    @discardableResult
    func insertImages(_ images: [TraceCanvasImage]) -> Bool {
        guard drawingController.insertImages(images) else {
            return false
        }
        resetToPen()
        return true
    }

    var canUndoTldraw: Bool {
        drawingController.canUndoTldraw
    }

    var canRedoTldraw: Bool {
        drawingController.canRedoTldraw
    }

    @discardableResult
    func undoTldrawIfAvailable() -> Bool {
        drawingController.undoTldrawIfAvailable()
    }

    @discardableResult
    func redoTldrawIfAvailable() -> Bool {
        drawingController.redoTldrawIfAvailable()
    }

    func flushTldrawSnapshot(completion: @escaping () -> Void) {
        drawingController.flushTldrawSnapshot(completion: completion)
    }

    func copyComposite(
        _ image: NSImage,
        transcript: String?
    ) -> Bool {
        TraceClipboardPayload.write(
            image: image,
            transcript: transcript,
            to: .general
        )
    }

    func hideBoard() {
        transitionController.cancel()
        blankCanvasRevealPending = false
        hideAnnotationToolbar()
        hideSetupPanel()
        drawingController.setHover(nil)
        window?.orderOut(nil)
    }

    func setEditorVisible(_ visible: Bool) {
        guard showingDocument else {
            return
        }
        if visible {
            showWindow(nil)
            window?.makeKeyAndOrderFront(nil)
            showAnnotationToolbar()
            if setupRequested {
                showSetupPanel()
            }
        } else {
            hideAnnotationToolbar()
            hideSetupPanel()
            window?.orderOut(nil)
        }
    }

    var workingScreen: NSScreen? {
        window?.screen
    }

#if DEBUG
    func prepareDocumentForPreview(
        _ document: TraceDrawingSession,
        toolState: TraceToolState
    ) {
        showingDocument = true
        suppressFloatingToolbarOrderingForTesting = true
        toolbarRevealAnimatedForTesting = false
        toolbarPresentedForTesting = false
        blankCanvasRevealPending =
            BlankCanvasLoadingPolicy.waitsForRenderer(
                pageKind: document.manifest.pageKind,
                usesTldraw:
                    drawingController.usesTldrawProductCanvas
            )
        configureDocumentWindow(document)
        currentToolState = toolState
        annotationToolbar.setToolState(toolState)
        window?.contentViewController = drawingController
        resizeForDocument(document)
        window?.layoutIfNeeded()
        drawingController.setDocument(document, toolState: toolState)
        showCapturelessToolbarIfReady()
    }

    var blankCanvasLoadingForPreview: (
        pending: Bool,
        tldrawReady: Bool,
        tldrawAlpha: CGFloat,
        surfaceDisplaysScreenshot: Bool,
        rootBackgroundColor: NSColor?,
        toolbarPresented: Bool,
        toolbarRevealAnimated: Bool
    ) {
        let presentation =
            drawingController.blankCanvasLoadingForPreview
        return (
            pending: blankCanvasRevealPending,
            tldrawReady: presentation.tldrawReady,
            tldrawAlpha: presentation.tldrawAlpha,
            surfaceDisplaysScreenshot:
                presentation.surfaceDisplaysScreenshot,
            rootBackgroundColor:
                presentation.rootBackgroundColor,
            toolbarPresented:
                toolbarPresentedForTesting,
            toolbarRevealAnimated:
                toolbarRevealAnimatedForTesting
        )
    }

    func configureInvisibleProbeWindows() {
        window?.alphaValue = 0
        window?.ignoresMouseEvents = true
        toolbarWindow.alphaValue = 0
        toolbarWindow.ignoresMouseEvents = true
    }

    var invisibleProbeWindowState: (
        boardAlpha: CGFloat,
        toolbarAlpha: CGFloat,
        boardIsKey: Bool,
        toolbarIsKey: Bool
    ) {
        (
            boardAlpha: window?.alphaValue ?? 1,
            toolbarAlpha: toolbarWindow.alphaValue,
            boardIsKey: window?.isKeyWindow == true,
            toolbarIsKey: toolbarWindow.isKeyWindow
        )
    }

    func selectStrokesForPreview(_ strokeIDs: Set<UInt64>) {
        drawingController.selectStrokesForPreview(strokeIDs)
    }

    var completedInkRenderCountForPreview: Int {
        drawingController.completedInkRenderCountForPreview
    }

    var boardContentSizeForPreview: NSSize {
        window?.contentView?.bounds.size ?? .zero
    }

    var boardWindowChromeForPreview: (
        titled: Bool,
        resizable: Bool,
        fullSizeContent: Bool,
        titleHidden: Bool,
        titlebarTransparent: Bool,
        titlebarSeparatorHidden: Bool,
        visibleStandardButtonCount: Int,
        frameSize: NSSize,
        contentSize: NSSize,
        nativeFrameOwnsEdges: Bool,
        topContentInteractive: Bool
    ) {
        (window as? TraceBoardWindow)?.chromeForTesting ?? (
            false,
            false,
            false,
            false,
            false,
            false,
            0,
            .zero,
            .zero,
            false,
            false
        )
    }

    func resizeBoardForPreview(to size: NSSize) {
        window?.setContentSize(size)
        window?.layoutIfNeeded()
    }

    func endLiveResizeForPreview() {
        windowDidEndLiveResize(
            Notification(name: NSWindow.didEndLiveResizeNotification)
        )
    }

    func cancelCalibrationForPreview() {
        drawingController.cancelCalibrationForTesting()
    }

    var toolbarInteractionForPreview: (
        hasWindowShadow: Bool,
        boardMovesFromBackground: Bool,
        emptyAreaDrags: Bool,
        controlAreaDrags: Bool
    ) {
        configureToolbar(
            contentView: annotationToolbar,
            size: annotationToolbar.preferredSize
        )
        annotationToolbar.layoutSubtreeIfNeeded()
        let dragRegions = annotationToolbar.dragRegionsForTesting
        return (
            hasWindowShadow: toolbarWindow.hasShadow,
            boardMovesFromBackground:
                window?.isMovableByWindowBackground ?? true,
            emptyAreaDrags: dragRegions.emptyArea,
            controlAreaDrags: dragRegions.controlArea
        )
    }

    var backgroundControlLayoutForPreview: (
        backgroundIndex: Int?,
        gridIndex: Int?,
        separatorIndex: Int?,
        colorsIndex: Int?,
        backgroundHidden: Bool,
        separatorHidden: Bool
    ) {
        annotationToolbar.backgroundControlLayoutForTesting
    }

    var backgroundSwatchPresentationForPreview: (
        size: NSSize,
        usesQuickSwatches: Bool,
        color: NSColor
    ) {
        annotationToolbar.backgroundSwatchPresentationForTesting
    }

    func activateBackgroundPickerForPreview() -> (
        isActive: Bool,
        panelVisible: Bool
    ) {
        annotationToolbar.activateBackgroundPickerForTesting()
    }

    var backgroundPickerStateForPreview: (
        isActive: Bool,
        panelVisible: Bool
    ) {
        annotationToolbar.backgroundPickerStateForTesting
    }

    func dismissBackgroundPickerForPreview() {
        annotationToolbar.dismissBackgroundPickerForTesting()
    }

    func selectBackgroundQuickColorForPreview(
        _ color: TraceRGBAColor
    ) {
        annotationToolbar.selectBackgroundQuickColorForTesting(color)
    }

    func focusCanvasForPreview() {
        (window as? TraceBoardWindow)?.notifyPointerDownForTesting()
    }

    func focusToolbarControlForPreview() {
        toolbarWindow.notifyPointerDownForTesting(
            at: NSPoint(x: toolbarWindow.frame.width / 2, y: 24)
        )
    }

    func focusBackgroundColorWellForPreview() {
        toolbarWindow.notifyPointerDownForTesting(
            at: annotationToolbar.backgroundColorWellPointForTesting
        )
    }

    var gridSpacingPresentationForPreview: (
        unitText: String?,
        accessibilityLabel: String?,
        fieldHeight: CGFloat,
        gridControlHeight: CGFloat,
        backgroundAlpha: CGFloat,
        hoverBackgroundAlpha: CGFloat,
        focusBackgroundAlpha: CGFloat,
        focusBorderAlpha: CGFloat,
        focusBorderWidth: CGFloat,
        disabledBackgroundAlpha: CGFloat,
        disabledTextAlpha: CGFloat,
        textAlpha: CGFloat,
        drawsBackground: Bool,
        isBezeled: Bool,
        focusRingType: NSFocusRingType,
        isEditable: Bool,
        isSelectable: Bool,
        fontSize: CGFloat,
        baselineOffset: CGFloat,
        focusedEditorRect: CGRect,
        focusedBaselineOffset: CGFloat,
        focusedGlyphCenterOffset: CGFloat
    ) {
        annotationToolbar.gridSpacingPresentationForTesting
    }

    var copyControlForPreview: (
        title: String,
        hasImage: Bool,
        toolTip: String?,
        isBordered: Bool,
        hasCustomBackground: Bool,
        width: CGFloat,
        hasChevron: Bool,
        menuTitles: [String],
        menuImageCount: Int,
        menuOpensBelow: Bool,
        menuGap: CGFloat,
        totalWidth: CGFloat
    ) {
        annotationToolbar.copyControlForTesting
    }

    var toolbarGroupLayoutForPreview: (
        contentCenterOffset: CGFloat,
        gridAccessoryGap: CGFloat,
        gridDividerVisible: Bool,
        toolSeparatorIndex: Int?,
        brushIndex: Int?,
        strokeIndex: Int?,
        voiceSeparatorIndex: Int?,
        voiceIndex: Int?,
        recordingSeparatorIndex: Int?,
        copyIndex: Int?,
        actionSeparatorIndex: Int?,
        closeIndex: Int?,
        separatorNeighborGaps: [CGFloat]
    ) {
        annotationToolbar.toolbarGroupLayoutForTesting
    }

    var toolbarSizingForPreview: (
        inactive: (
            toolbarWidth: CGFloat,
            leftInset: CGFloat,
            rightInset: CGFloat,
            gridCenterX: CGFloat,
            gridLeftReserve: CGFloat,
            gridRightReserve: CGFloat,
            backgroundToGridGap: CGFloat?,
            gridToColorsGap: CGFloat,
            spacingVisible: Bool
        ),
        active: (
            toolbarWidth: CGFloat,
            leftInset: CGFloat,
            rightInset: CGFloat,
            gridCenterX: CGFloat,
            gridLeftReserve: CGFloat,
            gridRightReserve: CGFloat,
            backgroundToGridGap: CGFloat?,
            gridToColorsGap: CGFloat,
            spacingVisible: Bool
        )
    ) {
        var state = TraceToolState()
        state.gridStyle = .none
        annotationToolbar.setToolState(state)
        configureToolbar(
            contentView: annotationToolbar,
            size: annotationToolbar.preferredSize
        )
        let inactive = annotationToolbar.toolbarSizingForTesting
        state.gridStyle = .square
        annotationToolbar.setToolState(state)
        configureToolbar(
            contentView: annotationToolbar,
            size: annotationToolbar.preferredSize
        )
        let active = annotationToolbar.toolbarSizingForTesting
        state.gridStyle = .none
        annotationToolbar.setToolState(state)
        configureToolbar(
            contentView: annotationToolbar,
            size: annotationToolbar.preferredSize
        )
        return (inactive, active)
    }

    var toolbarIconMetricsForPreview: (
        voiceHeight: CGFloat,
        copyHeight: CGFloat,
        closeHeight: CGFloat,
        brushHeights: [CGFloat],
        gridHeights: [CGFloat],
        brushControlHeight: CGFloat,
        swatchDiameter: CGFloat,
        sliderControlSize: UInt,
        sliderCellType: String,
        sliderKnobSize: NSSize
    ) {
        annotationToolbar.toolbarIconMetricsForTesting
    }

    var gridSelectorPresentationForPreview: (
        isPopUp: Bool,
        displaysSelectedImageOnly: Bool,
        controlWidth: CGFloat,
        accessibilityLabel: String?,
        selectedTitle: String?,
        selectedStyle: TraceGridStyle,
        menuTitles: [String],
        menuImageCount: Int
    ) {
        annotationToolbar.gridSelectorPresentationForTesting
    }

    func selectGridStyleForPreview(_ style: TraceGridStyle) {
        annotationToolbar.selectGridStyleForTesting(style)
    }

    var drawingToolPresentationForPreview: (
        selectedSegment: Int,
        toolTips: [String?],
        closeToolTip: String?
    ) {
        annotationToolbar.drawingToolPresentationForTesting
    }

    var controlAccentPresentationForPreview: (
        brush: Bool,
        grid: Bool,
        slider: Bool
    ) {
        annotationToolbar.controlAccentPresentationForTesting
    }

    var actionHoverPresentationForPreview: (
        brushAttached: Bool,
        brushAlpha: CGFloat,
        micAlpha: CGFloat,
        copyAlpha: CGFloat,
        closeAlpha: CGFloat,
        cornerRadii: [CGFloat]
    ) {
        annotationToolbar.actionHoverPresentationForTesting
    }

    var productRendererStateForPreview: (
        nativeLayersAttached: Bool,
        tldrawAttached: Bool,
        surfaceDisplaysScreenshot: Bool,
        tldrawErrorVisible: Bool
    ) {
        drawingController.productRendererStateForTesting
    }

    func productCanvasStateForPreview() async -> [String: Any]? {
        await drawingController.productCanvasStateForTesting()
    }

    func showProductRendererErrorForPreview(_ detail: String) {
        drawingController.showProductRendererErrorForTesting(detail)
    }

    func setActionHoverForPreview(_ hovered: Bool) {
        annotationToolbar.setActionHoverForTesting(hovered)
    }

    func setColorSwatchHoverForPreview(
        index: Int,
        hovered: Bool
    ) {
        annotationToolbar.setColorSwatchHoverForTesting(
            index: index,
            hovered: hovered
        )
    }

    func colorSwatchPresentationForPreview(
        index: Int
    ) -> (
        borderWidth: CGFloat,
        borderAlpha: CGFloat,
        isSelected: Bool
    )? {
        annotationToolbar.colorSwatchPresentationForTesting(
            index: index
        )
    }

    func setTemporaryDrawingToolForPreview(
        _ tool: TraceCanvasTool?
    ) {
        annotationToolbar.setTemporaryCanvasTool(tool)
    }

    var isBoardResizableForPreview: Bool {
        window?.styleMask.contains(.resizable) == true
    }

    var setupStateForPreview: (
        setupVisible: Bool,
        calibrationVisible: Bool,
        panelUsesStandaloneWindow: Bool,
        panelUsesNativeWindowChrome: Bool,
        panelIsOutsideDrawingArea: Bool,
        paintsReplacementBackground: Bool,
        panelUsesDarkAppearance: Bool,
        calibrationUsesDarkAppearance: Bool,
        panelBackgroundBrightness: CGFloat,
        calibrationBackgroundBrightness: CGFloat,
        calibrationBackgroundAlpha: CGFloat,
        panelFrame: NSRect,
        penTitle: String,
        penDetail: String,
        penAction: String?,
        captureAction: String?,
        voiceAction: String?,
        voiceReady: Bool,
        usesRegularItemTypography: Bool,
        apiKeyFieldVisible: Bool,
        apiKeySaveVisible: Bool,
        apiKeyRemoveVisible: Bool,
        apiKeyResetTitle: String?,
        apiKeyResetUsesLinkStyle: Bool,
        errorUsesConstrainedWrapping: Bool,
        blankShortcut: String,
        blankShortcutDetail: String,
        captureShortcut: String,
        captureShortcutDetail: String
    ) {
        let panelState = setupPanel.stateForTesting
        let calibration =
            drawingController.calibrationStateForTesting
        let boardFrame = window?.frame ?? .zero
        let panelFrame = setupWindow.frame
        return (
            setupRequested && !calibration.visible,
            calibration.visible,
            setupWindow.contentView === setupPanel,
            setupWindow.styleMask.contains(.titled)
                && setupWindow.styleMask.contains(.closable)
                && setupWindow.styleMask.contains(.utilityWindow),
            !panelFrame.intersects(boardFrame),
            calibration.paintsReplacementBackground,
            setupPanel.appearance?.name == .darkAqua,
            calibration.usesDarkAppearance,
            setupPanel.backgroundBrightnessForTesting,
            calibration.backgroundBrightness,
            calibration.backgroundAlpha,
            panelFrame,
            panelState.penTitle,
            panelState.penDetail,
            panelState.penAction,
            panelState.captureAction,
            panelState.voiceAction,
            panelState.voiceReady,
            panelState.usesRegularItemTypography,
            panelState.apiKeyFieldVisible,
            panelState.apiKeySaveVisible,
            panelState.apiKeyRemoveVisible,
            panelState.apiKeyResetTitle,
            panelState.apiKeyResetUsesLinkStyle,
            panelState.errorUsesConstrainedWrapping,
            panelState.blankShortcut,
            panelState.blankShortcutDetail,
            panelState.captureShortcut,
            panelState.captureShortcutDetail
        )
    }

    func shortcutConflictPolicyForPreview(
        _ action: TraceGlobalShortcutAction
    ) -> KeyboardShortcuts.ConflictPolicy {
        setupPanel.shortcutConflictPolicyForTesting(action)
    }

    var setupVisibleTextForPreview: [String] {
        setupPanel.visibleTextForTesting
    }

    func shortcutValidationForPreview(
        _ action: TraceGlobalShortcutAction,
        shortcut: KeyboardShortcuts.Shortcut
    ) -> KeyboardShortcuts.ValidationResult {
        setupPanel.shortcutValidationForTesting(
            action,
            shortcut: shortcut
        )
    }

    func showToolbarForResizePreview() {
        showAnnotationToolbar()
    }

    func resetToolbarPositionCountForPreview() {
        toolbarPositionCountForTesting = 0
    }

    var toolbarPositionCountForPreview: Int {
        toolbarPositionCountForTesting
    }

    var toolbarVerticalGapForPreview: CGFloat {
        toolbarWindow.frame.minY - (window?.frame.maxY ?? 0)
    }

    func performNativeResizeForPreview() -> (
        before: NSSize,
        after: NSSize
    ) {
        window?.alphaValue = 0
        toolbarWindow.alphaValue = 0
        return (window as? TraceBoardWindow)?
            .performNativeResizeForTesting() ?? (.zero, .zero)
    }

    var activeInkRenderCountForPreview: Int {
        drawingController.activeInkRenderCountForPreview
    }

    var hoverStateForPreview: (
        point: TracePoint?,
        diameter: Double,
        opacity: Double,
        renderCount: Int
    ) {
        drawingController.hoverStateForPreview
    }

    func displayHoverForPreview() {
        drawingController.displayHoverForPreview()
    }

    var hoverViewForPreview: NSView {
        drawingController.hoverViewForPreview
    }

    var completedInkHiddenForPreview: Bool {
        drawingController.completedInkHiddenForPreview
    }

    func resetInkRenderCountsForPreview() {
        drawingController.resetInkRenderCountsForPreview()
    }

    func displayInkLayersForPreview() {
        drawingController.displayInkLayersForPreview()
    }

    var submittedGridFrameCountForPreview: Int {
        drawingController.submittedGridFrameCountForPreview
    }

    var submittedGridStateForPreview: (
        style: TraceGridStyle,
        spacingPoints: Int
    )? {
        drawingController.submittedGridStateForPreview
    }

    func resetSubmittedGridFrameCountForPreview() {
        drawingController.resetSubmittedGridFrameCountForPreview()
    }

    func flushScheduledGridDrawForPreview() {
        drawingController.flushScheduledGridDrawForPreview()
    }

    func setGridForPreview(
        style: TraceGridStyle,
        spacingPoints: Int
    ) {
        drawingController.setGrid(
            style: style,
            spacingPoints: spacingPoints
        )
    }

    func showBehindForPreview() {
        window?.level = NSWindow.Level(
            rawValue: Int(CGWindowLevelForKey(.desktopWindow))
        )
        window?.orderFrontRegardless()
    }

    func hideAfterPreview() {
        window?.orderOut(nil)
    }

    func inkLayerSnapshotsForPreview() -> (
        completed: NSImage?,
        active: NSImage?
    ) {
        drawingController.invalidateInkLayersForPreview()
        return (
            snapshotImage(
                of: drawingController.completedInkViewForPreview
            ),
            snapshotImage(
                of: drawingController.activeInkViewForPreview
            )
        )
    }

    func compositeImageForPreview() -> NSImage? {
        drawingController.nativeCompositeImageForPreview()
    }

    var voiceStateApplyCountForPreview: Int {
        annotationToolbar.voiceStateApplyCountForTesting
    }

    var voicePresentationForPreview: (
        label: String,
        labelHidden: Bool,
        toggleSymbol: String,
        toggleTint: NSColor?,
        waveformColor: NSColor,
        toggleEnabled: Bool,
        copyEnabled: Bool
    ) {
        annotationToolbar.voicePresentationForTesting
    }

    func resetVoiceStateApplyCountForPreview() {
        annotationToolbar.resetVoiceStateApplyCountForTesting()
    }

    func writeVoiceToolbarSnapshotForPreview(
        to url: URL
    ) throws {
        annotationToolbar.showBackgroundControlForTesting()
        var toolState = TraceToolState()
        toolState.gridStyle = .square
        annotationToolbar.setToolState(toolState)
        annotationToolbar.setVoiceState(
            .recording(transcribedChunks: 2)
        )
        for level: Float in [0.2, 0.7, 0.4, 0.95, 0.35, 0.6, 0.25] {
            annotationToolbar.setVoiceLevel(level)
        }
        configureToolbar(
            contentView: annotationToolbar,
            size: annotationToolbar.preferredSize
        )
        annotationToolbar.layoutSubtreeIfNeeded()
        guard let image = snapshotImage(of: annotationToolbar),
              let tiff = image.tiffRepresentation,
              let representation = NSBitmapImageRep(data: tiff),
              let png = representation.representation(
                  using: .png,
                  properties: [:]
              )
        else {
            return
        }
        try png.write(to: url, options: .atomic)
    }

    func triggerCopyForPreview(_ content: TraceCopyContent) {
        annotationToolbar.triggerCopyForTesting(content)
    }

    func selectBackgroundColorForPreview(_ color: TraceRGBAColor) {
        annotationToolbar.selectBackgroundColorForTesting(color)
    }

    func moveSelectedStrokesForPreview(delta: TracePoint) {
        drawingController.moveSelectedStrokesForPreview(delta: delta)
    }

    func deleteSelectedStrokesForPreview() {
        drawingController.deleteSelectedStrokesForPreview()
    }

    func writeSnapshot(
        to url: URL,
        includeConfiguredToolbar: Bool = false
    ) throws {
        guard let window,
              let boardView = window.contentView,
              let boardImage = snapshotImage(of: boardView)
        else {
            return
        }

        let toolbarSnapshot = (
            toolbarWindow.isVisible || includeConfiguredToolbar
        )
            ? toolbarWindow.contentView.flatMap(snapshotImage)
            : nil
        let setupSnapshot = setupRequested
            ? setupWindow.contentView.flatMap(snapshotImage)
            : nil
        let setupContentFrame = NSRect(
            x: setupWindow.frame.minX
                + setupWindow.contentLayoutRect.minX,
            y: setupWindow.frame.minY
                + setupWindow.contentLayoutRect.minY,
            width: setupWindow.contentLayoutRect.width,
            height: setupWindow.contentLayoutRect.height
        )
        var captureFrame = window.frame
        if toolbarSnapshot != nil {
            captureFrame = captureFrame.union(toolbarWindow.frame)
        }
        if setupSnapshot != nil {
            captureFrame = captureFrame.union(setupContentFrame)
        }
        let scale = max(
            window.backingScaleFactor,
            toolbarWindow.backingScaleFactor
        )
        guard let representation = NSBitmapImageRep(
            bitmapDataPlanes: nil,
            pixelsWide: Int((captureFrame.width * scale).rounded()),
            pixelsHigh: Int((captureFrame.height * scale).rounded()),
            bitsPerSample: 8,
            samplesPerPixel: 4,
            hasAlpha: true,
            isPlanar: false,
            colorSpaceName: .deviceRGB,
            bitmapFormat: [],
            bytesPerRow: 0,
            bitsPerPixel: 0
        ) else {
            return
        }
        representation.size = captureFrame.size
        guard let context = NSGraphicsContext(
            bitmapImageRep: representation
        ) else {
            return
        }
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = context
        context.cgContext.clear(
            CGRect(origin: .zero, size: captureFrame.size)
        )
        boardImage.draw(
            in: NSRect(
                origin: NSPoint(
                    x: window.frame.minX - captureFrame.minX,
                    y: window.frame.minY - captureFrame.minY
                ),
                size: window.frame.size
            )
        )
        if let toolbarSnapshot {
            toolbarSnapshot.draw(
                in: NSRect(
                    origin: NSPoint(
                        x: toolbarWindow.frame.minX
                            - captureFrame.minX,
                        y: toolbarWindow.frame.minY
                            - captureFrame.minY
                    ),
                    size: toolbarWindow.frame.size
                )
            )
        }
        if let setupSnapshot {
            NSColor.windowBackgroundColor.setFill()
            NSRect(
                origin: NSPoint(
                    x: setupContentFrame.minX - captureFrame.minX,
                    y: setupContentFrame.minY - captureFrame.minY
                ),
                size: setupContentFrame.size
            ).fill()
            setupSnapshot.draw(
                in: NSRect(
                    origin: NSPoint(
                        x: setupContentFrame.minX - captureFrame.minX,
                        y: setupContentFrame.minY - captureFrame.minY
                    ),
                    size: setupContentFrame.size
                )
            )
        }
        NSGraphicsContext.restoreGraphicsState()

        if let data = representation.representation(
            using: .png,
            properties: [:]
        ) {
            try data.write(to: url, options: .atomic)
        }
    }

    func writeComposite(to url: URL) throws {
        guard let image = drawingController
              .nativeCompositeImageForPreview(),
              let representation = image.representations.first
                as? NSBitmapImageRep,
              let data = representation.representation(
                  using: .png,
                  properties: [:]
              )
        else {
            return
        }
        try data.write(to: url, options: .atomic)
    }

    private func snapshotImage(of view: NSView) -> NSImage? {
        guard let representation = view.bitmapImageRepForCachingDisplay(
            in: view.bounds
        ) else {
            return nil
        }
        view.cacheDisplay(in: view.bounds, to: representation)
        let image = NSImage(size: view.bounds.size)
        image.addRepresentation(representation)
        return image
    }
#endif

    func windowShouldClose(_ sender: NSWindow) -> Bool {
        if sender === setupWindow {
            onCompleteOnboarding?()
            return false
        }
        onClose?()
        return false
    }

    func windowDidMove(_ notification: Notification) {
        onWorkingScreenChange?()
        if setupWindow.isVisible {
            positionSetupPanel()
        }
        guard toolbarWindow.isVisible, !isPositioningToolbar else {
            return
        }
        scheduleAnnotationToolbarPosition(allowBoardReposition: true)
    }

    func windowDidResize(_ notification: Notification) {
        if toolbarWindow.isVisible, !isPositioningToolbar {
            scheduleAnnotationToolbarPosition()
        }
        if setupWindow.isVisible {
            positionSetupPanel()
        }
    }

    func windowDidEndLiveResize(_ notification: Notification) {
        guard showingDocument else {
            return
        }
        if currentDrawingSession?.manifest.pageKind == .blank,
           let size = window?.contentView?.bounds.size
        {
            onBlankViewportResize?(size)
        }
        scheduleAnnotationToolbarPosition(allowBoardReposition: true)
    }

    func calibratedBlankViewportSize(
        aspectRatio: Double
    ) -> NSSize? {
        guard currentDrawingSession?.manifest.pageKind == .blank,
              let window
        else {
            return nil
        }
        let visible = preferredScreen()?.visibleFrame
            ?? NSRect(x: 0, y: 0, width: 1_200, height: 800)
        let maximum = TraceSize(
            width: max(1, visible.width - Self.boardMargin * 2),
            height: max(
                1,
                visible.height
                    - Self.boardMargin * 2
                    - annotationToolbar.preferredSize.height
                    - Self.toolbarGap
            )
        )
        let reference = window.contentView?.bounds.size
            ?? window.frame.size
        let fitted = TraceBlankViewportPolicy.calibrated(
            aspectRatio: aspectRatio,
            reference: TraceSize(
                width: reference.width,
                height: reference.height
            ),
            maximum: maximum
        )
        return NSSize(
            width: round(fitted.width),
            height: round(fitted.height)
        )
    }

    func applyCurrentDocumentGeometry() {
        guard let document = currentDrawingSession else {
            return
        }
        resizeForDocument(document)
        drawingController.refreshDocumentGeometry()
        window?.layoutIfNeeded()
    }

    private func configureDocumentWindow(
        _ document: TraceDrawingSession
    ) {
        currentDrawingSession = document
        (window as? TraceBoardWindow)?
            .setNativeResizingEnabled(true)
        window?.minSize = NSSize(width: 320, height: 240)
        window?.maxSize = NSSize(width: 4_096, height: 4_096)
        annotationToolbar.setDocument(document)
    }

    private func resetToPen() {
        let state = currentToolState.resettingCanvasToPen
        currentToolState = state
        drawingController.setToolState(state)
        annotationToolbar.setToolState(state)
        onToolChange?(state)
    }

    private func resizeForDocument(_ document: TraceDrawingSession) {
        guard let window else {
            return
        }
        let visible = preferredScreen()?.visibleFrame
            ?? NSRect(x: 0, y: 0, width: 1200, height: 800)
        let fullSource = document.manifest.sourceWindowBounds.map {
            NSSize(width: $0.width, height: $0.height)
        } ?? document.screenshot.size
        let source: NSSize
        if document.manifest.pageKind == .blank {
            source = fullSource
        } else {
            let viewport = document.manifest.viewport
                ?? TracePageViewport.full
            source = NSSize(
                width: fullSource.width * viewport.width,
                height: fullSource.height * viewport.height
            )
        }
        let width = max(1, source.width)
        let height = max(1, source.height)
        let layout = TraceBoardLayoutPolicy.place(
            source: TraceSize(width: width, height: height),
            visibleFrame: TraceRect(
                x: visible.minX,
                y: visible.minY,
                width: visible.width,
                height: visible.height
            ),
            toolbar: TraceSize(
                width: annotationToolbar.preferredSize.width,
                height: annotationToolbar.preferredSize.height
            ),
            gap: Self.toolbarGap,
            margin: Self.boardMargin
        )
        let boardFrame = NSRect(
            x: layout.board.x,
            y: layout.board.y,
            width: layout.board.width,
            height: layout.board.height
        )
        let toolbarFrame = NSRect(
            x: layout.toolbar.x,
            y: layout.toolbar.y,
            width: layout.toolbar.width,
            height: layout.toolbar.height
        )
        window.setFrame(boardFrame, display: true)
        toolbarWindow.setFrame(toolbarFrame, display: false)
        let viewport = document.manifest.viewport
            ?? TracePageViewport.full
        let isCropped = viewport != TracePageViewport.full
        drawingController.setCornerRadius(
            document.manifest.pageKind != .blank
                && (isCropped || layout.board.width < width)
                ? 0
                : CGFloat(
                    (document.manifest.sourceWindowCornerRadius ?? 0)
                        * (layout.board.width / width)
                )
        )
        window.invalidateShadow()
    }

    private func setWindowSize(
        _ size: NSSize,
        centeredIn visibleFrame: NSRect
    ) {
        guard let window else {
            return
        }
        let frame = NSRect(
            x: round(visibleFrame.midX - size.width / 2),
            y: round(visibleFrame.midY - size.height / 2),
            width: size.width,
            height: size.height
        )
        window.setFrame(frame, display: true)
    }

    private func preferredScreen() -> NSScreen? {
        window?.screen ?? NSScreen.main ?? NSScreen.screens.first
    }

    private func showAnnotationToolbar(
        animated: Bool = false,
        allowBoardReposition: Bool = true
    ) {
#if DEBUG
        toolbarPresentedForTesting = true
        toolbarRevealAnimatedForTesting = animated
#endif
        configureToolbar(
            contentView: annotationToolbar,
            size: annotationToolbar.preferredSize
        )
        if animated {
            toolbarWindow.alphaValue = 0
        } else if !toolbarWindow.ignoresMouseEvents {
            toolbarWindow.alphaValue = 1
        }
        showFloatingToolbar(
            allowBoardReposition: allowBoardReposition
        )
        guard animated else {
            return
        }
        let motion = CaptureTransitionPolicy.toolbarAnimation()
        annotationToolbar.layer?.add(
            motion,
            forKey: "trace.capture-toolbar"
        )
        NSAnimationContext.runAnimationGroup { context in
            context.duration =
                CaptureTransitionPolicy.toolbarRevealDuration
            context.timingFunction = CAMediaTimingFunction(
                name: .easeOut
            )
            toolbarWindow.animator().alphaValue = 1
        }
    }

    private func configureToolbar(
        contentView: NSView,
        size: NSSize
    ) {
        if toolbarWindow.contentView !== contentView {
            toolbarWindow.contentView = contentView
        }
        toolbarWindow.setContentSize(size)
        contentView.frame = NSRect(origin: .zero, size: size)
    }

    private func configureSetupPanel(
        preservingTopLeft: Bool
    ) {
        let topLeft = NSPoint(
            x: setupWindow.frame.minX,
            y: setupWindow.frame.maxY
        )
        let size = setupPanel.preferredSize
        setupWindow.setContentSize(size)
        setupPanel.frame = NSRect(origin: .zero, size: size)
        if preservingTopLeft {
            setupWindow.setFrameOrigin(
                NSPoint(
                    x: topLeft.x,
                    y: topLeft.y - size.height
                )
            )
        }
    }

    private func showSetupPanelIfNeeded(
        _ snapshot: TraceAppSnapshot
    ) {
        guard snapshot.setupVisible && !snapshot.calibrationActive else {
            hideSetupPanel()
            return
        }
        showSetupPanel()
    }

    private func showSetupPanel() {
        configureSetupPanel(preservingTopLeft: setupWindow.isVisible)
        if !setupWindow.isVisible {
            positionSetupPanel()
        }
#if DEBUG
        guard !suppressFloatingToolbarOrderingForTesting else {
            return
        }
#endif
        guard let window else {
            return
        }
        if setupWindow.parent !== window {
            window.addChildWindow(setupWindow, ordered: .above)
        }
        setupWindow.orderFront(nil)
    }

    private func hideSetupPanel() {
        if let parent = setupWindow.parent {
            parent.removeChildWindow(setupWindow)
        }
        setupWindow.orderOut(nil)
    }

    private func positionSetupPanel() {
        guard let window else {
            return
        }
        let boardFrame = window.frame
        let screenFrame = window.screen?.visibleFrame
            ?? NSScreen.main?.visibleFrame
            ?? boardFrame
        let size = setupWindow.frame.size
        let panelGap = Self.toolbarGap
        let rightX = boardFrame.maxX + panelGap
        let leftX = boardFrame.minX - panelGap - size.width
        let x: CGFloat
        if rightX + size.width <= screenFrame.maxX - Self.boardMargin {
            x = rightX
        } else if leftX >= screenFrame.minX + Self.boardMargin {
            x = leftX
        } else {
            x = min(
                screenFrame.maxX - size.width - Self.boardMargin,
                max(screenFrame.minX + Self.boardMargin, rightX)
            )
        }
        let idealY = boardFrame.maxY - size.height
        let y = min(
            screenFrame.maxY - size.height - Self.boardMargin,
            max(screenFrame.minY + Self.boardMargin, idealY)
        )
        setupWindow.setFrameOrigin(
            NSPoint(x: round(x), y: round(y))
        )
    }

    private func refreshAnnotationToolbarSize() {
        guard toolbarWindow.contentView === annotationToolbar,
              toolbarWindow.isVisible
        else {
            return
        }
        let size = annotationToolbar.preferredSize
        guard abs(toolbarWindow.frame.width - size.width) >= 0.5 else {
            return
        }
        let centerX = toolbarWindow.frame.midX
        let originY = toolbarWindow.frame.minY
        configureToolbar(
            contentView: annotationToolbar,
            size: size
        )
        toolbarWindow.setFrameOrigin(
            NSPoint(
                x: round(centerX - size.width / 2),
                y: originY
            )
        )
        scheduleAnnotationToolbarPosition()
    }

    private func showFloatingToolbar(
        allowBoardReposition: Bool = true
    ) {
        positionAnnotationToolbar(
            allowBoardReposition: allowBoardReposition
        )
#if DEBUG
        guard !suppressFloatingToolbarOrderingForTesting else {
            return
        }
#endif
        guard let window else {
            return
        }
        if toolbarWindow.parent !== window {
            window.addChildWindow(toolbarWindow, ordered: .above)
        }
        toolbarWindow.orderFront(nil)
    }

    private func finishBlankCanvasReveal(
        rendererAvailable: Bool
    ) {
        guard blankCanvasRevealPending else {
            return
        }
        blankCanvasRevealPending = false
        let animated =
            rendererAvailable
                && !NSWorkspace.shared
                    .accessibilityDisplayShouldReduceMotion
        drawingController.revealTldrawCanvas(
            animated: animated
        )
        showAnnotationToolbar(animated: animated)
    }

    private func showCapturelessToolbarIfReady() {
        guard !blankCanvasRevealPending else {
            return
        }
        showAnnotationToolbar()
    }

    private func hideAnnotationToolbar() {
        annotationToolbar.dismissBackgroundPicker()
        if let parent = toolbarWindow.parent {
            parent.removeChildWindow(toolbarWindow)
        }
        toolbarWindow.orderOut(nil)
    }

    private func scheduleAnnotationToolbarPosition(
        allowBoardReposition: Bool = false
    ) {
        guard toolbarWindow.isVisible else {
            return
        }
        toolbarBoardRepositionRequested =
            toolbarBoardRepositionRequested || allowBoardReposition
        guard !toolbarPositionScheduled else {
            return
        }
        toolbarPositionScheduled = true
        DispatchQueue.main.async { [weak self] in
            guard let self else {
                return
            }
            self.toolbarPositionScheduled = false
            guard self.toolbarWindow.isVisible else {
                self.toolbarBoardRepositionRequested = false
                return
            }
            let canRepositionBoard =
                self.toolbarBoardRepositionRequested
                    && self.window?.inLiveResize != true
            if canRepositionBoard {
                self.toolbarBoardRepositionRequested = false
            }
            self.positionAnnotationToolbar(
                allowBoardReposition: canRepositionBoard
            )
        }
    }

    private func positionAnnotationToolbar(
        allowBoardReposition: Bool = true
    ) {
        guard let window else {
            return
        }
#if DEBUG
        toolbarPositionCountForTesting += 1
#endif
        var boardFrame = window.frame
        let screenFrame = window.screen?.visibleFrame
            ?? NSScreen.main?.visibleFrame
            ?? boardFrame
        let toolbarSize = toolbarWindow.frame.size
        let maximumToolbarY = screenFrame.maxY
            - Self.boardMargin
            - toolbarSize.height
        let idealToolbarY = boardFrame.maxY + Self.toolbarGap
        if allowBoardReposition, idealToolbarY > maximumToolbarY {
            isPositioningToolbar = true
            let correctedY = max(
                screenFrame.minY + Self.boardMargin,
                maximumToolbarY
                    - Self.toolbarGap
                    - boardFrame.height
            )
            window.setFrameOrigin(
                NSPoint(x: boardFrame.minX, y: correctedY)
            )
            boardFrame = window.frame
            isPositioningToolbar = false
        }
        let idealX = boardFrame.midX - toolbarSize.width / 2
        let x = min(
            screenFrame.maxX
                - toolbarSize.width
                - Self.boardMargin,
            max(screenFrame.minX + Self.boardMargin, idealX)
        )
        toolbarWindow.setFrameOrigin(
            NSPoint(
                x: round(x),
                y: round(
                    min(
                        maximumToolbarY,
                        boardFrame.maxY + Self.toolbarGap
                    )
                )
            )
        )
    }
}

private final class TraceBoardWindow: NSWindow {
    var onPointerDown: (() -> Void)?

#if DEBUG
    private let sidecarInputProbeEnabled =
        ProcessInfo.processInfo.environment[
            "TRACE_SIDECAR_INPUT_PROBE"
        ] == "1"
#endif

    func setNativeResizingEnabled(_ enabled: Bool) {
        var nextStyle: NSWindow.StyleMask = [
            .titled,
            .fullSizeContentView,
        ]
        if enabled {
            nextStyle.insert(.resizable)
        }
        styleMask = nextStyle
        title = ""
        titleVisibility = .hidden
        titlebarAppearsTransparent = true
        titlebarSeparatorStyle = .none
        for buttonType in [
            NSWindow.ButtonType.closeButton,
            .miniaturizeButton,
            .zoomButton,
        ] {
            standardWindowButton(buttonType)?.isHidden = true
        }
    }

    override var canBecomeKey: Bool {
        true
    }

    override var canBecomeMain: Bool {
        true
    }

    override func sendEvent(_ event: NSEvent) {
        if event.type == .leftMouseDown
            || event.type == .rightMouseDown
            || event.type == .otherMouseDown
        {
            onPointerDown?()
        }
#if DEBUG
        if sidecarInputProbeEnabled {
            logSidecarInput(event)
        }
#endif
        super.sendEvent(event)
    }

#if DEBUG
    private func logSidecarInput(_ event: NSEvent) {
        let pointerEvents: Set<NSEvent.EventType> = [
            .leftMouseDown,
            .leftMouseDragged,
            .leftMouseUp,
            .rightMouseDown,
            .rightMouseDragged,
            .rightMouseUp,
            .otherMouseDown,
            .otherMouseDragged,
            .otherMouseUp,
            .mouseMoved,
            .tabletPoint,
            .tabletProximity,
        ]
        guard pointerEvents.contains(event.type) else {
            return
        }
        var fields = [
            "type=\(event.type.rawValue)",
            "subtype=\(event.subtype.rawValue)",
            "x=\(event.locationInWindow.x)",
            "y=\(event.locationInWindow.y)",
        ]
        if event.type != .tabletProximity {
            fields.append("pressure=\(event.pressure)")
        }
        if event.type == .tabletPoint
            || event.subtype == .tabletPoint
        {
            let tilt = event.tilt
            fields.append(contentsOf: [
                "tiltX=\(tilt.x)",
                "tiltY=\(tilt.y)",
                "rotation=\(event.rotation)",
                "tangentialPressure=\(event.tangentialPressure)",
                "pointingDeviceType=\(event.pointingDeviceType.rawValue)",
            ])
        }
        NSLog(
            "Trace Sidecar input probe AppKit: %@",
            fields.joined(separator: " ")
        )
    }

    func notifyPointerDownForTesting() {
        onPointerDown?()
    }

    var chromeForTesting: (
        titled: Bool,
        resizable: Bool,
        fullSizeContent: Bool,
        titleHidden: Bool,
        titlebarTransparent: Bool,
        titlebarSeparatorHidden: Bool,
        visibleStandardButtonCount: Int,
        frameSize: NSSize,
        contentSize: NSSize,
        nativeFrameOwnsEdges: Bool,
        topContentInteractive: Bool
    ) {
        layoutIfNeeded()
        let size = contentView?.bounds.size ?? .zero
        let edgeInset: CGFloat = 1
        let edgePoints = [
            NSPoint(x: edgeInset, y: size.height / 2),
            NSPoint(x: size.width - edgeInset, y: size.height / 2),
            NSPoint(x: size.width / 2, y: edgeInset),
            NSPoint(x: size.width / 2, y: size.height - edgeInset),
        ]
        return (
            titled: styleMask.contains(.titled),
            resizable: styleMask.contains(.resizable),
            fullSizeContent: styleMask.contains(.fullSizeContentView),
            titleHidden: titleVisibility == .hidden,
            titlebarTransparent: titlebarAppearsTransparent,
            titlebarSeparatorHidden: titlebarSeparatorStyle == .none,
            visibleStandardButtonCount: [
                NSWindow.ButtonType.closeButton,
                .miniaturizeButton,
                .zoomButton,
            ].compactMap(standardWindowButton)
                .filter { !$0.isHidden }
                .count,
            frameSize: frame.size,
            contentSize: size,
            nativeFrameOwnsEdges:
                edgePoints.allSatisfy {
                    !contentOwnsHit(at: $0)
                },
            topContentInteractive: contentOwnsHit(
                at: NSPoint(
                    x: size.width / 2,
                    y: max(0, size.height - 16)
                )
            )
        )
    }

    private func contentOwnsHit(at point: NSPoint) -> Bool {
        guard let contentView,
              let frameView = contentView.superview,
              let hit = frameView.hitTest(
                  contentView.convert(point, to: frameView)
              )
        else {
            return false
        }
        var candidate: NSView? = hit
        while let view = candidate {
            if view === contentView {
                return true
            }
            candidate = view.superview
        }
        return false
    }

    func performNativeResizeForTesting() -> (
        before: NSSize,
        after: NSSize
    ) {
        alphaValue = 0
        orderBack(nil)
        layoutIfNeeded()
        let before = contentView?.bounds.size ?? .zero
        guard before.width > 2, before.height > 2 else {
            return (before, before)
        }
        let timestamp = ProcessInfo.processInfo.systemUptime
        let start = NSPoint(
            x: before.width - 1,
            y: before.height / 2
        )
        func event(
            type: NSEvent.EventType,
            point: NSPoint,
            number: Int
        ) -> NSEvent {
            NSEvent.mouseEvent(
                with: type,
                location: point,
                modifierFlags: [],
                timestamp: timestamp + Double(number) * 0.01,
                windowNumber: windowNumber,
                context: nil,
                eventNumber: number,
                clickCount: 1,
                pressure: type == .leftMouseUp ? 0 : 1
            )!
        }
        let finalPoint = NSPoint(
            x: start.x + 24,
            y: start.y
        )
        NSApp.postEvent(
            event(
                type: .leftMouseUp,
                point: finalPoint,
                number: 14
            ),
            atStart: true
        )
        for number in stride(from: 13, through: 2, by: -1) {
            NSApp.postEvent(
                event(
                    type: .leftMouseDragged,
                    point: NSPoint(
                        x: start.x + CGFloat(number * 2),
                        y: start.y
                    ),
                    number: number
                ),
                atStart: true
            )
        }
        sendEvent(
            event(
                type: .leftMouseDown,
                point: start,
                number: 1
            )
        )
        return (
            before,
            contentView?.bounds.size ?? .zero
        )
    }

#endif
}

private final class TraceToolbarPanel: NSPanel {
    var onPointerDown: ((NSPoint) -> Void)?

    override var canBecomeKey: Bool {
        true
    }

    override var canBecomeMain: Bool {
        false
    }

    override func sendEvent(_ event: NSEvent) {
        if event.type == .leftMouseDown
            || event.type == .rightMouseDown
            || event.type == .otherMouseDown
        {
            onPointerDown?(event.locationInWindow)
        }
        super.sendEvent(event)
    }

#if DEBUG
    func notifyPointerDownForTesting(at point: NSPoint) {
        onPointerDown?(point)
    }
#endif
}

final class TraceProjectionWindowController:
    NSWindowController,
    NSWindowDelegate
{
    private let root = NSView()
    private let drawingController = DrawingBoardViewController()
    private var currentDrawing: TraceDrawingSession?

    init() {
        let window = TraceProjectionWindow(
            contentRect: .zero,
            styleMask: .borderless,
            backing: .buffered,
            defer: false
        )
        window.isOpaque = true
        window.backgroundColor = .black
        window.hasShadow = false
        window.ignoresMouseEvents = true
        window.level = .statusBar
        window.collectionBehavior = [
            .canJoinAllSpaces,
            .fullScreenAuxiliary,
            .stationary,
        ]
        super.init(window: window)
        window.delegate = self

        root.wantsLayer = true
        root.layer?.backgroundColor = NSColor.black.cgColor
        drawingController.view.translatesAutoresizingMaskIntoConstraints = true
        root.addSubview(drawingController.view)
        window.contentView = root
    }

    required init?(coder: NSCoder) {
        nil
    }

    func present(
        _ document: TraceDrawingSession,
        toolState: TraceToolState,
        on screen: NSScreen
    ) {
        currentDrawing = document
        drawingController.view.isHidden = false
        drawingController.setDocument(document, toolState: toolState)
        window?.setFrame(screen.frame, display: true)
        layoutDocument()
        window?.orderFrontRegardless()
    }

    func presentBlack(on screen: NSScreen) {
        configureBlackFrame(screen.frame, display: true)
        window?.orderFrontRegardless()
    }

    func hideProjection() {
        drawingController.setHover(nil)
        window?.orderOut(nil)
        currentDrawing = nil
    }

    func apply(_ update: TraceAnnotationUpdate) {
        drawingController.apply(update)
    }

    func updateHover(_ update: TraceHoverUpdate?) {
        drawingController.setHover(update)
    }

    func updateToolState(_ state: TraceToolState) {
        drawingController.setToolState(state)
    }

    func refreshBackground(_ color: TraceRGBAColor) {
        drawingController.setBackgroundColor(color)
    }

    func refreshGeometry() {
        drawingController.refreshDocumentGeometry()
        layoutDocument()
    }

    func refreshDrawingHistory() {
        drawingController.refreshDrawingHistory()
    }

    func refreshTldrawSnapshot() {
        drawingController.refreshTldrawSnapshot()
    }

    func refreshTranscriptAnnotations() {
        drawingController.refreshTranscriptAnnotations()
    }

    func updateTranscriptAnnotationScale(
        _ scale: TraceTranscriptAnnotationScale
    ) {
        drawingController.updateTranscriptAnnotationScale(scale)
    }

    func windowDidResize(_ notification: Notification) {
        layoutDocument()
    }

#if DEBUG
    func prepareForPreview(
        _ document: TraceDrawingSession,
        toolState: TraceToolState,
        outputSize: NSSize
    ) -> NSRect {
        currentDrawing = document
        drawingController.view.isHidden = false
        drawingController.setDocument(document, toolState: toolState)
        window?.setFrame(
            NSRect(origin: .zero, size: outputSize),
            display: false
        )
        layoutDocument()
        return drawingController.view.frame
    }

    func prepareBlackForPreview(
        outputSize: NSSize
    ) -> (contentHidden: Bool, backgroundColor: NSColor) {
        configureBlackFrame(
            NSRect(origin: .zero, size: outputSize),
            display: false
        )
        return (
            contentHidden: drawingController.view.isHidden,
            backgroundColor:
                root.layer?.backgroundColor.flatMap(
                    NSColor.init(cgColor:)
                ) ?? .clear
        )
    }

    func renderedContentPreview() -> NSBitmapImageRep? {
        drawingController.renderedSurfaceForPreview()
    }

    var letterboxColorForPreview: NSColor {
        root.layer?.backgroundColor.flatMap(NSColor.init(cgColor:))
            ?? .clear
    }
#endif

    private func configureBlackFrame(
        _ frame: NSRect,
        display: Bool
    ) {
        currentDrawing = nil
        drawingController.setHover(nil)
        drawingController.view.isHidden = true
        window?.setFrame(frame, display: display)
        root.frame = window?.contentView?.bounds ?? .zero
    }

    private func layoutDocument() {
        guard let document = currentDrawing else {
            drawingController.view.frame = .zero
            return
        }
        root.frame = window?.contentView?.bounds ?? .zero
        let viewport = document.manifest.viewport
            ?? TracePageViewport.full
        let fullSource = document.manifest.sourceWindowBounds.map {
            TraceSize(width: $0.width, height: $0.height)
        } ?? TraceSize(
            width: document.screenshot.size.width,
            height: document.screenshot.size.height
        )
        let visibleSource = document.manifest.pageKind == .blank
            ? fullSource
            : TraceSize(
                width: fullSource.width * viewport.width,
                height: fullSource.height * viewport.height
            )
        let fitted = TraceProjectionPolicy.contentFrame(
            source: visibleSource,
            output: TraceSize(
                width: root.bounds.width,
                height: root.bounds.height
            )
        )
        drawingController.view.frame = NSRect(
            x: fitted.x,
            y: fitted.y,
            width: fitted.width,
            height: fitted.height
        )
        drawingController.view.layoutSubtreeIfNeeded()
        let isCropped = viewport != TracePageViewport.full
        drawingController.setCornerRadius(
            document.manifest.pageKind != .blank && isCropped
                ? 0
                : CGFloat(
                    (document.manifest.sourceWindowCornerRadius ?? 0)
                        * (fitted.width / max(1, visibleSource.width))
                )
        )
    }
}

private final class TraceProjectionWindow: NSWindow {
    override var canBecomeKey: Bool {
        true
    }

    override var canBecomeMain: Bool {
        true
    }
}

private final class DrawingBoardViewController: NSViewController {
    var onDocumentEdited: ((
        [TraceDrawingStroke],
        [TraceDrawingStroke]
    ) -> Void)?
    var onTldrawSnapshotChange: ((
        String,
        [TraceTimedCanvasShape]
    ) -> Void)?
    var onTldrawUserEdit: ((Int) -> Void)?
    var onTldrawToolChange: ((TraceToolState) -> Void)?
    var onTldrawTemporaryToolChange: ((TraceCanvasTool?) -> Void)?
    var onTldrawPresentationReady: ((Bool) -> Void)?
    var onCancelCalibration: (() -> Void)?

    var imageRectOnScreen: NSRect? {
        guard let window = root.window else {
            return nil
        }
        return window.convertToScreen(
            root.convert(root.bounds, to: nil)
        )
    }

    private let surface = ScreenshotGridSurfaceView()
    private let completedInk = CompletedInkView()
    private let canvas = AnnotationCanvasView()
    private let nativeProbeMode: Bool = {
#if DEBUG
        ProcessInfo.processInfo.environment[
            "TRACE_RETAINED_INK_PROBE"
        ] == "1"
            || ProcessInfo.processInfo.environment[
                "TRACE_HARDWARE_FREE_PROBE"
            ] == "1"
#else
        false
#endif
    }()
    private let productUsesTldraw = TraceProductCanvasPolicy.usesTldraw(
        environment: ProcessInfo.processInfo.environment,
        debugBuild: _isDebugAssertConfiguration()
    )
    private var tldrawCanvas: TldrawProductCanvasView?
    private let hoverPointer = TraceHoverPointerView()
    private let setupOverlay = SetupOverlayView()
    private let root = TraceBoardRootView()
    private var document: TraceDrawingSession?
    private var toolState = TraceToolState()
    private var tldrawReady = false

    var usesTldrawProductCanvas: Bool {
        productUsesTldraw && !nativeProbeMode
    }

    var canUndoTldraw: Bool {
        tldrawReady && (tldrawCanvas?.canUndo ?? false)
    }

    var canRedoTldraw: Bool {
        tldrawReady && (tldrawCanvas?.canRedo ?? false)
    }

    override func loadView() {
        root.translatesAutoresizingMaskIntoConstraints = false

        surface.translatesAutoresizingMaskIntoConstraints = false
        hoverPointer.translatesAutoresizingMaskIntoConstraints = false
        root.addSubview(surface)
        if nativeProbeMode {
            completedInk.translatesAutoresizingMaskIntoConstraints = false
            canvas.translatesAutoresizingMaskIntoConstraints = false
            completedInk.attach(to: canvas)
            canvas.onDocumentEdited = { [weak self] before, after in
                self?.completedInk.invalidateInk()
                self?.onDocumentEdited?(before, after)
            }
            canvas.onSelectionModeChanged = { [weak self] isSelecting in
                self?.completedInk.isHidden = isSelecting
                if !isSelecting {
                    self?.completedInk.invalidateInk()
                }
            }
            root.addSubview(completedInk)
            root.addSubview(canvas)
        }
        root.addSubview(hoverPointer)
        setupOverlay.translatesAutoresizingMaskIntoConstraints = false
        setupOverlay.onCancelCalibration = { [weak self] in
            self?.onCancelCalibration?()
        }
        root.addSubview(setupOverlay)

        var constraints = [
            surface.topAnchor.constraint(equalTo: root.topAnchor),
            surface.leadingAnchor.constraint(equalTo: root.leadingAnchor),
            surface.trailingAnchor.constraint(equalTo: root.trailingAnchor),
            surface.bottomAnchor.constraint(equalTo: root.bottomAnchor),
            hoverPointer.topAnchor.constraint(equalTo: root.topAnchor),
            hoverPointer.leadingAnchor.constraint(equalTo: root.leadingAnchor),
            hoverPointer.trailingAnchor.constraint(equalTo: root.trailingAnchor),
            hoverPointer.bottomAnchor.constraint(equalTo: root.bottomAnchor),
            setupOverlay.topAnchor.constraint(equalTo: root.topAnchor),
            setupOverlay.leadingAnchor.constraint(equalTo: root.leadingAnchor),
            setupOverlay.trailingAnchor.constraint(equalTo: root.trailingAnchor),
            setupOverlay.bottomAnchor.constraint(equalTo: root.bottomAnchor),
        ]
        if nativeProbeMode {
            constraints += [
                completedInk.topAnchor.constraint(equalTo: root.topAnchor),
                completedInk.leadingAnchor.constraint(equalTo: root.leadingAnchor),
                completedInk.trailingAnchor.constraint(equalTo: root.trailingAnchor),
                completedInk.bottomAnchor.constraint(equalTo: root.bottomAnchor),
                canvas.topAnchor.constraint(equalTo: root.topAnchor),
                canvas.leadingAnchor.constraint(equalTo: root.leadingAnchor),
                canvas.trailingAnchor.constraint(equalTo: root.trailingAnchor),
                canvas.bottomAnchor.constraint(equalTo: root.bottomAnchor),
            ]
        }
        NSLayoutConstraint.activate(constraints)
        view = root
    }

    func updateSetup(
        _ snapshot: TraceAppSnapshot,
        shortcuts: TraceGlobalShortcutsSnapshot =
            TraceGlobalShortcutsSnapshot()
    ) {
        _ = view
        setupOverlay.update(snapshot, shortcuts: shortcuts)
    }

#if DEBUG
    func cancelCalibrationForTesting() {
        setupOverlay.cancelCalibrationForTesting()
    }

    var calibrationStateForTesting: (
        visible: Bool,
        paintsReplacementBackground: Bool,
        usesDarkAppearance: Bool,
        backgroundBrightness: CGFloat,
        backgroundAlpha: CGFloat
    ) {
        setupOverlay.calibrationStateForTesting
    }
#endif

    func setDocument(
        _ document: TraceDrawingSession,
        toolState: TraceToolState
    ) {
        _ = view
        self.document = document
        self.toolState = toolState
        root.setBackgroundColor(
            NSColor(
                document.manifest.backgroundColor
                    ?? TraceRGBAColor(red: 1, green: 1, blue: 1)
            )
        )
        root.setCornerRadius(
            CGFloat(document.manifest.sourceWindowCornerRadius ?? 0)
        )
        surface.setDocument(document)
        hoverPointer.setDocument(document)
        if nativeProbeMode {
            canvas.setDocument(document)
            completedInk.isHidden = false
            completedInk.invalidateInk()
            surface.setDisplaysScreenshot(true)
        } else {
            completedInk.isHidden = true
            canvas.isHidden = true
            let tldrawCanvas = ensureTldrawCanvas()
            prepareTldrawLoadingState()
            tldrawCanvas?.setDocument(
                document,
                toolState: toolState
            )
        }
        surface.setGrid(
            style: toolState.gridStyle,
            spacingPoints: toolState.gridSpacingPoints
        )
    }

    func setGrid(
        style: TraceGridStyle,
        spacingPoints: Int
    ) {
        surface.setGrid(
            style: style,
            spacingPoints: spacingPoints
        )
        toolState.gridStyle = style
        toolState.gridSpacingPoints = spacingPoints
    }

    func setBackgroundColor(_ color: TraceRGBAColor) {
        root.setBackgroundColor(NSColor(color))
        surface.setBackgroundColor(color)
        tldrawCanvas?.setBackgroundColor(color)
        hoverPointer.refreshDocument()
        if nativeProbeMode {
            canvas.refreshDocumentGeometry()
            completedInk.invalidateInk()
        }
    }

    func refreshDocumentGeometry() {
        surface.refreshDocumentGeometry()
        hoverPointer.refreshDocument()
        if nativeProbeMode {
            canvas.refreshDocumentGeometry()
            completedInk.invalidateInk()
        }
        if let document {
            tldrawCanvas?.setDocument(document, toolState: toolState)
        }
    }

    func refreshDrawingHistory() {
        if nativeProbeMode {
            canvas.refreshAfterHistoryChange()
            completedInk.isHidden = false
            completedInk.invalidateInk()
        }
        if let document {
            tldrawCanvas?.syncStrokes(document)
        }
    }

    func refreshTldrawSnapshot() {
        if let document {
            tldrawCanvas?.setDocument(document, toolState: toolState)
        }
    }

    func refreshTranscriptAnnotations() {
        if nativeProbeMode {
            canvas.refreshTranscriptAnnotations()
            completedInk.invalidateInk()
        }
        if let document {
            tldrawCanvas?.syncStrokes(document)
        }
    }

    func updateTranscriptAnnotationScale(
        _ scale: TraceTranscriptAnnotationScale
    ) {
        if nativeProbeMode {
            guard canvas.setTranscriptAnnotationScale(scale) else {
                return
            }
            completedInk.invalidateInk()
        }
        tldrawCanvas?.setTranscriptAnnotationScale(
            scale,
            document: document
        )
    }

    func setCornerRadius(_ radius: CGFloat) {
        root.setCornerRadius(radius)
    }

    func setHover(_ update: TraceHoverUpdate?) {
        hoverPointer.setHover(update)
    }

#if DEBUG
    var blankCanvasLoadingForPreview: (
        tldrawReady: Bool,
        tldrawAlpha: CGFloat,
        surfaceDisplaysScreenshot: Bool,
        rootBackgroundColor: NSColor?
    ) {
        (
            tldrawReady: tldrawReady,
            tldrawAlpha: tldrawCanvas?.alphaValue ?? 0,
            surfaceDisplaysScreenshot:
                surface.displaysScreenshotForTesting,
            rootBackgroundColor:
                root.layer?.backgroundColor.flatMap(
                    NSColor.init(cgColor:)
                )
        )
    }

    var productRendererStateForTesting: (
        nativeLayersAttached: Bool,
        tldrawAttached: Bool,
        surfaceDisplaysScreenshot: Bool,
        tldrawErrorVisible: Bool
    ) {
        (
            nativeLayersAttached:
                completedInk.superview != nil || canvas.superview != nil,
            tldrawAttached: tldrawCanvas?.superview != nil,
            surfaceDisplaysScreenshot:
                surface.displaysScreenshotForTesting,
            tldrawErrorVisible:
                tldrawCanvas?.errorPresentationForTesting.visible
                    == true
        )
    }

    func productCanvasStateForTesting() async -> [String: Any]? {
        await tldrawCanvas?.stateForTesting()
    }

    func showProductRendererErrorForTesting(_ detail: String) {
        tldrawCanvas?.showErrorForTesting(detail)
    }

    func nativeCompositeImageForPreview() -> NSImage? {
        canvas.compositeImage()
    }

    func renderedSurfaceForPreview() -> NSBitmapImageRep? {
        surface.layoutSubtreeIfNeeded()
        guard let representation = surface.bitmapImageRepForCachingDisplay(
            in: surface.bounds
        ) else {
            return nil
        }
        surface.cacheDisplay(in: surface.bounds, to: representation)
        return representation
    }

    func selectStrokesForPreview(_ strokeIDs: Set<UInt64>) {
        canvas.selectStrokesForPreview(strokeIDs)
    }

    var completedInkRenderCountForPreview: Int {
        completedInk.renderCount
    }

    var activeInkRenderCountForPreview: Int {
        canvas.renderCount
    }

    var completedInkHiddenForPreview: Bool {
        completedInk.isHidden
    }

    var completedInkViewForPreview: NSView {
        completedInk
    }

    var activeInkViewForPreview: NSView {
        canvas
    }

    var hoverStateForPreview: (
        point: TracePoint?,
        diameter: Double,
        opacity: Double,
        renderCount: Int
    ) {
        (
            point: hoverPointer.displayedNormalizedPointForTesting,
            diameter: hoverPointer.diameterForTesting,
            opacity: hoverPointer.alphaValue,
            renderCount: hoverPointer.renderCount
        )
    }

    var hoverViewForPreview: NSView {
        hoverPointer
    }

    func resetInkRenderCountsForPreview() {
        completedInk.resetRenderCountForTesting()
        canvas.resetRenderCountForTesting()
    }

    func displayInkLayersForPreview() {
        view.layoutSubtreeIfNeeded()
        completedInk.displayIfNeeded()
        canvas.displayIfNeeded()
    }

    func displayHoverForPreview() {
        view.layoutSubtreeIfNeeded()
        hoverPointer.displayIfNeeded()
    }

    var submittedGridFrameCountForPreview: Int {
        surface.submittedMetalFrameCountForTesting
    }

    var submittedGridStateForPreview: (
        style: TraceGridStyle,
        spacingPoints: Int
    )? {
        surface.submittedGridStateForTesting
    }

    func resetSubmittedGridFrameCountForPreview() {
        surface.resetSubmittedMetalFrameCountForTesting()
    }

    func flushScheduledGridDrawForPreview() {
        surface.flushScheduledMetalDrawForTesting()
    }

    func invalidateInkLayersForPreview() {
        completedInk.needsDisplay = true
        canvas.needsDisplay = true
    }

    func moveSelectedStrokesForPreview(delta: TracePoint) {
        canvas.moveSelectedStrokesForPreview(delta: delta)
    }

    func deleteSelectedStrokesForPreview() {
        canvas.deleteSelectedStrokesForPreview()
    }
#endif

    func apply(_ update: TraceAnnotationUpdate) {
        if nativeProbeMode {
            canvas.apply(update)
            if update.isFinal {
                completedInk.invalidateInk()
            }
        } else {
            tldrawCanvas?.apply(update)
        }
    }

    func compositeImage(
        completion: @escaping (NSImage?) -> Void
    ) {
        if nativeProbeMode {
            completion(canvas.compositeImage())
            return
        }
        guard tldrawReady else {
            completion(nil)
            return
        }
        tldrawCanvas?.exportImage(
            pixelRatio: view.window?.backingScaleFactor ?? 2,
            completion: completion
        )
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
        guard document != nil,
              let tldrawCanvas = ensureTldrawCanvas(),
              tldrawCanvas.unavailableReason == nil
        else {
            return false
        }
        return tldrawCanvas.insertImages(images)
    }

    @discardableResult
    func undoTldrawIfAvailable() -> Bool {
        guard canUndoTldraw else {
            return false
        }
        tldrawCanvas?.undo()
        return true
    }

    @discardableResult
    func redoTldrawIfAvailable() -> Bool {
        guard canRedoTldraw else {
            return false
        }
        tldrawCanvas?.redo()
        return true
    }

    func flushTldrawSnapshot(completion: @escaping () -> Void) {
        guard tldrawReady, let tldrawCanvas else {
            completion()
            return
        }
        tldrawCanvas.flushSnapshot(completion: completion)
    }

    func setToolState(_ state: TraceToolState) {
        toolState = state
        setGrid(
            style: state.gridStyle,
            spacingPoints: state.gridSpacingPoints
        )
        tldrawCanvas?.setToolState(state)
    }

    func focusTldrawCanvas() {
        guard tldrawReady else {
            return
        }
        tldrawCanvas?.focusCanvas()
    }

    func revealTldrawCanvas(animated: Bool) {
        guard tldrawReady, let tldrawCanvas else {
            return
        }
        surface.setDisplaysScreenshot(false)
        guard animated else {
            tldrawCanvas.alphaValue = 1
            focusTldrawCanvasIfInteractive()
            return
        }
        tldrawCanvas.alphaValue = 0
        NSAnimationContext.runAnimationGroup { context in
            context.duration =
                BlankCanvasLoadingPolicy.rendererRevealDuration
            context.timingFunction = CAMediaTimingFunction(
                name: .easeOut
            )
            tldrawCanvas.animator().alphaValue = 1
        } completionHandler: { [weak self] in
            self?.focusTldrawCanvasIfInteractive()
        }
    }

    private func prepareTldrawLoadingState() {
        tldrawReady = false
        let isBlank = document?.manifest.pageKind == .blank
        tldrawCanvas?.isHidden = false
        tldrawCanvas?.alphaValue = isBlank ? 0 : 1
        surface.setDisplaysScreenshot(!isBlank)
        surface.isHidden = false
        completedInk.isHidden = true
        canvas.isHidden = true
    }

    private func setTldrawReady(_ ready: Bool) {
        tldrawReady = ready
        tldrawCanvas?.isHidden = false
        let isBlank = document?.manifest.pageKind == .blank
        if ready, !isBlank {
            tldrawCanvas?.alphaValue = 1
        }
        surface.setDisplaysScreenshot(!ready && !isBlank)
        surface.isHidden = false
        completedInk.isHidden = true
        canvas.isHidden = true
        guard ready else {
            return
        }
        if isBlank, onTldrawPresentationReady == nil {
            revealTldrawCanvas(animated: false)
        } else if !isBlank {
            focusTldrawCanvasIfInteractive()
        }
        onTldrawPresentationReady?(true)
    }

    private func setTldrawUnavailable() {
        tldrawReady = false
        tldrawCanvas?.isHidden = false
        tldrawCanvas?.alphaValue = 1
        surface.setDisplaysScreenshot(false)
        surface.isHidden = false
        completedInk.isHidden = true
        canvas.isHidden = true
        onTldrawPresentationReady?(false)
    }

    private func focusTldrawCanvasIfInteractive() {
        guard view.window?.ignoresMouseEvents == false else {
            return
        }
        tldrawCanvas?.focusCanvas()
    }

    private func ensureTldrawCanvas() -> TldrawProductCanvasView? {
        guard !nativeProbeMode else {
            return nil
        }
        precondition(
            productUsesTldraw,
            "Trace requires the tldraw product canvas."
        )
        if let tldrawCanvas {
            return tldrawCanvas
        }
        let canvas = TldrawProductCanvasView()
        canvas.translatesAutoresizingMaskIntoConstraints = false
        canvas.isHidden = false
        canvas.onDocumentReady = { [weak self] in
            self?.setTldrawReady(true)
        }
        canvas.onUnavailable = { [weak self] in
            self?.setTldrawUnavailable()
        }
        canvas.onSnapshotChange = {
            [weak self] snapshot, timedShapes in
            self?.onTldrawSnapshotChange?(snapshot, timedShapes)
        }
        canvas.onUserEdit = { [weak self] count in
            self?.onTldrawUserEdit?(count)
        }
        canvas.onToolChange = { [weak self] tool in
            guard let self else {
                return
            }
            var state = toolState
            state.canvasTool = tool
            if tool == .pen || tool == .rectangle {
                state.brush = .pen
            } else if tool == .highlighter {
                state.brush = .highlighter
            }
            toolState = state
            onTldrawToolChange?(state)
        }
        canvas.onTemporaryToolChange = { [weak self] tool in
            self?.onTldrawTemporaryToolChange?(tool)
        }
        root.addSubview(
            canvas,
            positioned: .below,
            relativeTo: surface
        )
        NSLayoutConstraint.activate([
            canvas.topAnchor.constraint(equalTo: root.topAnchor),
            canvas.leadingAnchor.constraint(equalTo: root.leadingAnchor),
            canvas.trailingAnchor.constraint(equalTo: root.trailingAnchor),
            canvas.bottomAnchor.constraint(equalTo: root.bottomAnchor),
        ])
        tldrawCanvas = canvas
        if canvas.unavailableReason != nil {
            setTldrawUnavailable()
        }
        return canvas
    }
}

private func configureFloatingToolbarAppearance(
    _ toolbar: NSVisualEffectView
) {
    toolbar.material = .hudWindow
    toolbar.blendingMode = .withinWindow
    toolbar.state = .active
    toolbar.appearance = NSAppearance(named: .darkAqua)
    toolbar.wantsLayer = true
    toolbar.layer?.cornerRadius = 14
    toolbar.layer?.cornerCurve = .continuous
    toolbar.layer?.masksToBounds = true
    toolbar.layer?.borderWidth = 0.5
    toolbar.layer?.borderColor = NSColor.white
        .withAlphaComponent(0.22).cgColor
}

private class DraggableToolbarView: NSVisualEffectView {
    override func hitTest(_ point: NSPoint) -> NSView? {
        guard let hit = super.hitTest(point) else {
            return nil
        }
        var candidate: NSView? = hit
        while let view = candidate, view !== self {
            if isInteractiveControl(view) {
                return hit
            }
            candidate = view.superview
        }
        return self
    }

    override func mouseDown(with event: NSEvent) {
        window?.parent?.performDrag(with: event)
    }

    private func isInteractiveControl(_ view: NSView) -> Bool {
        guard let control = view as? NSControl, control.isEnabled else {
            return false
        }
        if let textField = control as? NSTextField {
            return textField.isEditable || textField.isSelectable
        }
        return control.action != nil
    }
}

private final class ToolbarActionHoverView: NSView {
    fileprivate static let hoverColor =
        NSColor.white.withAlphaComponent(0.10)
    private var controls: [NSControl] = []
    private var trackingArea: NSTrackingArea?
    private var isHovered = false

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        wantsLayer = true
        layer?.cornerRadius = 7
        layer?.cornerCurve = .continuous
    }

    required init?(coder: NSCoder) {
        nil
    }

    func setContent(
        _ content: NSView,
        controls: [NSControl]
    ) {
        self.controls = controls
        content.translatesAutoresizingMaskIntoConstraints = false
        addSubview(content)
        NSLayoutConstraint.activate([
            content.topAnchor.constraint(
                equalTo: topAnchor,
                constant: 2
            ),
            content.leadingAnchor.constraint(
                equalTo: leadingAnchor,
                constant: 2
            ),
            content.trailingAnchor.constraint(
                equalTo: trailingAnchor,
                constant: -2
            ),
            content.bottomAnchor.constraint(
                equalTo: bottomAnchor,
                constant: -2
            ),
        ])
        invalidateIntrinsicContentSize()
    }

    override var intrinsicContentSize: NSSize {
        guard let content = subviews.first else {
            return NSSize(width: 4, height: 4)
        }
        let size = content.fittingSize
        return NSSize(
            width: size.width + 4,
            height: size.height + 4
        )
    }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        if let trackingArea {
            removeTrackingArea(trackingArea)
        }
        let trackingArea = NSTrackingArea(
            rect: .zero,
            options: [
                .mouseEnteredAndExited,
                .activeAlways,
                .inVisibleRect,
            ],
            owner: self,
            userInfo: nil
        )
        addTrackingArea(trackingArea)
        self.trackingArea = trackingArea
    }

    override func mouseEntered(with event: NSEvent) {
        isHovered = true
        refreshHoverAppearance()
    }

    override func mouseExited(with event: NSEvent) {
        isHovered = false
        refreshHoverAppearance()
    }

    func refreshHoverAppearance() {
        let interactive = controls.contains(where: \.isEnabled)
        layer?.backgroundColor = (
            isHovered && interactive
                ? Self.hoverColor
                : NSColor.clear
        ).cgColor
    }

#if DEBUG
    func setHoveredForTesting(_ hovered: Bool) {
        isHovered = hovered
        refreshHoverAppearance()
    }

    var hoverBackgroundAlphaForTesting: CGFloat {
        layer?.backgroundColor.flatMap(NSColor.init(cgColor:))?
            .alphaComponent ?? 0
    }

    var hoverCornerRadiusForTesting: CGFloat {
        layer?.cornerRadius ?? 0
    }
#endif
}

private final class FloatingAnnotationToolbar:
    DraggableToolbarView,
    NSTextFieldDelegate
{
    private static let preferredHeight: CGFloat = 48
    private static let horizontalPadding: CGFloat = 12
    private static let separatorSpacing: CGFloat = 12
    private static let gridAccessoryGap: CGFloat = 6
    private static let gridAccessoryWidth: CGFloat = 32
    private static let gridSelectorWidth: CGFloat = 42
    private static let toolbarSymbolPointSize: CGFloat = 16
    private static let drawingToolSymbolPointSize: CGFloat = 18
    private static let gridSymbolPointSize: CGFloat = 14
    private static let chevronSymbolPointSize: CGFloat = 9
    private static let recordingAccentColor =
        NSColor.systemRed.withAlphaComponent(0.78)

    var onToolChange: ((TraceToolState) -> Void)?
    var onCopy: ((TraceCopyContent) -> Void)?
    var onClose: (() -> Void)?
    var onToggleVoiceRecording: (() -> Void)?
    var onBackgroundColorChange: ((TraceRGBAColor) -> Void)?
    var onPreferredSizeChange: (() -> Void)?

    private let brushControl = NSSegmentedControl(
        labels: ["", "", "", ""],
        trackingMode: .selectOne,
        target: nil,
        action: nil
    )
    private let brushActionHover = ToolbarActionHoverView()
    private let gridControl = NSPopUpButton(
        frame: .zero,
        pullsDown: false
    )
    private let gridSpacingField: GridSpacingTextField = {
        let field = GridSpacingTextField(string: "8")
        field.cell = GridSpacingTextFieldCell(textCell: field.stringValue)
        return field
    }()
    private let gridSpacingGroup = NSStackView()
    private let widthSlider = NSSlider(
        value: TraceStrokeWidthPolicy.defaultValue,
        minValue: TraceStrokeWidthPolicy.minimum,
        maxValue: TraceStrokeWidthPolicy.maximum,
        target: nil,
        action: nil
    )
    private let widthLabel = NSTextField(labelWithString: "5.2")
    private let backgroundColorWell = PageBackgroundColorWell()
    private let backgroundSeparator = NSBox()
    private let toolSeparator = NSBox()
    private let voiceSeparator = NSBox()
    private let recordingSeparator = NSBox()
    private let actionSeparator = NSBox()
    private let swatchStack = NSStackView()
    private let leftStack = NSStackView()
    private let gridStack = NSStackView()
    private let rightStack = NSStackView()
    private let toolbarStack = NSStackView()
    private let voiceWaveform = VoiceWaveformView()
    private let voiceLabel = NSTextField(labelWithString: "")
    private let voiceToggleButton = NSButton()
    private let voiceActionHover = ToolbarActionHoverView()
    private let voiceGroup = NSStackView()
    private let copyButton = NSButton()
    private let copyOptionsButton = NSButton()
    private let copyGroup = NSStackView()
    private let copyActionHover = ToolbarActionHoverView()
    private let copyOptionsMenu = NSMenu(title: "Copy")
    private let closeButton = NSButton()
    private let closeActionHover = ToolbarActionHoverView()
    private var swatches: [ColorSwatchButton] = []
    private var toolState = TraceToolState()
    private var temporaryCanvasTool: TraceCanvasTool?
    private var currentVoiceState: TraceVoiceCaptureState?
    private var dictationConfigured = true
    private var voicePresentationSuppressed = false
    private var currentVoiceToggleSymbol = ""
#if DEBUG
    private(set) var voiceStateApplyCountForTesting = 0
#endif

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        configureFloatingToolbarAppearance(self)

        let colors: [(String, TraceRGBAColor)] = [
            ("Red", .red),
            ("Blue", .blue),
            ("Yellow", .yellow),
            ("Green", .green),
        ]
        swatches = colors.map { name, color in
            let button = ColorSwatchButton(name: name, color: color)
            button.controlSize = .mini
            button.target = self
            button.action = #selector(selectColor(_:))
            return button
        }
        for swatch in swatches {
            swatchStack.addArrangedSubview(swatch)
        }
        swatchStack.orientation = .horizontal
        swatchStack.spacing = 5

        brushControl.segmentStyle = .rounded
        brushControl.controlSize = .small
        brushControl.selectedSegmentBezelColor = .controlAccentColor
        brushControl.target = self
        brushControl.action = #selector(changeBrush)
        let drawingTools = [
            (
                "cursorarrow",
                "arrow.up.left",
                "Select",
                "Select (V or hold ⌘)"
            ),
            ("pencil.tip", "pencil", "Pen", "Pen (D)"),
            (
                "highlighter",
                "pencil.and.outline",
                "Highlighter",
                "Highlighter (H)"
            ),
            ("rectangle", "square", "Rectangle", "Rectangle (R)"),
        ]
        for (index, tool) in drawingTools.enumerated() {
            brushControl.setImage(
                symbolImage(
                    named: tool.0,
                    fallback: tool.1,
                    description: tool.2,
                    pointSize: Self.drawingToolSymbolPointSize
                ),
                forSegment: index
            )
            brushControl.setWidth(28, forSegment: index)
            brushControl.setToolTip(tool.3, forSegment: index)
        }
        brushControl.setAccessibilityLabel("Drawing tool")
        brushActionHover.setContent(
            brushControl,
            controls: [brushControl]
        )

        gridControl.controlSize = .small
        gridControl.bezelStyle = .rounded
        gridControl.imagePosition = .imageOnly
        gridControl.contentTintColor = .controlAccentColor
        gridControl.target = self
        gridControl.action = #selector(changeGrid)
        gridControl.removeAllItems()
        let gridOptions: [
            (
                TraceGridStyle,
                String,
                String,
                String
            )
        ] = [
            (.none, "No grid", "square.slash", "nosign"),
            (
                .dots,
                "Dots",
                "circle.grid.3x3.fill",
                "circle.grid.2x2.fill"
            ),
            (.square, "Square", "square.grid.3x3", "square.grid.2x2"),
            (
                .horizontal,
                "Horizontal",
                "rectangle.split.3x1",
                "line.3.horizontal"
            ),
            (
                .vertical,
                "Vertical",
                "rectangle.split.1x2",
                "line.3.horizontal.decrease"
            ),
        ]
        for option in gridOptions {
            let item = NSMenuItem(
                title: option.1,
                action: nil,
                keyEquivalent: ""
            )
            item.representedObject = option.0.rawValue
            item.image = symbolImage(
                named: option.2,
                fallback: option.3,
                description: option.1,
                pointSize: Self.gridSymbolPointSize
            )
            gridControl.menu?.addItem(item)
        }
        gridControl.selectItem(at: 0)
        gridControl.widthAnchor.constraint(
            equalToConstant: Self.gridSelectorWidth
        ).isActive = true
        gridControl.setAccessibilityLabel("Canvas grid")
        gridControl.toolTip = "Canvas grid"

        let spacingFormatter = NumberFormatter()
        spacingFormatter.numberStyle = .none
        spacingFormatter.minimum = NSNumber(
            value: TraceGridPolicy.minimumSpacingPoints
        )
        spacingFormatter.maximum = NSNumber(
            value: TraceGridPolicy.maximumSpacingPoints
        )
        spacingFormatter.allowsFloats = false
        gridSpacingField.formatter = spacingFormatter
        gridSpacingField.delegate = self
        gridSpacingField.target = self
        gridSpacingField.action = #selector(changeGridSpacing)
        gridSpacingField.controlSize = .small
        gridSpacingField.font = .monospacedDigitSystemFont(
            ofSize: 11,
            weight: .medium
        )
        gridSpacingField.alignment = .right
        gridSpacingField.isEditable = true
        gridSpacingField.isSelectable = true
        gridSpacingField.isBezeled = false
        gridSpacingField.drawsBackground = false
        gridSpacingField.focusRingType = .default
        gridSpacingField.configureToolbarAppearance()
        gridSpacingField.onStep = { [weak self] value in
            guard let self else {
                return
            }
            guard self.toolState.gridSpacingPoints != value else {
                return
            }
            self.toolState.gridSpacingPoints = value
            self.onToolChange?(self.toolState)
        }
        gridSpacingField.widthAnchor.constraint(
            equalToConstant: Self.gridAccessoryWidth
        )
            .isActive = true
        gridSpacingField.setAccessibilityLabel("Grid spacing in points")
        gridSpacingField.toolTip = "Grid spacing (↑/↓)"
        gridSpacingGroup.orientation = .horizontal
        gridSpacingGroup.alignment = .centerY
        gridSpacingGroup.addArrangedSubview(gridSpacingField)
        gridSpacingGroup.widthAnchor.constraint(
            equalToConstant: Self.gridAccessoryWidth
        ).isActive = true
        gridSpacingField.isHidden = true

        widthSlider.controlSize = .small
        widthSlider.trackFillColor = nil
        widthSlider.target = self
        widthSlider.action = #selector(changeWidth)
        widthSlider.widthAnchor.constraint(equalToConstant: 82)
            .isActive = true
        widthSlider.setAccessibilityLabel("Stroke width")
        widthSlider.toolTip = "Stroke width"

        widthLabel.font = .monospacedDigitSystemFont(
            ofSize: 11,
            weight: .medium
        )
        widthLabel.textColor = NSColor.white.withAlphaComponent(0.78)
        widthLabel.alignment = .right
        widthLabel.widthAnchor.constraint(equalToConstant: 30).isActive = true

        backgroundColorWell.colorWellStyle = .minimal
        backgroundColorWell.isBordered = true
        backgroundColorWell.focusRingType = .default
        backgroundColorWell.isContinuous = true
        backgroundColorWell.target = self
        backgroundColorWell.action = #selector(changeBackgroundColor(_:))
        backgroundColorWell.isHidden = true
        backgroundColorWell.widthAnchor.constraint(equalToConstant: 30)
            .isActive = true
        backgroundColorWell.heightAnchor.constraint(equalToConstant: 22)
            .isActive = true
        backgroundColorWell.setAccessibilityLabel("Page background color")
        backgroundColorWell.toolTip = "Page background color"
        for separator in [
            backgroundSeparator,
            toolSeparator,
            voiceSeparator,
            recordingSeparator,
            actionSeparator,
        ] {
            configureSeparator(separator)
        }

        voiceWaveform.translatesAutoresizingMaskIntoConstraints = false
        voiceWaveform.widthAnchor.constraint(equalToConstant: 42).isActive =
            true
        voiceWaveform.heightAnchor.constraint(equalToConstant: 20).isActive =
            true
        voiceLabel.font = .systemFont(ofSize: 11, weight: .medium)
        voiceLabel.textColor = NSColor.white.withAlphaComponent(0.72)
        voiceLabel.lineBreakMode = .byTruncatingTail
        voiceLabel.widthAnchor.constraint(equalToConstant: 58).isActive = true
        voiceToggleButton.isBordered = false
        voiceToggleButton.imagePosition = .imageOnly
        voiceToggleButton.target = self
        voiceToggleButton.action = #selector(toggleVoiceRecording)
        voiceToggleButton.widthAnchor.constraint(equalToConstant: 24)
            .isActive = true
        voiceToggleButton.heightAnchor.constraint(equalToConstant: 24)
            .isActive = true
        voiceGroup.orientation = .horizontal
        voiceGroup.alignment = .centerY
        voiceGroup.spacing = 4
        voiceGroup.addArrangedSubview(voiceWaveform)
        voiceGroup.addArrangedSubview(voiceLabel)
        voiceActionHover.setContent(
            voiceToggleButton,
            controls: [voiceToggleButton]
        )
        voiceGroup.addArrangedSubview(voiceActionHover)
        voiceGroup.setAccessibilityLabel("Dictation status")
        setVoiceState(.idle)

        copyButton.image = symbolImage(
            named: "doc.on.doc",
            fallback: "doc.on.clipboard",
            description: "Copy trace"
        )
        copyButton.isBordered = false
        copyButton.title = ""
        copyButton.imagePosition = .imageOnly
        copyButton.image?.isTemplate = true
        copyButton.contentTintColor = NSColor.white.withAlphaComponent(0.78)
        copyButton.toolTip = "Copy trace (⌘C)"
        copyButton.setAccessibilityLabel("Copy trace")
        copyButton.setAccessibilityHelp("Keyboard shortcut Command-C")
        copyButton.target = self
        copyButton.action = #selector(copyDrawing)
        copyButton.heightAnchor.constraint(equalToConstant: 24).isActive = true
        copyButton.widthAnchor.constraint(equalToConstant: 24).isActive = true

        copyOptionsButton.image = symbolImage(
            named: "chevron.down",
            fallback: "arrowtriangle.down.fill",
            description: "Copy options",
            pointSize: Self.chevronSymbolPointSize,
            weight: .semibold
        )
        copyOptionsButton.isBordered = false
        copyOptionsButton.image?.isTemplate = true
        copyOptionsButton.imagePosition = .imageOnly
        copyOptionsButton.contentTintColor =
            NSColor.white.withAlphaComponent(0.68)
        copyOptionsButton.toolTip = "Copy options"
        copyOptionsButton.setAccessibilityLabel("Copy options")
        copyOptionsButton.target = self
        copyOptionsButton.action = #selector(showCopyOptions(_:))
        copyOptionsButton.widthAnchor.constraint(equalToConstant: 14)
            .isActive = true
        copyOptionsButton.heightAnchor.constraint(equalToConstant: 24)
            .isActive = true

        let copyDictationItem = NSMenuItem(
            title: "Copy Dictation",
            action: #selector(copyDictation),
            keyEquivalent: ""
        )
        copyDictationItem.target = self
        copyOptionsMenu.addItem(copyDictationItem)
        let copyImageItem = NSMenuItem(
            title: "Copy Image",
            action: #selector(copyImage),
            keyEquivalent: ""
        )
        copyImageItem.target = self
        copyOptionsMenu.addItem(copyImageItem)

        copyGroup.orientation = .horizontal
        copyGroup.alignment = .centerY
        copyGroup.spacing = 1
        copyGroup.addArrangedSubview(copyButton)
        copyGroup.addArrangedSubview(copyOptionsButton)
        copyActionHover.setContent(
            copyGroup,
            controls: [copyButton, copyOptionsButton]
        )

        closeButton.image = symbolImage(
            named: "xmark",
            fallback: "multiply",
            description: "Close drawing board"
        )
        closeButton.isBordered = false
        closeButton.image?.isTemplate = true
        closeButton.contentTintColor = NSColor.white.withAlphaComponent(0.7)
        closeButton.toolTip = "Close trace (⌘W)"
        closeButton.setAccessibilityLabel("Close trace")
        closeButton.setAccessibilityHelp("Keyboard shortcut Command-W")
        closeButton.target = self
        closeButton.action = #selector(closeBoard)
        closeButton.widthAnchor.constraint(equalToConstant: 24).isActive = true
        closeButton.heightAnchor.constraint(equalToConstant: 24).isActive = true
        closeActionHover.setContent(
            closeButton,
            controls: [closeButton]
        )

        let rightControls: [NSView] = [
            voiceGroup,
            recordingSeparator,
            copyActionHover,
            actionSeparator,
            closeActionHover,
        ]
        gridStack.addArrangedSubview(gridControl)
        gridStack.addArrangedSubview(gridSpacingGroup)
        let leftControls: [NSView] = [
            backgroundColorWell,
            gridStack,
            backgroundSeparator,
            swatchStack,
            toolSeparator,
            brushActionHover,
            widthSlider,
            widthLabel,
        ]
        for control in leftControls {
            leftStack.addArrangedSubview(control)
        }
        for control in rightControls {
            rightStack.addArrangedSubview(control)
        }
        for stack in [leftStack, gridStack, rightStack] {
            stack.translatesAutoresizingMaskIntoConstraints = false
            stack.orientation = .horizontal
            stack.alignment = .centerY
            stack.spacing = 8
        }
        gridStack.spacing = Self.gridAccessoryGap
        configureSeparatorSpacing(
            around: [
                backgroundSeparator,
                toolSeparator,
            ],
            in: leftStack
        )
        configureSeparatorSpacing(
            around: [
                recordingSeparator,
                actionSeparator,
            ],
            in: rightStack
        )
        toolbarStack.translatesAutoresizingMaskIntoConstraints = false
        toolbarStack.orientation = .horizontal
        toolbarStack.alignment = .centerY
        toolbarStack.spacing = 8
        toolbarStack.addArrangedSubview(leftStack)
        toolbarStack.addArrangedSubview(voiceSeparator)
        toolbarStack.addArrangedSubview(rightStack)
        configureSeparatorSpacing(
            around: [voiceSeparator],
            in: toolbarStack
        )
        addSubview(toolbarStack)

        NSLayoutConstraint.activate([
            toolbarStack.centerXAnchor.constraint(equalTo: centerXAnchor),
            toolbarStack.centerYAnchor.constraint(equalTo: centerYAnchor),
            toolbarStack.leadingAnchor.constraint(
                greaterThanOrEqualTo: leadingAnchor,
                constant: Self.horizontalPadding
            ),
            toolbarStack.trailingAnchor.constraint(
                lessThanOrEqualTo: trailingAnchor,
                constant: -Self.horizontalPadding
            ),
            gridSpacingField.heightAnchor.constraint(
                equalTo: gridControl.heightAnchor
            ),
        ])
    }

    required init?(coder: NSCoder) {
        nil
    }

    var preferredSize: NSSize {
        let contentSize = toolbarStack.fittingSize
        return NSSize(
            width: ceil(
                contentSize.width + Self.horizontalPadding * 2
            ),
            height: Self.preferredHeight
        )
    }

    func setToolState(_ state: TraceToolState) {
        toolState = state
        if toolState.brush == .marker {
            toolState.brush = .pen
            if toolState.canvasTool == .highlighter {
                toolState.canvasTool = .pen
            }
        }
        syncControls()
    }

    func setDocument(_ document: TraceDrawingSession) {
        dismissBackgroundPicker()
        temporaryCanvasTool = nil
        backgroundColorWell.isHidden = false
        backgroundColorWell.color = NSColor(
            document.manifest.backgroundColor
                ?? TraceRGBAColor(red: 1, green: 1, blue: 1)
        )
    }

    func setTemporaryCanvasTool(_ tool: TraceCanvasTool?) {
        guard temporaryCanvasTool != tool else {
            return
        }
        temporaryCanvasTool = tool
        syncControls()
    }

    func setVoiceState(
        _ state: TraceVoiceCaptureState,
        dictationConfigured: Bool = true
    ) {
        guard state != currentVoiceState
                || dictationConfigured
                    != self.dictationConfigured
        else {
            return
        }
        currentVoiceState = state
        self.dictationConfigured = dictationConfigured
        guard !voicePresentationSuppressed else {
            return
        }
        applyVoicePresentation(state)
    }

    func setVoicePresentationSuppressed(_ suppressed: Bool) {
        guard voicePresentationSuppressed != suppressed else {
            return
        }
        voicePresentationSuppressed = suppressed
        applyVoicePresentation(
            suppressed ? .idle : currentVoiceState ?? .idle
        )
        if suppressed {
            voiceToggleButton.isEnabled = false
            setCopyControlsEnabled(false)
            voiceActionHover.refreshHoverAppearance()
        }
    }

    private func applyVoicePresentation(
        _ state: TraceVoiceCaptureState
    ) {
#if DEBUG
        voiceStateApplyCountForTesting += 1
#endif
        let toggleSymbol: String
        let toggleLabel: String
        let accessibilityValue: String
        voiceLabel.toolTip = nil
        voiceLabel.isHidden = false
        switch state {
        case .idle:
            voiceLabel.stringValue = ""
            voiceLabel.isHidden = true
            voiceWaveform.setMode(.idle)
            toggleSymbol = "mic.circle.fill"
            toggleLabel = dictationConfigured
                ? "Start recording"
                : "Set up Dictation"
            accessibilityValue = dictationConfigured
                ? "No voice recording"
                : "Dictation setup required"
            voiceToggleButton.contentTintColor =
                NSColor.white.withAlphaComponent(0.68)
            voiceToggleButton.isEnabled = true
            setCopyControlsEnabled(true)
        case .recording:
            voiceLabel.stringValue = ""
            voiceLabel.isHidden = true
            voiceWaveform.setMode(.recording)
            toggleSymbol = "stop.circle.fill"
            toggleLabel = "Stop recording"
            accessibilityValue = "Recording"
            voiceToggleButton.contentTintColor =
                Self.recordingAccentColor
            voiceToggleButton.isEnabled = true
            setCopyControlsEnabled(true)
        case .paused:
            voiceLabel.stringValue = ""
            voiceLabel.isHidden = true
            voiceWaveform.setMode(.paused)
            toggleSymbol = "pause.circle.fill"
            toggleLabel = "Resume recording"
            accessibilityValue = "Recording paused"
            voiceToggleButton.contentTintColor = .labelColor
            voiceToggleButton.isEnabled = true
            setCopyControlsEnabled(true)
        case let .transcribing(_, pendingChunks):
            voiceLabel.stringValue = pendingChunks == 0
                ? "Finishing"
                : "Finishing \(pendingChunks)"
            voiceWaveform.setMode(.processing)
            toggleSymbol = "stop.fill"
            toggleLabel = "Recording is finalizing"
            accessibilityValue = voiceLabel.stringValue
            voiceToggleButton.contentTintColor =
                NSColor.white.withAlphaComponent(0.34)
            voiceToggleButton.isEnabled = false
            setCopyControlsEnabled(false)
        case .ready:
            voiceLabel.stringValue = "Transcript"
            voiceWaveform.setMode(.ready)
            toggleSymbol = "checkmark.circle.fill"
            toggleLabel = "Recording complete"
            accessibilityValue = "Transcript ready"
            voiceToggleButton.contentTintColor = .systemGreen
            voiceToggleButton.isEnabled = false
            setCopyControlsEnabled(true)
        case let .failed(message):
            voiceLabel.stringValue = "Error"
            voiceLabel.toolTip = message
            voiceWaveform.setMode(.failed)
            toggleSymbol = "arrow.counterclockwise"
            toggleLabel = dictationConfigured
                ? "Start a new recording"
                : "Set up Dictation"
            accessibilityValue = dictationConfigured
                ? "Voice recording error"
                : "Dictation setup required"
            voiceToggleButton.contentTintColor = .systemOrange
            voiceToggleButton.isEnabled = true
            setCopyControlsEnabled(true)
        }
        currentVoiceToggleSymbol = toggleSymbol
        voiceToggleButton.image = symbolImage(
            named: toggleSymbol,
            fallback: toggleSymbol == "mic.circle.fill"
                ? "mic.fill"
                : "record.circle",
            description: toggleLabel,
            pointSize: toggleSymbol == "mic.circle.fill"
                ? 19
                : Self.toolbarSymbolPointSize
        )
        voiceToggleButton.toolTip = toggleLabel
        voiceToggleButton.toolTip = toggleLabel
        voiceToggleButton.setAccessibilityLabel(toggleLabel)
        voiceGroup.setAccessibilityValue(accessibilityValue)
        voiceActionHover.refreshHoverAppearance()
        onPreferredSizeChange?()
    }

    private func setCopyControlsEnabled(_ enabled: Bool) {
        copyButton.isEnabled = enabled
        copyOptionsButton.isEnabled = enabled
        copyActionHover.refreshHoverAppearance()
    }

#if DEBUG
    var toolbarGroupLayoutForTesting: (
        contentCenterOffset: CGFloat,
        gridAccessoryGap: CGFloat,
        gridDividerVisible: Bool,
        toolSeparatorIndex: Int?,
        brushIndex: Int?,
        strokeIndex: Int?,
        voiceSeparatorIndex: Int?,
        voiceIndex: Int?,
        recordingSeparatorIndex: Int?,
        copyIndex: Int?,
        actionSeparatorIndex: Int?,
        closeIndex: Int?,
        separatorNeighborGaps: [CGFloat]
    ) {
        layoutSubtreeIfNeeded()
        let left = leftStack.arrangedSubviews
        let right = rightStack.arrangedSubviews
        let toolbar = toolbarStack.arrangedSubviews
        let gridControlFrame = convert(
            gridControl.bounds,
            from: gridControl
        )
        let gridAccessoryFrame = convert(
            gridSpacingGroup.bounds,
            from: gridSpacingGroup
        )
        return (
            contentCenterOffset:
                abs(toolbarStack.frame.midX - bounds.midX),
            gridAccessoryGap:
                gridAccessoryFrame.minX - gridControlFrame.maxX,
            gridDividerVisible:
                backgroundSeparator.superview != nil
                    && !backgroundSeparator.isHidden,
            toolSeparatorIndex: left.firstIndex {
                $0 === toolSeparator
            },
            brushIndex: left.firstIndex {
                $0 === brushActionHover
            },
            strokeIndex: left.firstIndex {
                $0 === widthSlider
            },
            voiceSeparatorIndex: toolbar.firstIndex {
                $0 === voiceSeparator
            },
            voiceIndex: right.firstIndex {
                $0 === voiceGroup
            },
            recordingSeparatorIndex: right.firstIndex {
                $0 === recordingSeparator
            },
            copyIndex: right.firstIndex {
                $0 === copyActionHover
            },
            actionSeparatorIndex: right.firstIndex {
                $0 === actionSeparator
            },
            closeIndex: right.firstIndex {
                $0 === closeActionHover
            },
            separatorNeighborGaps:
                separatorNeighborGaps(
                    around: [
                        backgroundSeparator,
                        toolSeparator,
                    ],
                    in: leftStack
                )
                + separatorNeighborGaps(
                    around: [
                        recordingSeparator,
                        actionSeparator,
                    ],
                    in: rightStack
                )
                + separatorNeighborGaps(
                    around: [voiceSeparator],
                    in: toolbarStack
                )
        )
    }

    private func separatorNeighborGaps(
        around separators: [NSBox],
        in stack: NSStackView
    ) -> [CGFloat] {
        let views = stack.arrangedSubviews
        return separators.flatMap { separator -> [CGFloat] in
            guard let index = views.firstIndex(where: {
                $0 === separator
            }),
                  index > views.startIndex,
                  index < views.index(before: views.endIndex)
            else {
                return []
            }
            let previous = views[views.index(before: index)]
            let next = views[views.index(after: index)]
            let previousFrame = convert(previous.bounds, from: previous)
            let separatorFrame = convert(separator.bounds, from: separator)
            let nextFrame = convert(next.bounds, from: next)
            return [
                separatorFrame.minX - previousFrame.maxX,
                nextFrame.minX - separatorFrame.maxX,
            ]
        }
    }

    var toolbarSizingForTesting: (
        toolbarWidth: CGFloat,
        leftInset: CGFloat,
        rightInset: CGFloat,
        gridCenterX: CGFloat,
        gridLeftReserve: CGFloat,
        gridRightReserve: CGFloat,
        backgroundToGridGap: CGFloat?,
        gridToColorsGap: CGFloat,
        spacingVisible: Bool
    ) {
        layoutSubtreeIfNeeded()
        let contentFrame = toolbarStack.frame
        let gridControlFrame = convert(
            gridControl.bounds,
            from: gridControl
        )
        let gridStackFrame = convert(
            gridStack.bounds,
            from: gridStack
        )
        let backgroundFrame = convert(
            backgroundColorWell.bounds,
            from: backgroundColorWell
        )
        let colorsFrame = convert(
            swatchStack.bounds,
            from: swatchStack
        )
        return (
            toolbarWidth: bounds.width,
            leftInset: contentFrame.minX - bounds.minX,
            rightInset: bounds.maxX - contentFrame.maxX,
            gridCenterX: gridControlFrame.midX,
            gridLeftReserve:
                gridControlFrame.minX - gridStackFrame.minX,
            gridRightReserve:
                gridStackFrame.maxX - gridControlFrame.maxX,
            backgroundToGridGap:
                backgroundColorWell.isHidden
                    ? nil
                    : gridStackFrame.minX - backgroundFrame.maxX,
            gridToColorsGap:
                colorsFrame.minX - gridStackFrame.maxX,
            spacingVisible: !gridSpacingField.isHidden
        )
    }

    var copyControlForTesting: (
        title: String,
        hasImage: Bool,
        toolTip: String?,
        isBordered: Bool,
        hasCustomBackground: Bool,
        width: CGFloat,
        hasChevron: Bool,
        menuTitles: [String],
        menuImageCount: Int,
        menuOpensBelow: Bool,
        menuGap: CGFloat,
        totalWidth: CGFloat
    ) {
        layoutSubtreeIfNeeded()
        let menuAnchor = copyMenuAnchor(for: copyOptionsButton)
        let buttonBounds = copyOptionsButton.bounds
        return (
            title: copyButton.title,
            hasImage: copyButton.image != nil,
            toolTip: copyButton.toolTip,
            isBordered: copyButton.isBordered,
            hasCustomBackground:
                copyButton.layer?.backgroundColor != nil,
            width: copyButton.bounds.width,
            hasChevron: copyOptionsButton.image != nil,
            menuTitles: copyOptionsMenu.items.map(\.title),
            menuImageCount: copyOptionsMenu.items.compactMap(\.image).count,
            menuOpensBelow:
                copyOptionsButton.isFlipped
                    ? menuAnchor.y > buttonBounds.maxY
                    : menuAnchor.y < buttonBounds.minY,
            menuGap:
                copyOptionsButton.isFlipped
                    ? menuAnchor.y - buttonBounds.maxY
                    : buttonBounds.minY - menuAnchor.y,
            totalWidth: copyGroup.bounds.width
        )
    }

    var gridSelectorPresentationForTesting: (
        isPopUp: Bool,
        displaysSelectedImageOnly: Bool,
        controlWidth: CGFloat,
        accessibilityLabel: String?,
        selectedTitle: String?,
        selectedStyle: TraceGridStyle,
        menuTitles: [String],
        menuImageCount: Int
    ) {
        layoutSubtreeIfNeeded()
        return (
            isPopUp: true,
            displaysSelectedImageOnly:
                gridControl.imagePosition == .imageOnly,
            controlWidth: gridControl.bounds.width,
            accessibilityLabel: gridControl.accessibilityLabel(),
            selectedTitle: gridControl.titleOfSelectedItem,
            selectedStyle: (
                gridControl.selectedItem?.representedObject as? String
            ).flatMap(TraceGridStyle.init(rawValue:)) ?? .none,
            menuTitles: gridControl.itemTitles,
            menuImageCount:
                gridControl.itemArray.compactMap(\.image).count
        )
    }

    func selectGridStyleForTesting(_ style: TraceGridStyle) {
        guard let index = gridControl.itemArray.firstIndex(where: {
            ($0.representedObject as? String) == style.rawValue
        }) else {
            return
        }
        gridControl.selectItem(at: index)
        changeGrid()
    }

    var toolbarIconMetricsForTesting: (
        voiceHeight: CGFloat,
        copyHeight: CGFloat,
        closeHeight: CGFloat,
        brushHeights: [CGFloat],
        gridHeights: [CGFloat],
        brushControlHeight: CGFloat,
        swatchDiameter: CGFloat,
        sliderControlSize: UInt,
        sliderCellType: String,
        sliderKnobSize: NSSize
    ) {
        layoutSubtreeIfNeeded()
        let sliderCell = widthSlider.cell as? NSSliderCell
        return (
            voiceHeight: voiceToggleButton.image?.size.height ?? 0,
            copyHeight: copyButton.image?.size.height ?? 0,
            closeHeight: closeButton.image?.size.height ?? 0,
            brushHeights: (0..<brushControl.segmentCount).map {
                brushControl.image(forSegment: $0)?.size.height ?? 0
            },
            gridHeights: gridControl.itemArray.compactMap {
                $0.image?.size.height
            },
            brushControlHeight: brushControl.bounds.height,
            swatchDiameter: swatches.first?.bounds.height ?? 0,
            sliderControlSize: widthSlider.controlSize.rawValue,
            sliderCellType: widthSlider.cell.map {
                String(describing: type(of: $0))
            } ?? "nil",
            sliderKnobSize:
                sliderCell?.knobRect(
                    flipped: widthSlider.isFlipped
                ).size ?? .zero
        )
    }

    var drawingToolPresentationForTesting: (
        selectedSegment: Int,
        toolTips: [String?],
        closeToolTip: String?
    ) {
        (
            selectedSegment: brushControl.selectedSegment,
            toolTips: (0..<brushControl.segmentCount).map {
                brushControl.toolTip(forSegment: $0)
            },
            closeToolTip: closeButton.toolTip
        )
    }

    var controlAccentPresentationForTesting: (
        brush: Bool,
        grid: Bool,
        slider: Bool
    ) {
        (
            brush: brushControl.selectedSegmentBezelColor?
                .isEqual(NSColor.controlAccentColor) == true,
            grid: gridControl.contentTintColor?
                .isEqual(NSColor.controlAccentColor) == true,
            slider: widthSlider.trackFillColor?
                .isEqual(NSColor.controlAccentColor) == true
        )
    }

    var actionHoverPresentationForTesting: (
        brushAttached: Bool,
        brushAlpha: CGFloat,
        micAlpha: CGFloat,
        copyAlpha: CGFloat,
        closeAlpha: CGFloat,
        cornerRadii: [CGFloat]
    ) {
        (
            brushAttached: brushActionHover.superview != nil,
            brushAlpha: brushActionHover.hoverBackgroundAlphaForTesting,
            micAlpha: voiceActionHover.hoverBackgroundAlphaForTesting,
            copyAlpha: copyActionHover.hoverBackgroundAlphaForTesting,
            closeAlpha: closeActionHover.hoverBackgroundAlphaForTesting,
            cornerRadii: [
                brushActionHover.hoverCornerRadiusForTesting,
                voiceActionHover.hoverCornerRadiusForTesting,
                copyActionHover.hoverCornerRadiusForTesting,
                closeActionHover.hoverCornerRadiusForTesting,
            ]
        )
    }

    func setActionHoverForTesting(_ hovered: Bool) {
        brushActionHover.setHoveredForTesting(hovered)
        voiceActionHover.setHoveredForTesting(hovered)
        copyActionHover.setHoveredForTesting(hovered)
        closeActionHover.setHoveredForTesting(hovered)
    }

    func setColorSwatchHoverForTesting(
        index: Int,
        hovered: Bool
    ) {
        guard swatches.indices.contains(index) else {
            return
        }
        swatches[index].setHoveredForTesting(hovered)
    }

    func colorSwatchPresentationForTesting(
        index: Int
    ) -> (
        borderWidth: CGFloat,
        borderAlpha: CGFloat,
        isSelected: Bool
    )? {
        guard swatches.indices.contains(index) else {
            return nil
        }
        return swatches[index].presentationForTesting
    }

    var backgroundControlLayoutForTesting: (
        backgroundIndex: Int?,
        gridIndex: Int?,
        separatorIndex: Int?,
        colorsIndex: Int?,
        backgroundHidden: Bool,
        separatorHidden: Bool
    ) {
        let views = leftStack.arrangedSubviews
        return (
            backgroundIndex: views.firstIndex {
                $0 === backgroundColorWell
            },
            gridIndex: views.firstIndex {
                $0 === gridStack
            },
            separatorIndex: views.firstIndex {
                $0 === backgroundSeparator
            },
            colorsIndex: views.firstIndex {
                $0 === swatchStack
            },
            backgroundHidden: backgroundColorWell.isHidden,
            separatorHidden: backgroundSeparator.isHidden
        )
    }

    var backgroundSwatchPresentationForTesting: (
        size: NSSize,
        usesQuickSwatches: Bool,
        color: NSColor
    ) {
        layoutSubtreeIfNeeded()
        backgroundColorWell.layoutSubtreeIfNeeded()
        return (
            size: backgroundColorWell.bounds.size,
            usesQuickSwatches:
                backgroundColorWell.usesQuickSwatchesForTesting,
            color:
                backgroundColorWell.color
                    .usingColorSpace(.deviceRGB)
                    ?? backgroundColorWell.color
        )
    }

    var backgroundPickerStateForTesting: (
        isActive: Bool,
        panelVisible: Bool
    ) {
        (
            isActive: backgroundColorWell.isActive,
            panelVisible: NSColorPanel.shared.isVisible
        )
    }

    var backgroundColorWellPointForTesting: NSPoint {
        convert(
            NSPoint(
                x: backgroundColorWell.bounds.midX,
                y: backgroundColorWell.bounds.midY
            ),
            from: backgroundColorWell
        )
    }

    var gridSpacingPresentationForTesting: (
        unitText: String?,
        accessibilityLabel: String?,
        fieldHeight: CGFloat,
        gridControlHeight: CGFloat,
        backgroundAlpha: CGFloat,
        hoverBackgroundAlpha: CGFloat,
        focusBackgroundAlpha: CGFloat,
        focusBorderAlpha: CGFloat,
        focusBorderWidth: CGFloat,
        disabledBackgroundAlpha: CGFloat,
        disabledTextAlpha: CGFloat,
        textAlpha: CGFloat,
        drawsBackground: Bool,
        isBezeled: Bool,
        focusRingType: NSFocusRingType,
        isEditable: Bool,
        isSelectable: Bool,
        fontSize: CGFloat,
        baselineOffset: CGFloat,
        focusedEditorRect: CGRect,
        focusedBaselineOffset: CGFloat,
        focusedGlyphCenterOffset: CGFloat
    ) {
        layoutSubtreeIfNeeded()
        gridSpacingField.layoutSubtreeIfNeeded()
        gridControl.layoutSubtreeIfNeeded()
        let originalValue = gridSpacingField.stringValue
        gridSpacingField.stringValue = "16"
        let focusedTextMetrics =
            (
                gridSpacingField.cell as? GridSpacingTextFieldCell
            )?.focusedTextMetrics(
                forBounds: gridSpacingField.bounds,
                in: gridSpacingField
            ) ?? (.zero, 0, .infinity)
        gridSpacingField.stringValue = originalValue
        let backgroundAlpha =
            gridSpacingField.toolbarBackgroundAlphaForTesting
        gridSpacingField.setHoveredForTesting(true)
        let hoverBackgroundAlpha =
            gridSpacingField.toolbarBackgroundAlphaForTesting
        gridSpacingField.setHoveredForTesting(false)
        gridSpacingField.setEditingForTesting(true)
        let focusBackgroundAlpha =
            gridSpacingField.toolbarBackgroundAlphaForTesting
        let focusBorderAlpha =
            gridSpacingField.toolbarBorderAlphaForTesting
        let focusBorderWidth = gridSpacingField.toolbarBorderWidthForTesting
        gridSpacingField.setEditingForTesting(false)
        gridSpacingField.isEnabled = false
        let disabledBackgroundAlpha =
            gridSpacingField.toolbarBackgroundAlphaForTesting
        let disabledTextAlpha =
            gridSpacingField.textColor?.alphaComponent ?? 0
        gridSpacingField.isEnabled = true
        return (
            unitText: gridSpacingGroup.arrangedSubviews
                .compactMap { ($0 as? NSTextField)?.stringValue }
                .first { $0 != gridSpacingField.stringValue },
            accessibilityLabel:
                gridSpacingField.accessibilityLabel(),
            fieldHeight: gridSpacingField.bounds.height,
            gridControlHeight: gridControl.bounds.height,
            backgroundAlpha: backgroundAlpha,
            hoverBackgroundAlpha: hoverBackgroundAlpha,
            focusBackgroundAlpha: focusBackgroundAlpha,
            focusBorderAlpha: focusBorderAlpha,
            focusBorderWidth: focusBorderWidth,
            disabledBackgroundAlpha: disabledBackgroundAlpha,
            disabledTextAlpha: disabledTextAlpha,
            textAlpha: gridSpacingField.textColor?.alphaComponent ?? 0,
            drawsBackground: gridSpacingField.drawsBackground,
            isBezeled: gridSpacingField.isBezeled,
            focusRingType: gridSpacingField.focusRingType,
            isEditable: gridSpacingField.isEditable,
            isSelectable: gridSpacingField.isSelectable,
            fontSize: gridSpacingField.font?.pointSize ?? 0,
            baselineOffset:
                gridSpacingField.firstBaselineOffsetFromTop,
            focusedEditorRect: focusedTextMetrics.rect,
            focusedBaselineOffset: focusedTextMetrics.baselineOffset,
            focusedGlyphCenterOffset:
                focusedTextMetrics.glyphCenterOffset
        )
    }

    func activateBackgroundPickerForTesting() -> (
        isActive: Bool,
        panelVisible: Bool
    ) {
        backgroundColorWell.isHidden = false
        dismissBackgroundPicker()
        backgroundColorWell.performClick(nil)
        RunLoop.current.run(
            until: Date().addingTimeInterval(0.05)
        )
        return (
            isActive: backgroundColorWell.isActive,
            panelVisible: NSColorPanel.shared.isVisible
        )
    }

    func dismissBackgroundPickerForTesting() {
        dismissBackgroundPicker()
    }

    var dragRegionsForTesting: (
        emptyArea: Bool,
        controlArea: Bool
    ) {
        let emptyPoint = convert(
            NSPoint(
                x: widthLabel.bounds.midX,
                y: widthLabel.bounds.midY
            ),
            from: widthLabel
        )
        let controlPoint = swatches.first.map {
            convert(
                NSPoint(x: $0.bounds.midX, y: $0.bounds.midY),
                from: $0
            )
        } ?? .zero
        return (
            emptyArea: hitTest(emptyPoint) === self,
            controlArea: hitTest(controlPoint) === self
        )
    }

    func showBackgroundControlForTesting() {
        backgroundColorWell.isHidden = false
        backgroundSeparator.isHidden = false
        backgroundColorWell.color = .white
    }

    func selectBackgroundColorForTesting(_ color: TraceRGBAColor) {
        backgroundColorWell.deactivate()
        let panel = NSColorPanel.shared
        panel.setTarget(nil)
        panel.setAction(nil)
        panel.orderFront(nil)
        panel.color = NSColor(color)
        changeBackgroundColor(panel)
    }

    func selectBackgroundQuickColorForTesting(
        _ color: TraceRGBAColor
    ) {
        backgroundColorWell.color = NSColor(color)
        changeBackgroundColor(backgroundColorWell)
        RunLoop.current.run(
            until: Date().addingTimeInterval(0.05)
        )
    }

    func resetVoiceStateApplyCountForTesting() {
        voiceStateApplyCountForTesting = 0
    }

    var voicePresentationForTesting: (
        label: String,
        labelHidden: Bool,
        toggleSymbol: String,
        toggleTint: NSColor?,
        waveformColor: NSColor,
        toggleEnabled: Bool,
        copyEnabled: Bool
    ) {
        (
            label: voiceLabel.stringValue,
            labelHidden: voiceLabel.isHidden,
            toggleSymbol: currentVoiceToggleSymbol,
            toggleTint: voiceToggleButton.contentTintColor,
            waveformColor: voiceWaveform.colorForTesting,
            toggleEnabled: voiceToggleButton.isEnabled,
            copyEnabled:
                copyButton.isEnabled && copyOptionsButton.isEnabled
        )
    }

    func triggerCopyForTesting(_ content: TraceCopyContent) {
        switch content {
        case .all:
            copyDrawing()
        case .dictation:
            copyDictation()
        case .image:
            copyImage()
        }
    }
#endif

    func setVoiceLevel(_ level: Float) {
        voiceWaveform.push(level: level)
    }

    @objc private func selectColor(_ sender: ColorSwatchButton) {
        toolState.color = sender.traceColor
        syncControls()
        onToolChange?(toolState)
    }

    @objc private func changeBrush() {
        switch brushControl.indexOfSelectedItem {
        case 0:
            toolState.canvasTool = .select
        case 2:
            toolState.canvasTool = .highlighter
            toolState.brush = .highlighter
        case 3:
            toolState.canvasTool = .rectangle
            toolState.brush = .pen
        default:
            toolState.canvasTool = .pen
            toolState.brush = .pen
        }
        onToolChange?(toolState)
    }

    @objc private func changeGrid() {
        let previousStyle = toolState.gridStyle
        toolState.gridStyle = (
            gridControl.selectedItem?.representedObject as? String
        ).flatMap(TraceGridStyle.init(rawValue:)) ?? .none
        let hidesSpacing = toolState.gridStyle == .none
        if gridSpacingField.isHidden != hidesSpacing {
            gridSpacingField.isHidden = hidesSpacing
        }
        onToolChange?(toolState)
        if previousStyle == .none && toolState.gridStyle != .none {
            DispatchQueue.main.async { [weak self] in
                self?.focusGridSpacingField()
            }
        }
    }

    @objc private func changeGridSpacing() {
        let spacing = TraceGridPolicy.spacing(
            from: gridSpacingField.stringValue
        )
        gridSpacingField.stringValue = String(spacing)
        guard toolState.gridSpacingPoints != spacing else {
            return
        }
        toolState.gridSpacingPoints = spacing
        onToolChange?(toolState)
    }

    func controlTextDidChange(_ notification: Notification) {
        guard notification.object as? NSTextField === gridSpacingField else {
            return
        }
        let input = (
            gridSpacingField.currentEditor() as? NSTextView
        )?.string ?? gridSpacingField.stringValue
        if input
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .isEmpty
        {
            let minimum = TraceGridPolicy.minimumSpacingPoints
            guard toolState.gridSpacingPoints != minimum else {
                return
            }
            toolState.gridSpacingPoints = minimum
            onToolChange?(toolState)
            return
        }
        guard let value = Int(input),
              (
                  TraceGridPolicy.minimumSpacingPoints
                    ... TraceGridPolicy.maximumSpacingPoints
              ).contains(value)
        else {
            return
        }
        guard toolState.gridSpacingPoints != value else {
            return
        }
        toolState.gridSpacingPoints = value
        onToolChange?(toolState)
    }

    func controlTextDidEndEditing(_ notification: Notification) {
        guard notification.object as? NSTextField === gridSpacingField else {
            return
        }
        gridSpacingField.setEditing(false)
        changeGridSpacing()
    }

    func controlTextDidBeginEditing(_ notification: Notification) {
        guard notification.object as? NSTextField === gridSpacingField else {
            return
        }
        gridSpacingField.setEditing(true)
    }

    func control(
        _ control: NSControl,
        textView: NSTextView,
        doCommandBy commandSelector: Selector
    ) -> Bool {
        guard control === gridSpacingField else {
            return false
        }
        switch commandSelector {
        case #selector(NSResponder.moveUp(_:)):
            let value = gridSpacingField.step(
                by: 1,
                currentText: textView.string
            )
            textView.string = String(value)
            textView.selectAll(nil)
            return true
        case #selector(NSResponder.moveDown(_:)):
            let value = gridSpacingField.step(
                by: -1,
                currentText: textView.string
            )
            textView.string = String(value)
            textView.selectAll(nil)
            return true
        default:
            return false
        }
    }

    @objc private func changeWidth() {
        toolState.width = widthSlider.doubleValue
        widthLabel.stringValue = String(format: "%.1f", toolState.width)
        onToolChange?(toolState)
    }

    @objc private func changeBackgroundColor(_ sender: Any?) {
        let selectedColor = (sender as? NSColorPanel)?.color
            ?? backgroundColorWell.color
        applyBackgroundColor(selectedColor)
    }

    private func applyBackgroundColor(_ selectedColor: NSColor) {
        backgroundColorWell.color = selectedColor
        guard let color = selectedColor.usingColorSpace(
            .deviceRGB
        ) else {
            return
        }
        onBackgroundColorChange?(
            TraceRGBAColor(
                red: color.redComponent,
                green: color.greenComponent,
                blue: color.blueComponent,
                alpha: 1
            )
        )
    }

    @objc private func copyDrawing() {
        onCopy?(.all)
    }

    @objc private func showCopyOptions(_ sender: NSButton) {
        copyOptionsMenu.popUp(
            positioning: nil,
            at: copyMenuAnchor(for: sender),
            in: sender
        )
    }

    private func copyMenuAnchor(for sender: NSButton) -> NSPoint {
        NSPoint(x: 0, y: sender.bounds.maxY + 4)
    }

    @objc private func copyDictation() {
        onCopy?(.dictation)
    }

    @objc private func copyImage() {
        onCopy?(.image)
    }

    @objc private func toggleVoiceRecording() {
        onToggleVoiceRecording?()
    }

    @objc private func closeBoard() {
        onClose?()
    }

    private func syncControls() {
        for swatch in swatches {
            swatch.isSelected = swatch.traceColor == toolState.color
        }
        switch temporaryCanvasTool ?? toolState.canvasTool {
        case .select:
            brushControl.selectedSegment = 0
        case .pen:
            brushControl.selectedSegment = 1
        case .highlighter:
            brushControl.selectedSegment = 2
        case .rectangle:
            brushControl.selectedSegment = 3
        }
        if let index = gridControl.itemArray.firstIndex(where: {
            ($0.representedObject as? String)
                == toolState.gridStyle.rawValue
        }) {
            gridControl.selectItem(at: index)
        }
        gridSpacingField.isHidden = toolState.gridStyle == .none
        gridSpacingField.stringValue = String(toolState.gridSpacingPoints)
        widthSlider.doubleValue = toolState.width
        widthLabel.stringValue = String(format: "%.1f", toolState.width)
    }

    private func focusGridSpacingField() {
        guard let window else {
            return
        }
        window.makeKey()
        if window.makeFirstResponder(gridSpacingField) {
            gridSpacingField.selectText(nil)
        }
    }

    func handleToolbarPointerDown(at point: NSPoint) {
        let localPoint = convert(point, from: nil)
        let colorWellPoint = backgroundColorWell.convert(
            localPoint,
            from: self
        )
        guard !backgroundColorWell.bounds.contains(colorWellPoint) else {
            return
        }
        dismissBackgroundPicker()
    }

    func dismissBackgroundPicker() {
        guard backgroundColorWell.isActive
                || NSColorPanel.shared.isVisible
        else {
            return
        }
        backgroundColorWell.deactivate()
        NSColorPanel.shared.orderOut(nil)
    }

    private func symbolImage(
        named: String,
        fallback: String,
        description: String,
        pointSize: CGFloat = FloatingAnnotationToolbar
            .toolbarSymbolPointSize,
        weight: NSFont.Weight = .regular
    ) -> NSImage {
        let baseImage = NSImage(
            systemSymbolName: named,
            accessibilityDescription: description
        ) ?? NSImage(
            systemSymbolName: fallback,
            accessibilityDescription: description
        ) ?? NSImage()
        let image = baseImage.withSymbolConfiguration(
            NSImage.SymbolConfiguration(
                pointSize: pointSize,
                weight: weight
            )
        ) ?? baseImage
        image.isTemplate = true
        return image
    }

    private func configureSeparator(_ separator: NSBox) {
        separator.boxType = .separator
        separator.heightAnchor.constraint(equalToConstant: 21).isActive = true
        separator.widthAnchor.constraint(equalToConstant: 1).isActive = true
    }

    private func configureSeparatorSpacing(
        around separators: [NSBox],
        in stack: NSStackView
    ) {
        let views = stack.arrangedSubviews
        for separator in separators {
            guard let index = views.firstIndex(where: {
                $0 === separator
            }),
                  index > views.startIndex
            else {
                continue
            }
            let previous = views[views.index(before: index)]
            stack.setCustomSpacing(
                Self.separatorSpacing,
                after: previous
            )
            stack.setCustomSpacing(
                Self.separatorSpacing,
                after: separator
            )
        }
    }
}

private final class SetupOverlayView: NSView {
    var onCancelCalibration: (() -> Void)?

    private let calibrationSurface = CalibrationGuideView()
    private let calibrationClose = NSButton()
    private var calibrating = false
    private var calibrationCorner: CalibrationCorner?
    private let calibrationBackdropColor: NSColor? = nil

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        calibrationSurface.translatesAutoresizingMaskIntoConstraints = false
        calibrationClose.image = NSImage(
            systemSymbolName: "xmark",
            accessibilityDescription: "Cancel calibration"
        )
        calibrationClose.isBordered = false
        calibrationClose.target = self
        calibrationClose.action = #selector(dismissCalibration)
        calibrationClose.toolTip = "Cancel calibration"
        calibrationClose.setAccessibilityLabel("Cancel calibration")
        calibrationClose.translatesAutoresizingMaskIntoConstraints = false
        addSubview(calibrationSurface)
        addSubview(calibrationClose)
        let guideLeading = calibrationSurface.leadingAnchor.constraint(
            greaterThanOrEqualTo: leadingAnchor,
            constant: 72
        )
        guideLeading.priority = .defaultLow
        let guideTrailing = calibrationSurface.trailingAnchor.constraint(
            lessThanOrEqualTo: trailingAnchor,
            constant: -72
        )
        guideTrailing.priority = .defaultLow
        NSLayoutConstraint.activate([
            calibrationSurface.centerXAnchor.constraint(equalTo: centerXAnchor),
            calibrationSurface.topAnchor.constraint(
                equalTo: topAnchor,
                constant: 80
            ),
            guideLeading,
            guideTrailing,
            calibrationClose.topAnchor.constraint(
                equalTo: topAnchor,
                constant: 18
            ),
            calibrationClose.trailingAnchor.constraint(
                equalTo: trailingAnchor,
                constant: -18
            ),
        ])
        isHidden = true
    }

    required init?(coder: NSCoder) {
        nil
    }

    func update(
        _ snapshot: TraceAppSnapshot,
        shortcuts: TraceGlobalShortcutsSnapshot
    ) {
        calibrating = snapshot.calibrationActive
        calibrationCorner = snapshot.calibrationCorner
        isHidden = !calibrating
        calibrationSurface.isHidden = !calibrating
        calibrationClose.isHidden = !calibrating
        _ = shortcuts
        calibrationSurface.update(snapshot)
        needsDisplay = true
    }

    override func hitTest(_ point: NSPoint) -> NSView? {
        guard !isHidden else {
            return nil
        }

        return super.hitTest(point)
    }

    @objc private func dismissCalibration() {
        onCancelCalibration?()
    }

    override func draw(_ dirtyRect: NSRect) {
        super.draw(dirtyRect)
        guard calibrating else {
            return
        }
        if let calibrationBackdropColor {
            calibrationBackdropColor.setFill()
            bounds.fill()
        }
        let inset: CGFloat = 42
        let target = calibrationCorner.map { corner in
            switch corner {
            case .topLeft:
                return NSPoint(x: inset, y: bounds.maxY - inset)
            case .topRight:
                return NSPoint(x: bounds.maxX - inset, y: bounds.maxY - inset)
            case .bottomRight:
                return NSPoint(x: bounds.maxX - inset, y: inset)
            case .bottomLeft:
                return NSPoint(x: inset, y: inset)
            }
        } ?? NSPoint(x: bounds.midX, y: bounds.midY)
        let outer = NSBezierPath(
            ovalIn: NSRect(
                x: target.x - 13,
                y: target.y - 13,
                width: 26,
                height: 26
            )
        )
        NSColor.white.withAlphaComponent(0.92).setFill()
        outer.fill()
        let guide = NSBezierPath(
            ovalIn: NSRect(
                x: target.x - 9,
                y: target.y - 9,
                width: 18,
                height: 18
            )
        )
        NSColor.controlAccentColor.setFill()
        guide.fill()
        let center = NSBezierPath(
            ovalIn: NSRect(
                x: target.x - 2,
                y: target.y - 2,
                width: 4,
                height: 4
            )
        )
        NSColor.white.setFill()
        center.fill()
    }

#if DEBUG
    func cancelCalibrationForTesting() {
        dismissCalibration()
    }

    var calibrationStateForTesting: (
        visible: Bool,
        paintsReplacementBackground: Bool,
        usesDarkAppearance: Bool,
        backgroundBrightness: CGFloat,
        backgroundAlpha: CGFloat
    ) {
        layoutSubtreeIfNeeded()
        let calibrationBackground =
            calibrationSurface.backgroundStyleForTesting
        return (
            !isHidden,
            calibrationBackdropColor != nil,
            calibrationSurface.appearance?.name == .darkAqua,
            calibrationBackground.brightness,
            calibrationBackground.alpha
        )
    }
#endif
}

private final class SetupPanelView: NSView {
    private static let preferredWidth: CGFloat = 360
    private static let horizontalPadding: CGFloat = 20
    private static let verticalPadding: CGFloat = 18

    var onRequestScreenAccess: (() -> Void)?
    var onRequestMicrophoneAccess: (() -> Void)?
    var onSaveOpenRouterAPIKey: ((String) -> Void)?
    var onRemoveOpenRouterAPIKey: (() -> Void)?
    var onRecalibrate: (() -> Void)?
    var onGlobalShortcutsChange: (() -> Void)?

    private let penRow = SetupCapabilityRow()
    private let captureRow = SetupCapabilityRow()
    private let voiceRow = SetupCapabilityRow()
    private let openRouterRow = OpenRouterSetupRow()
    private let blankShortcutRow = SetupShortcutRecorderRow(
        action: .newBlankTrace
    )
    private let captureShortcutRow = SetupShortcutRecorderRow(
        action: .captureFrontmostApp
    )
    private let errorLabel = NSTextField(wrappingLabelWithString: "")
    private let contentStack = NSStackView()

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)

        penRow.onAction = { [weak self] in self?.onRecalibrate?() }
        captureRow.onAction = {
            [weak self] in self?.onRequestScreenAccess?()
        }
        voiceRow.onAction = {
            [weak self] in self?.onRequestMicrophoneAccess?()
        }
        openRouterRow.onSave = { [weak self] apiKey in
            self?.onSaveOpenRouterAPIKey?(apiKey)
        }
        openRouterRow.onRemove = { [weak self] in
            self?.onRemoveOpenRouterAPIKey?()
        }
        blankShortcutRow.onChange = { [weak self] in
            self?.onGlobalShortcutsChange?()
        }
        captureShortcutRow.onChange = { [weak self] in
            self?.onGlobalShortcutsChange?()
        }
        errorLabel.font = .systemFont(ofSize: 11)
        errorLabel.textColor = .systemRed
        errorLabel.lineBreakMode = .byWordWrapping
        errorLabel.maximumNumberOfLines = 0
        errorLabel.preferredMaxLayoutWidth =
            Self.preferredWidth - Self.horizontalPadding * 2
        errorLabel.setContentCompressionResistancePriority(
            .defaultLow,
            for: .horizontal
        )

        let penHeading = sectionHeading("Pen")
        let dictationHeading = sectionHeading("Dictation")
        let captureHeading = sectionHeading("Screen capture")
        let shortcutHeading = sectionHeading("Keyboard shortcuts")
        let divider = NSBox()
        divider.boxType = .separator
        [
            penHeading,
            penRow,
            dictationHeading,
            voiceRow,
            openRouterRow,
            captureHeading,
            captureRow,
            divider,
            shortcutHeading,
            blankShortcutRow,
            captureShortcutRow,
            errorLabel,
        ].forEach(contentStack.addArrangedSubview)
        contentStack.translatesAutoresizingMaskIntoConstraints = false
        contentStack.orientation = .vertical
        contentStack.alignment = .leading
        contentStack.spacing = 12
        [
            penHeading,
            penRow,
            dictationHeading,
            voiceRow,
            openRouterRow,
            captureHeading,
            captureRow,
            divider,
            shortcutHeading,
            blankShortcutRow,
            captureShortcutRow,
            errorLabel,
        ].forEach {
            $0.widthAnchor.constraint(equalTo: contentStack.widthAnchor)
                .isActive = true
        }
        contentStack.setCustomSpacing(8, after: penHeading)
        contentStack.setCustomSpacing(18, after: penRow)
        contentStack.setCustomSpacing(8, after: dictationHeading)
        contentStack.setCustomSpacing(8, after: voiceRow)
        contentStack.setCustomSpacing(18, after: openRouterRow)
        contentStack.setCustomSpacing(8, after: captureHeading)
        contentStack.setCustomSpacing(18, after: captureRow)
        contentStack.setCustomSpacing(14, after: divider)
        contentStack.setCustomSpacing(8, after: shortcutHeading)
        contentStack.setCustomSpacing(10, after: blankShortcutRow)
        addSubview(contentStack)
        NSLayoutConstraint.activate([
            contentStack.topAnchor.constraint(
                equalTo: topAnchor,
                constant: Self.verticalPadding
            ),
            contentStack.leadingAnchor.constraint(
                equalTo: leadingAnchor,
                constant: Self.horizontalPadding
            ),
            contentStack.trailingAnchor.constraint(
                equalTo: trailingAnchor,
                constant: -Self.horizontalPadding
            ),
            contentStack.bottomAnchor.constraint(
                equalTo: bottomAnchor,
                constant: -Self.verticalPadding
            ),
        ])
        setAccessibilityLabel("Set up Trace")
        setAccessibilityHelp(
            "Pen, screen capture, Dictation, OpenRouter, "
                + "and global shortcut setup."
        )
    }

    private func sectionHeading(_ title: String) -> NSTextField {
        let label = NSTextField(labelWithString: title)
        label.font = .systemFont(ofSize: 13, weight: .semibold)
        label.textColor = .labelColor
        return label
    }

    required init?(coder: NSCoder) {
        nil
    }

    var preferredSize: NSSize {
        let contentSize = contentStack.fittingSize
        return NSSize(
            width: Self.preferredWidth,
            height: ceil(
                contentSize.height + Self.verticalPadding * 2
            )
        )
    }

    func update(
        _ snapshot: TraceAppSnapshot,
        shortcuts: TraceGlobalShortcutsSnapshot
    ) {
        if snapshot.inputEnabled {
            let calibrated = snapshot.calibration != nil
            penRow.update(
                title: "Connected",
                detail: calibrated ? "Connected and ready" : "Connected",
                ready: calibrated,
                action: calibrated ? "Calibration" : "Start calibration"
            )
        } else {
            penRow.update(
                title: "Not detected",
                detail: connectionText(snapshot.connectionState),
                ready: false,
                action: nil
            )
        }
        captureRow.update(
            title: "Screen Recording permission",
            detail: snapshot.screenCaptureAuthorized
                ? "Screen Recording allowed"
                : "Screen Recording is off",
            ready: snapshot.screenCaptureAuthorized,
            action: snapshot.screenCaptureAuthorized ? nil : "Allow"
        )
        voiceRow.update(
            title: "Microphone access",
            detail: snapshot.microphoneAuthorized
                ? "Microphone access allowed"
                : "Microphone access is off",
            ready: snapshot.microphoneAuthorized,
            action: snapshot.microphoneAuthorized ? nil : "Allow"
        )
        openRouterRow.update(
            snapshot.openRouterAPIKeyState,
            voiceState: snapshot.voiceState
        )
        blankShortcutRow.update(
            shortcuts.state(for: .newBlankTrace)
        )
        captureShortcutRow.update(
            shortcuts.state(for: .captureFrontmostApp)
        )
        errorLabel.stringValue = snapshot.lastError ?? ""
        errorLabel.isHidden = snapshot.lastError == nil
    }

    private func connectionText(_ state: PenConnectionState) -> String {
        switch state {
        case .connected:
            return "Preparing pen input"
        case .connecting, .reconnecting:
            return "Connecting"
        case .discovering:
            return "Looking for the pen"
        case .failed:
            return "Connection failed"
        default:
            return "Remove the cap to connect"
        }
    }

#if DEBUG
    var backgroundBrightnessForTesting: CGFloat {
        layoutSubtreeIfNeeded()
        guard let representation = bitmapImageRepForCachingDisplay(
            in: bounds
        ) else {
            return 1
        }
        cacheDisplay(in: bounds, to: representation)
        let scaleX = CGFloat(representation.pixelsWide) / bounds.width
        let scaleY = CGFloat(representation.pixelsHigh) / bounds.height
        return representation.colorAt(
            x: Int((24 * scaleX).rounded()),
            y: Int((24 * scaleY).rounded())
        )?
            .usingColorSpace(.deviceRGB)?
            .brightnessComponent ?? 1
    }

    var stateForTesting: (
        penTitle: String,
        penDetail: String,
        penAction: String?,
        captureAction: String?,
        voiceAction: String?,
        voiceReady: Bool,
        usesRegularItemTypography: Bool,
        apiKeyFieldVisible: Bool,
        apiKeySaveVisible: Bool,
        apiKeyRemoveVisible: Bool,
        apiKeyResetTitle: String?,
        apiKeyResetUsesLinkStyle: Bool,
        errorUsesConstrainedWrapping: Bool,
        blankShortcut: String,
        blankShortcutDetail: String,
        captureShortcut: String,
        captureShortcutDetail: String
    ) {
        (
            penRow.titleForTesting,
            penRow.detailForTesting,
            penRow.actionForTesting,
            captureRow.actionForTesting,
            voiceRow.actionForTesting,
            voiceRow.readyForTesting,
            penRow.usesRegularTitleFontForTesting
                && captureRow.usesRegularTitleFontForTesting
                && voiceRow.usesRegularTitleFontForTesting
                && openRouterRow.usesRegularTitleFontForTesting
                && blankShortcutRow.usesRegularTitleFontForTesting
                && captureShortcutRow.usesRegularTitleFontForTesting,
            openRouterRow.fieldVisibleForTesting,
            openRouterRow.saveVisibleForTesting,
            openRouterRow.removeVisibleForTesting,
            openRouterRow.removeTitleForTesting,
            openRouterRow.removeUsesLinkStyleForTesting,
            errorLabel.lineBreakMode == .byWordWrapping
                && errorLabel.maximumNumberOfLines == 0
                && abs(
                    errorLabel.preferredMaxLayoutWidth
                        - (
                            Self.preferredWidth
                                - Self.horizontalPadding * 2
                        )
                ) < 0.5
                && errorLabel.contentCompressionResistancePriority(
                    for: .horizontal
                ) == .defaultLow,
            blankShortcutRow.shortcutForTesting,
            blankShortcutRow.detailForTesting,
            captureShortcutRow.shortcutForTesting,
            captureShortcutRow.detailForTesting
        )
    }

    var visibleTextForTesting: [String] {
        func collect(from view: NSView) -> [String] {
            var values: [String] = []
            if let label = view as? NSTextField,
               !label.isHidden,
               !label.stringValue.isEmpty
            {
                values.append(label.stringValue)
            }
            return values + view.subviews.flatMap(collect)
        }
        return collect(from: contentStack)
    }

    func shortcutConflictPolicyForTesting(
        _ action: TraceGlobalShortcutAction
    ) -> KeyboardShortcuts.ConflictPolicy {
        shortcutRow(for: action).conflictPolicyForTesting
    }

    func shortcutValidationForTesting(
        _ action: TraceGlobalShortcutAction,
        shortcut: KeyboardShortcuts.Shortcut
    ) -> KeyboardShortcuts.ValidationResult {
        shortcutRow(for: action).validationResultForTesting(shortcut)
    }

    private func shortcutRow(
        for action: TraceGlobalShortcutAction
    ) -> SetupShortcutRecorderRow {
        switch action {
        case .newBlankTrace:
            return blankShortcutRow
        case .captureFrontmostApp:
            return captureShortcutRow
        }
    }
#endif
}

private final class OpenRouterSetupRow: NSView {
    var onSave: ((String) -> Void)?
    var onRemove: (() -> Void)?

    private let titleLabel = NSTextField(
        labelWithString: "OpenRouter API key"
    )
    private let detailLabel = NSTextField(labelWithString: "")
    private let statusImage = NSImageView()
    private let apiKeyField = NSSecureTextField(frame: .zero)
    private let saveButton = NSButton()
    private let removeButton = NSButton()
    private let controls = NSStackView()

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        titleLabel.font = .systemFont(ofSize: 12, weight: .regular)
        titleLabel.textColor = .labelColor
        statusImage.translatesAutoresizingMaskIntoConstraints = false
        statusImage.imageScaling = .scaleProportionallyDown

        apiKeyField.controlSize = .small
        apiKeyField.placeholderString = "Enter OpenRouter API key"
        apiKeyField.setAccessibilityLabel("OpenRouter API key")
        apiKeyField.target = self
        apiKeyField.action = #selector(saveAPIKey)

        saveButton.bezelStyle = .rounded
        saveButton.controlSize = .small
        saveButton.target = self
        saveButton.action = #selector(saveAPIKey)

        removeButton.title = "Reset"
        removeButton.bezelStyle = .inline
        removeButton.isBordered = false
        removeButton.controlSize = .small
        removeButton.contentTintColor = .linkColor
        removeButton.font = .systemFont(ofSize: 12)
        removeButton.target = self
        removeButton.action = #selector(removeAPIKey)

        let heading = NSStackView(views: [
            statusImage,
            titleLabel,
            NSView(),
            removeButton,
        ])
        heading.orientation = .horizontal
        heading.alignment = .centerY
        heading.spacing = 9
        [apiKeyField, saveButton].forEach(
            controls.addArrangedSubview
        )
        controls.orientation = .horizontal
        controls.alignment = .centerY
        controls.spacing = 7
        apiKeyField.setContentHuggingPriority(.defaultLow, for: .horizontal)

        let stack = NSStackView(views: [heading, controls])
        stack.translatesAutoresizingMaskIntoConstraints = false
        stack.orientation = .vertical
        stack.alignment = .leading
        stack.spacing = 7
        addSubview(stack)
        NSLayoutConstraint.activate([
            stack.topAnchor.constraint(equalTo: topAnchor),
            stack.leadingAnchor.constraint(equalTo: leadingAnchor),
            stack.trailingAnchor.constraint(equalTo: trailingAnchor),
            stack.bottomAnchor.constraint(equalTo: bottomAnchor),
            controls.widthAnchor.constraint(equalTo: stack.widthAnchor),
            statusImage.widthAnchor.constraint(equalToConstant: 16),
            statusImage.heightAnchor.constraint(equalToConstant: 16),
        ])
    }

    required init?(coder: NSCoder) {
        nil
    }

    func update(
        _ state: OpenRouterAPIKeyState,
        voiceState: TraceVoiceCaptureState
    ) {
        switch state {
        case .externallySupplied:
            isHidden = false
            detailLabel.stringValue = "Provided by Trace configuration"
            apiKeyField.stringValue = ""
            apiKeyField.isHidden = true
            saveButton.isHidden = true
            removeButton.isHidden = true
            controls.isHidden = true
        case .userKeychain:
            isHidden = false
            detailLabel.stringValue = "Saved securely in Keychain"
            apiKeyField.stringValue = ""
            apiKeyField.isHidden = true
            saveButton.isHidden = true
            removeButton.isHidden = false
            controls.isHidden = true
        case .missing:
            isHidden = false
            detailLabel.stringValue =
                "Add your own key to enable Dictation"
            apiKeyField.placeholderString = "Enter OpenRouter API key"
            apiKeyField.isHidden = false
            saveButton.title = "Add"
            saveButton.isHidden = false
            removeButton.isHidden = true
            controls.isHidden = false
        }
        let ready = state != .missing
        statusImage.image = NSImage(
            systemSymbolName: ready
                ? "checkmark.circle.fill"
                : "exclamationmark.circle.fill",
            accessibilityDescription: ready ? "Ready" : "Needs attention"
        )
        statusImage.contentTintColor = ready ? .systemGreen : .systemOrange
        titleLabel.toolTip = detailLabel.stringValue
        let allowsMutation = voiceState.allowsOpenRouterAPIKeyMutation
        apiKeyField.isEnabled = allowsMutation
        saveButton.isEnabled = allowsMutation
        removeButton.isEnabled = allowsMutation
        if !allowsMutation, !isHidden {
            detailLabel.stringValue =
                "Finish or cancel the current Dictation recording "
                + "to change the key"
        }
        saveButton.setAccessibilityLabel(
            "\(saveButton.title) OpenRouter API key"
        )
        removeButton.setAccessibilityLabel("Reset OpenRouter API key")
        setAccessibilityLabel(
            "OpenRouter API key, \(detailLabel.stringValue)"
        )
        setAccessibilityHelp(
            allowsMutation
                ? "The key is stored only in macOS Keychain."
                : "Credential changes are disabled during Dictation."
        )
    }

    @objc private func saveAPIKey() {
        onSave?(apiKeyField.stringValue)
    }

    @objc private func removeAPIKey() {
        onRemove?()
    }

#if DEBUG
    var usesRegularTitleFontForTesting: Bool {
        titleLabel.font == .systemFont(ofSize: 12, weight: .regular)
    }
    var fieldVisibleForTesting: Bool { !apiKeyField.isHidden }
    var saveVisibleForTesting: Bool { !saveButton.isHidden }
    var removeVisibleForTesting: Bool { !removeButton.isHidden }
    var removeTitleForTesting: String? {
        removeButton.isHidden ? nil : removeButton.title
    }
    var removeUsesLinkStyleForTesting: Bool {
        !removeButton.isBordered
            && removeButton.bezelStyle == .inline
            && removeButton.contentTintColor == .linkColor
    }
#endif
}

private final class SetupCapabilityRow: NSView {
    var onAction: (() -> Void)?

    private let statusImage = NSImageView()
    private let titleLabel = NSTextField(labelWithString: "")
    private let detailLabel = NSTextField(labelWithString: "")
    private let actionButton = NSButton()
    private var ready = false

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        statusImage.translatesAutoresizingMaskIntoConstraints = false
        statusImage.imageScaling = .scaleProportionallyDown
        titleLabel.font = .systemFont(ofSize: 12, weight: .regular)
        titleLabel.textColor = .labelColor
        actionButton.bezelStyle = .rounded
        actionButton.controlSize = .small
        actionButton.target = self
        actionButton.action = #selector(performAction)

        let row = NSStackView(
            views: [statusImage, titleLabel, NSView(), actionButton]
        )
        row.translatesAutoresizingMaskIntoConstraints = false
        row.orientation = .horizontal
        row.alignment = .centerY
        row.spacing = 9
        addSubview(row)
        NSLayoutConstraint.activate([
            statusImage.widthAnchor.constraint(equalToConstant: 16),
            statusImage.heightAnchor.constraint(equalToConstant: 16),
            row.topAnchor.constraint(equalTo: topAnchor),
            row.leadingAnchor.constraint(equalTo: leadingAnchor),
            row.trailingAnchor.constraint(equalTo: trailingAnchor),
            row.bottomAnchor.constraint(equalTo: bottomAnchor),
        ])
    }

    required init?(coder: NSCoder) {
        nil
    }

    func update(
        title: String,
        detail: String,
        ready: Bool,
        action: String?
    ) {
        titleLabel.stringValue = title
        detailLabel.stringValue = detail
        self.ready = ready
        titleLabel.toolTip = detail
        statusImage.image = NSImage(
            systemSymbolName: ready
                ? "checkmark.circle.fill"
                : "exclamationmark.circle.fill",
            accessibilityDescription: ready ? "Ready" : "Needs attention"
        )
        statusImage.contentTintColor = ready ? .systemGreen : .systemOrange
        actionButton.title = action ?? ""
        actionButton.isHidden = action == nil
        setAccessibilityLabel("\(title), \(detail)")
    }

    @objc private func performAction() {
        onAction?()
    }

#if DEBUG
    var titleForTesting: String { titleLabel.stringValue }
    var detailForTesting: String { detailLabel.stringValue }
    var actionForTesting: String? {
        actionButton.isHidden ? nil : actionButton.title
    }
    var readyForTesting: Bool { ready }
    var usesRegularTitleFontForTesting: Bool {
        titleLabel.font == .systemFont(ofSize: 12, weight: .regular)
    }
#endif
}

private final class SetupShortcutRecorderRow: NSView {
    var onChange: (() -> Void)?

    private let action: TraceGlobalShortcutAction
    private let titleLabel = NSTextField(labelWithString: "")
    private let detailLabel = NSTextField(labelWithString: "")
    private var actionState = TraceGlobalShortcutActionState(
        assignment: nil,
        isActive: false,
        message: nil
    )
    private lazy var recorder = KeyboardShortcuts.RecorderCocoa(
        for: action.name
    ) { [weak self] _ in
        self?.onChange?()
    }

    init(action: TraceGlobalShortcutAction) {
        self.action = action
        super.init(frame: .zero)

        titleLabel.stringValue = action.title
        titleLabel.font = .systemFont(ofSize: 12.5, weight: .regular)
        titleLabel.setContentCompressionResistancePriority(
            .defaultLow,
            for: .horizontal
        )

        recorder.controlSize = .small
        recorder.conflictPolicy = .allowAll
        recorder.validateShortcut = { shortcut in
            TraceGlobalShortcutPolicy.validationResult(
                for: shortcut,
                action: action
            )
        }
        recorder.setAccessibilityLabel("\(action.title) global shortcut")
        recorder.setAccessibilityHelp(
            "Requires at least one modifier, or a function key. "
                + "Use the clear button inside the field to remove it."
        )

        let controls = NSStackView(views: [
            titleLabel,
            NSView(),
            recorder,
        ])
        controls.orientation = .horizontal
        controls.alignment = .centerY
        controls.spacing = 8

        let stack = NSStackView(views: [controls])
        stack.translatesAutoresizingMaskIntoConstraints = false
        stack.orientation = .vertical
        stack.alignment = .leading
        stack.spacing = 0
        controls.widthAnchor.constraint(
            equalTo: stack.widthAnchor
        ).isActive = true
        addSubview(stack)
        NSLayoutConstraint.activate([
            stack.topAnchor.constraint(equalTo: topAnchor),
            stack.leadingAnchor.constraint(equalTo: leadingAnchor),
            stack.trailingAnchor.constraint(equalTo: trailingAnchor),
            stack.bottomAnchor.constraint(equalTo: bottomAnchor),
        ])
        setAccessibilityRole(.group)
        setAccessibilityLabel("\(action.title) global shortcut")
        refreshPresentation()
    }

    required init?(coder: NSCoder) {
        nil
    }

    func update(_ state: TraceGlobalShortcutActionState) {
        actionState = state
        refreshPresentation()
    }

    private func refreshPresentation() {
        let assignment = actionState.assignment

        if let message = actionState.message {
            detailLabel.stringValue = message
            detailLabel.textColor = .systemRed
        } else if assignment == nil {
            detailLabel.stringValue =
                "Unassigned. Use a modifier or function key."
            detailLabel.textColor = .secondaryLabelColor
        } else if actionState.isActive {
            detailLabel.stringValue =
                "Active system-wide while Trace is running."
            detailLabel.textColor = .secondaryLabelColor
        } else {
            detailLabel.stringValue =
                "Saved, but macOS could not activate it."
            detailLabel.textColor = .systemOrange
        }
        recorder.toolTip = detailLabel.stringValue
        titleLabel.toolTip = detailLabel.stringValue
        setAccessibilityValue(
            [
                assignment?.description ?? "Unassigned",
                detailLabel.stringValue,
            ].joined(separator: ", ")
        )
    }

#if DEBUG
    var shortcutForTesting: String {
        recorder.stringValue.isEmpty ? "Unassigned" : recorder.stringValue
    }

    var detailForTesting: String {
        detailLabel.stringValue
    }

    var usesRegularTitleFontForTesting: Bool {
        titleLabel.font == .systemFont(ofSize: 12.5, weight: .regular)
    }

    var conflictPolicyForTesting: KeyboardShortcuts.ConflictPolicy {
        recorder.conflictPolicy
    }

    func validationResultForTesting(
        _ shortcut: KeyboardShortcuts.Shortcut
    ) -> KeyboardShortcuts.ValidationResult {
        recorder.validateShortcut?(shortcut) ?? .allow
    }
#endif
}

private final class CalibrationGuideView: NSView {
    private let instructionLabel = NSTextField(labelWithString: "")
    private let detailLabel = NSTextField(labelWithString: "")

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        let darkAppearance = NSAppearance(named: .darkAqua)
        appearance = darkAppearance
        wantsLayer = true
        // Semantic window colors changed with the linked SDK.
        layer?.backgroundColor = NSColor(
            calibratedWhite: 0.11,
            alpha: 0.88
        ).cgColor
        layer?.cornerRadius = 14
        layer?.cornerCurve = .continuous

        instructionLabel.font = .systemFont(ofSize: 24, weight: .semibold)
        instructionLabel.textColor = .labelColor
        instructionLabel.alignment = .center
        instructionLabel.maximumNumberOfLines = 2
        instructionLabel.lineBreakMode = .byWordWrapping

        detailLabel.font = .systemFont(ofSize: 13, weight: .regular)
        detailLabel.textColor = .secondaryLabelColor
        detailLabel.alignment = .center
        detailLabel.maximumNumberOfLines = 2
        detailLabel.lineBreakMode = .byWordWrapping

        let stack = NSStackView(views: [
            instructionLabel,
            detailLabel,
        ])
        stack.translatesAutoresizingMaskIntoConstraints = false
        stack.orientation = .vertical
        stack.alignment = .centerX
        stack.spacing = 8
        addSubview(stack)

        NSLayoutConstraint.activate([
            stack.topAnchor.constraint(equalTo: topAnchor, constant: 14),
            stack.leadingAnchor.constraint(
                equalTo: leadingAnchor,
                constant: 18
            ),
            stack.trailingAnchor.constraint(
                equalTo: trailingAnchor,
                constant: -18
            ),
            stack.bottomAnchor.constraint(
                equalTo: bottomAnchor,
                constant: -14
            ),
        ])
    }

    required init?(coder: NSCoder) {
        nil
    }

    func update(_ snapshot: TraceAppSnapshot) {
        guard snapshot.calibrationActive else {
            return
        }
        guard snapshot.inputEnabled else {
            instructionLabel.stringValue = "Remove the cap and wait for the pen to connect."
            detailLabel.stringValue = "Keep the pen nearby. The first paper target appears automatically."
            return
        }
        if let corner = snapshot.calibrationCorner {
            let retrying = snapshot.calibrationMessage?.hasPrefix("Try ") == true
            instructionLabel.stringValue = retrying
                ? "Try the \(corner.displayName) corner again."
                : "On the paper, touch its \(corner.displayName) corner."
            detailLabel.stringValue =
                "One firm tap, then lift. Trace advances automatically."
        } else {
            instructionLabel.stringValue = "On the paper, touch once near its center."
            detailLabel.stringValue =
                "This identifies the Ncode page. Lift when Trace advances."
        }
    }

#if DEBUG
    var backgroundStyleForTesting: (
        brightness: CGFloat,
        alpha: CGFloat
    ) {
        let color = layer?.backgroundColor
            .flatMap(NSColor.init(cgColor:))?
            .usingColorSpace(.deviceRGB)
        return (
            color?.brightnessComponent ?? 1,
            color?.alphaComponent ?? 0
        )
    }
#endif
}

private final class PageBackgroundColorWell: NSColorWell {
    override var needsPanelToBecomeKey: Bool {
        true
    }

    override func activate(_ exclusive: Bool) {
        super.activate(exclusive)
        let panel = NSColorPanel.shared
        panel.isContinuous = true
        panel.setTarget(target)
        panel.setAction(action)
    }

#if DEBUG
    var usesQuickSwatchesForTesting: Bool {
        colorWellStyle == .minimal
    }
#endif
}

private final class GridSpacingTextFieldCell: NSTextFieldCell {
    override func drawingRect(forBounds rect: NSRect) -> NSRect {
        var drawingRect = super.drawingRect(forBounds: rect)
        let textHeight = min(
            cellSize(forBounds: rect).height,
            drawingRect.height
        )
        drawingRect.origin.y += (drawingRect.height - textHeight) / 2
        drawingRect.size.height = textHeight
        return drawingRect
    }

    override func edit(
        withFrame rect: NSRect,
        in controlView: NSView,
        editor textObj: NSText,
        delegate: Any?,
        event: NSEvent?
    ) {
        super.edit(
            withFrame: drawingRect(forBounds: rect),
            in: controlView,
            editor: textObj,
            delegate: delegate,
            event: event
        )
    }

    override func select(
        withFrame rect: NSRect,
        in controlView: NSView,
        editor textObj: NSText,
        delegate: Any?,
        start selStart: Int,
        length selLength: Int
    ) {
        super.select(
            withFrame: drawingRect(forBounds: rect),
            in: controlView,
            editor: textObj,
            delegate: delegate,
            start: selStart,
            length: selLength
        )
    }

#if DEBUG
    func focusedTextMetrics(
        forBounds rect: NSRect,
        in controlView: NSView
    ) -> (
        rect: NSRect,
        baselineOffset: CGFloat,
        glyphCenterOffset: CGFloat
    ) {
        let editor = NSTextView(frame: .zero)
        select(
            withFrame: rect,
            in: controlView,
            editor: editor,
            delegate: nil,
            start: 0,
            length: stringValue.utf16.count
        )
        guard let layoutManager = editor.layoutManager,
              let textContainer = editor.textContainer,
              let font = editor.font,
              !editor.string.isEmpty
        else {
            return (editor.frame, 0, .infinity)
        }
        layoutManager.ensureLayout(for: textContainer)
        guard layoutManager.numberOfGlyphs > 0 else {
            return (editor.frame, 0, .infinity)
        }
        let baselineOffset = editor.frame.minY
            + layoutManager.location(forGlyphAt: 0).y
        let attributedText = NSAttributedString(
            string: editor.string,
            attributes: [.font: font]
        )
        let line = CTLineCreateWithAttributedString(attributedText)
        let inkBounds = CTLineGetBoundsWithOptions(
            line,
            .useGlyphPathBounds
        )
        let glyphCenter = baselineOffset - inkBounds.midY
        return (
            editor.frame,
            baselineOffset,
            abs(glyphCenter - rect.midY)
        )
    }
#endif
}

private final class GridSpacingTextField: NSTextField {
    private static let enabledTextColor =
        NSColor.white.withAlphaComponent(0.88)
    private static let disabledTextColor =
        NSColor.white.withAlphaComponent(0.48)
    private static let focusBorderColor =
        NSColor.controlAccentColor.withAlphaComponent(0.90)
    var onStep: ((Int) -> Void)?
    private var trackingArea: NSTrackingArea?
    private var isHovered = false
    private var isEditing = false

    override var needsPanelToBecomeKey: Bool {
        true
    }

    override var isEnabled: Bool {
        didSet {
            refreshToolbarAppearance()
        }
    }

    func configureToolbarAppearance() {
        isBezeled = false
        drawsBackground = false
        backgroundColor = .clear
        wantsLayer = true
        layer?.cornerRadius = 7
        layer?.cornerCurve = .continuous
        refreshToolbarAppearance()
    }

    func setEditing(_ editing: Bool) {
        isEditing = editing
        refreshToolbarAppearance()
    }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        if let trackingArea {
            removeTrackingArea(trackingArea)
        }
        let trackingArea = NSTrackingArea(
            rect: .zero,
            options: [
                .mouseEnteredAndExited,
                .activeAlways,
                .inVisibleRect,
            ],
            owner: self,
            userInfo: nil
        )
        addTrackingArea(trackingArea)
        self.trackingArea = trackingArea
    }

    override func mouseEntered(with event: NSEvent) {
        isHovered = true
        refreshToolbarAppearance()
    }

    override func mouseExited(with event: NSEvent) {
        isHovered = false
        refreshToolbarAppearance()
    }

    override func keyDown(with event: NSEvent) {
        let delta: Int
        switch event.keyCode {
        case 126:
            delta = 1
        case 125:
            delta = -1
        default:
            super.keyDown(with: event)
            return
        }
        step(by: delta)
    }

    @discardableResult
    func step(
        by delta: Int,
        currentText: String? = nil
    ) -> Int {
        let value = TraceGridPolicy.steppedSpacing(
            current: Int(currentText ?? stringValue),
            delta: delta
        )
        stringValue = String(value)
        onStep?(value)
        return value
    }

    private func refreshToolbarAppearance() {
        textColor = isEnabled
            ? Self.enabledTextColor
            : Self.disabledTextColor
        layer?.backgroundColor = if isEnabled && (isHovered || isEditing) {
            ToolbarActionHoverView.hoverColor.cgColor
        } else {
            NSColor.clear.cgColor
        }
        layer?.borderColor = isEnabled && isEditing
            ? Self.focusBorderColor.cgColor
            : NSColor.clear.cgColor
        layer?.borderWidth = isEnabled && isEditing ? 1 : 0
    }

#if DEBUG
    func setHoveredForTesting(_ hovered: Bool) {
        isHovered = hovered
        refreshToolbarAppearance()
    }

    func setEditingForTesting(_ editing: Bool) {
        setEditing(editing)
    }

    var toolbarBackgroundAlphaForTesting: CGFloat {
        layer?.backgroundColor.flatMap(NSColor.init(cgColor:))?
            .alphaComponent ?? 0
    }

    var toolbarBorderAlphaForTesting: CGFloat {
        layer?.borderColor.flatMap(NSColor.init(cgColor:))?
            .alphaComponent ?? 0
    }

    var toolbarBorderWidthForTesting: CGFloat {
        layer?.borderWidth ?? 0
    }
#endif
}

private final class TraceHoverPointerView: NSView {
    private weak var document: TraceDrawingSession?
    private var normalizedPoint: TracePoint?
    private var displayedPoint: TracePoint?
    private var color = TraceRGBAColor.red
#if DEBUG
    private(set) var renderCount = 0
#endif

    override var isFlipped: Bool {
        true
    }

    override var isOpaque: Bool {
        false
    }

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        alphaValue = TraceProductHoverPolicy.opacity
        wantsLayer = true
        layer?.needsDisplayOnBoundsChange = true
        setAccessibilityElement(false)
    }

    required init?(coder: NSCoder) {
        nil
    }

    override func hitTest(_ point: NSPoint) -> NSView? {
        nil
    }

    override func setFrameSize(_ newSize: NSSize) {
        super.setFrameSize(newSize)
        displayedPoint = normalizedPoint.map(displayPoint(for:))
        needsDisplay = true
    }

    func setDocument(_ document: TraceDrawingSession) {
        self.document = document
        clear()
    }

    func refreshDocument() {
        needsDisplay = true
    }

    func setHover(_ update: TraceHoverUpdate?) {
        guard let update else {
            clear()
            return
        }
        let proposedPoint = displayPoint(for: update.point)
        let pointChanged = TraceProductHoverPolicy.shouldMove(
            from: displayedPoint,
            to: proposedPoint,
            backingScale: Double(window?.backingScaleFactor ?? 2)
        )
        let styleChanged = color != update.color
        guard pointChanged || styleChanged else {
            return
        }
        if pointChanged {
            normalizedPoint = update.point
            displayedPoint = proposedPoint
        }
        color = update.color
        needsDisplay = true
    }

    func clear() {
        guard normalizedPoint != nil else {
            return
        }
        normalizedPoint = nil
        displayedPoint = nil
        needsDisplay = true
    }

    override func draw(_ dirtyRect: NSRect) {
        super.draw(dirtyRect)
#if DEBUG
        renderCount += 1
#endif
        NSGraphicsContext.current?.cgContext.clear(bounds)
        guard let normalizedPoint else {
            return
        }
        let point = displayPoint(for: normalizedPoint)
        let outerDiameter = CGFloat(TraceProductHoverPolicy.diameter)
        let outer = NSRect(
            x: CGFloat(point.x) - outerDiameter / 2,
            y: CGFloat(point.y) - outerDiameter / 2,
            width: outerDiameter,
            height: outerDiameter
        )
        let strokeWidth = CGFloat(TraceProductHoverPolicy.strokeWidth)
        let lens = outer.insetBy(dx: strokeWidth, dy: strokeWidth)

        NSGraphicsContext.saveGraphicsState()
        let shadow = NSShadow()
        shadow.shadowColor = NSColor.black.withAlphaComponent(0.28)
        shadow.shadowBlurRadius = 5
        shadow.shadowOffset = NSSize(width: 0, height: -1)
        shadow.set()
        NSColor.white.withAlphaComponent(0.16).setFill()
        NSBezierPath(ovalIn: outer).fill()
        NSGraphicsContext.restoreGraphicsState()

        drawMagnifiedBackground(
            at: normalizedPoint,
            in: lens
        )

        let innerRim = NSBezierPath(ovalIn: lens.insetBy(dx: 0.5, dy: 0.5))
        innerRim.lineWidth = 1
        NSColor.white.withAlphaComponent(0.72).setStroke()
        innerRim.stroke()

        let outline = NSBezierPath(
            ovalIn: outer.insetBy(
                dx: strokeWidth / 2,
                dy: strokeWidth / 2
            )
        )
        outline.lineWidth = strokeWidth
        NSColor(color).withAlphaComponent(0.96).setStroke()
        outline.stroke()
    }

#if DEBUG
    var displayedNormalizedPointForTesting: TracePoint? {
        normalizedPoint
    }

    var diameterForTesting: Double {
        TraceProductHoverPolicy.diameter
    }
#endif

    private func drawMagnifiedBackground(
        at normalizedPoint: TracePoint,
        in lens: NSRect
    ) {
        guard let document, lens.width > 0, lens.height > 0 else {
            return
        }

        NSGraphicsContext.saveGraphicsState()
        NSBezierPath(ovalIn: lens).addClip()
        if document.manifest.pageKind == .blank {
            NSColor(
                document.manifest.backgroundColor
                    ?? TraceRGBAColor(red: 1, green: 1, blue: 1)
            ).setFill()
            lens.fill()
        } else {
            let viewport = document.manifest.viewport
                ?? TracePageViewport.full
            let sourcePoint = TracePageViewport.unmap(
                normalizedPoint,
                through: viewport
            )
            let localSampleWidth = lens.width
                / CGFloat(TraceProductHoverPolicy.magnification)
                / max(1, bounds.width)
            let localSampleHeight = lens.height
                / CGFloat(TraceProductHoverPolicy.magnification)
                / max(1, bounds.height)
            let sourceSampleWidth =
                Double(localSampleWidth) * viewport.width
            let sourceSampleHeight =
                Double(localSampleHeight) * viewport.height
            let sourceSize = document.screenshot.size
            let proposedSource = NSRect(
                x: CGFloat((
                    sourcePoint.x - sourceSampleWidth / 2
                ) * Double(sourceSize.width)),
                y: CGFloat((
                    1 - sourcePoint.y - sourceSampleHeight / 2
                ) * Double(sourceSize.height)),
                width: CGFloat(
                    sourceSampleWidth * Double(sourceSize.width)
                ),
                height: CGFloat(
                    sourceSampleHeight * Double(sourceSize.height)
                )
            )
            let source = proposedSource.intersection(
                NSRect(origin: .zero, size: sourceSize)
            )
            document.screenshot.draw(
                in: lens,
                from: source,
                operation: .copy,
                fraction: 1,
                respectFlipped: true,
                hints: [.interpolation: NSImageInterpolation.high]
            )
        }
        NSColor.white.withAlphaComponent(0.12).setFill()
        NSBezierPath(ovalIn: lens).fill()
        if let highlight = NSGradient(
            starting: NSColor.white.withAlphaComponent(0.28),
            ending: NSColor.white.withAlphaComponent(0)
        ) {
            highlight.draw(in: lens, angle: -55)
        }
        NSGraphicsContext.restoreGraphicsState()
    }

    private func displayPoint(for point: TracePoint) -> TracePoint {
        TracePoint(
            x: point.x * Double(bounds.width),
            y: point.y * Double(bounds.height)
        )
    }
}

private final class TraceBoardRootView: NSView {
    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        wantsLayer = true
        layer?.cornerRadius = 14
        layer?.masksToBounds = true
    }

    required init?(coder: NSCoder) {
        nil
    }

    func setBackgroundColor(_ color: NSColor) {
        layer?.backgroundColor = color.cgColor
    }

    func setCornerRadius(_ radius: CGFloat) {
        layer?.cornerRadius = max(0, radius)
    }
}

private final class VoiceWaveformView: NSView {
    enum Mode: Equatable {
        case idle
        case recording
        case paused
        case processing
        case ready
        case failed
    }

    private var levels = Array(repeating: CGFloat(0.12), count: 7)
    private var mode = Mode.idle

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        wantsLayer = true
        layerContentsRedrawPolicy = .onSetNeedsDisplay
    }

    required init?(coder: NSCoder) {
        nil
    }

    override var isOpaque: Bool {
        false
    }

    func setMode(_ mode: Mode) {
        guard mode != self.mode else {
            return
        }
        self.mode = mode
        if mode == .idle {
            levels = Array(repeating: 0.12, count: levels.count)
        }
        needsDisplay = true
    }

    func push(level: Float) {
        guard mode == .recording else {
            return
        }
        levels.removeFirst()
        levels.append(
            max(0.12, min(1, CGFloat(level)))
        )
        needsDisplay = true
    }

    override func draw(_ dirtyRect: NSRect) {
        super.draw(dirtyRect)
        NSGraphicsContext.current?.cgContext.clear(bounds)
        displayColor.setFill()
        let barWidth: CGFloat = 3
        let gap: CGFloat = 3
        let contentWidth = CGFloat(levels.count) * barWidth
            + CGFloat(levels.count - 1) * gap
        var x = bounds.midX - contentWidth / 2
        for (index, level) in levels.enumerated() {
            let shaped = mode == .processing
                ? CGFloat([0.35, 0.65, 1, 0.5][index % 4])
                : level
            let height = max(3, shaped * bounds.height)
            NSBezierPath(
                roundedRect: NSRect(
                    x: x,
                    y: bounds.midY - height / 2,
                    width: barWidth,
                    height: height
                ),
                xRadius: barWidth / 2,
                yRadius: barWidth / 2
            ).fill()
            x += barWidth + gap
        }
    }

    private var displayColor: NSColor {
        switch mode {
        case .idle:
            return NSColor.white.withAlphaComponent(0.28)
        case .recording:
            return NSColor.white.withAlphaComponent(0.68)
        case .paused:
            return NSColor.white.withAlphaComponent(0.42)
        case .processing:
            return .systemBlue
        case .ready:
            return .systemGreen
        case .failed:
            return .systemOrange
        }
    }

#if DEBUG
    var colorForTesting: NSColor {
        displayColor
    }
#endif
}

private final class ColorSwatchButton: NSButton {
    let traceColor: TraceRGBAColor
    private var trackingArea: NSTrackingArea?
    private var isHovered = false

    var isSelected = false {
        didSet {
            updateAppearance()
        }
    }

    init(name: String, color: TraceRGBAColor) {
        traceColor = color
        super.init(frame: NSRect(x: 0, y: 0, width: 20, height: 20))
        title = ""
        isBordered = false
        wantsLayer = true
        layer?.cornerRadius = 10
        widthAnchor.constraint(equalToConstant: 20).isActive = true
        heightAnchor.constraint(equalToConstant: 20).isActive = true
        setAccessibilityLabel("\(name) drawing color")
        toolTip = "\(name) drawing color"
        updateAppearance()
    }

    required init?(coder: NSCoder) {
        nil
    }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        if let trackingArea {
            removeTrackingArea(trackingArea)
        }
        let trackingArea = NSTrackingArea(
            rect: .zero,
            options: [
                .mouseEnteredAndExited,
                .activeAlways,
                .inVisibleRect,
            ],
            owner: self,
            userInfo: nil
        )
        addTrackingArea(trackingArea)
        self.trackingArea = trackingArea
    }

    override func mouseEntered(with event: NSEvent) {
        isHovered = true
        updateAppearance()
    }

    override func mouseExited(with event: NSEvent) {
        isHovered = false
        updateAppearance()
    }

#if DEBUG
    func setHoveredForTesting(_ hovered: Bool) {
        isHovered = hovered
        updateAppearance()
    }

    var presentationForTesting: (
        borderWidth: CGFloat,
        borderAlpha: CGFloat,
        isSelected: Bool
    ) {
        (
            borderWidth: layer?.borderWidth ?? 0,
            borderAlpha:
                layer?.borderColor.flatMap(NSColor.init(cgColor:))?
                    .alphaComponent ?? 0,
            isSelected: isSelected
        )
    }
#endif

    private func updateAppearance() {
        let highlighted = isSelected || isHovered
        layer?.backgroundColor = NSColor(traceColor).cgColor
        layer?.borderWidth = highlighted ? 2.5 : 1
        layer?.borderColor = (
            highlighted
                ? NSColor.white
                : NSColor.white.withAlphaComponent(0.30)
        ).cgColor
    }
}

extension NSColor {
    convenience init(_ color: TraceRGBAColor) {
        self.init(
            calibratedRed: color.red,
            green: color.green,
            blue: color.blue,
            alpha: color.alpha
        )
    }
}
