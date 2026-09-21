import AppKit
import NeoInput
import TraceCalibration
import TraceMetrics
import TraceStrokeProcessing

/*
 THESIS: A raw pen trace should fill the window; measurement supports it rather
 than turning the lab into a dashboard.
 OWN-WORLD: Native macOS chrome, a white paper field, black received samples,
 and system semantic colors only for connection, gaps, and errors.
 STORY: Connect, calibrate once, draw, and immediately read real latency,
 cadence, pressure, recognition, and discontinuity.
 FIRST VIEWPORT: One compact status bar above a dominant calibrated paper
 canvas, with Recalibrate and Erase at the trailing edge.
 FORM: Simple operator canvas chosen by the user; the launch preset is
 Predict + Velocity + Smooth, while Raw stays explicit, reversible, and
 available as ground truth.
 */
final class LabViewController: NSViewController {
    private enum StrategyMenu {
        case reconstruction
        case prediction
    }

    #if DEBUG
    var rendererTitlesForTesting: [String] {
        rendererControl.itemArray.map(\.title)
    }

    var selectedRendererTitleForTesting: String? {
        rendererControl.titleOfSelectedItem
    }

    var connectionTextForTesting: String {
        connectionLabel.stringValue
    }

    var recalibrateEnabledForTesting: Bool {
        calibrateButton.isEnabled
    }

    var processingModeEnabledForTesting: Bool {
        modeControl.isEnabled
    }

    var strategyEnabledForTesting: Bool {
        strategyControl.isEnabled
    }

    var anchorsEnabledForTesting: Bool {
        anchorsControl.isEnabled
    }

    var processingControlStateForTesting: String {
        "mode=\(modeControl.isEnabled) "
            + "strategy=\(strategyControl.isEnabled) "
            + "anchors=\(anchorsControl.isEnabled)"
    }

    var tracePresentationUpdateCountForTesting: Int {
        canvasView.presentationUpdateCountForTesting
    }

    var statusControlsFitForTesting: Bool {
        statusControlFramesForTesting.allSatisfy { _, frame in
            frame.minX.isFinite
                && frame.maxX.isFinite
                && frame.minY.isFinite
                && frame.maxY.isFinite
                && frame.minX >= 0
                && frame.maxX <= view.bounds.width
        }
    }

    var statusLayoutDescriptionForTesting: String {
        statusControlFramesForTesting.map { name, frame in
            "\(name)=\(NSStringFromRect(frame))"
        }.joined(separator: " ")
    }

    var rendererDrawingSizesForTesting: [LabRendererMode: NSSize] {
        var sizes: [LabRendererMode: NSSize] = [
            .trace: canvasView.drawingRectForTesting.size,
            .tldraw: tldrawSurface.drawingFrameForTesting.size,
        ]
#if canImport(PaperKit)
        if #available(macOS 26.0, *),
           let surface = paperKitSurface as? PaperKitRendererSurface
        {
            sizes[.paperKit] = surface.drawingFrameForTesting.size
        }
#endif
        return sizes
    }

    var rendererLayoutDescriptionForTesting: String {
        rendererDrawingSizesForTesting.map { mode, size in
            "\(mode.rawValue)=\(NSStringFromSize(size))"
        }.sorted().joined(separator: " ")
    }

    private var statusControlFramesForTesting: [(
        String,
        NSRect
    )] {
        [
            ("connection", connectionLabel),
            ("page", pageLabel),
            ("metrics", metricsLabel),
            ("renderer", rendererControl),
            ("mode", modeControl),
            ("strategy", strategyControl),
            ("anchors", anchorsControl),
            ("recalibrate", calibrateButton),
            ("erase", eraseButton),
        ].map { name, control in
            (name, control.convert(control.bounds, to: view))
        }
    }

    func selectRendererForTesting(_ mode: LabRendererMode) {
        rendererControl.selectItem(withTitle: mode.title)
        changeRenderer()
    }

    func selectProcessingModeForTesting(_ segment: Int) {
        modeControl.selectedSegment = segment
        changeProcessingMode()
    }

    func selectStrategyForTesting(_ index: Int) {
        strategyControl.selectItem(at: index)
        changeStrategy()
    }

    func refreshStatusForTesting() {
        refreshStatus()
    }
    #endif

    private let model: LabModel
    private let canvasView = RawCanvasView()
    private let paperKitSurface: LabRendererSurface
    private let tldrawSurface = TldrawRendererSurface()
    private let rendererContainer = NSView()
    private let hoverCursorView = HoverCursorView()
    private let connectionLabel = NSTextField(labelWithString: "● Waiting")
    private let pageLabel = NSTextField(labelWithString: "Page --")
    private let metricsLabel = NSTextField(labelWithString: "No samples")
    private let rendererControl = NSPopUpButton(
        frame: .zero,
        pullsDown: false
    )
    private let modeControl = NSSegmentedControl(
        labels: ["Raw", "Fill Gaps", "Predict"],
        trackingMode: .selectOne,
        target: nil,
        action: nil
    )
    private let strategyControl = NSPopUpButton(
        frame: .zero,
        pullsDown: false
    )
    private let anchorsControl = NSButton(
        checkboxWithTitle: "Anchors",
        target: nil,
        action: nil
    )
    private let eraseButton = NSButton(title: "Erase", target: nil, action: nil)
    private let calibrateButton = NSButton(
        title: "Recalibrate",
        target: nil,
        action: nil
    )
    private var updateTimer: Timer?
    private var hasStarted = false
    private var strategyMenu = StrategyMenu.reconstruction
    private var lastRendererPresentation: LabRendererPresentation?
    private var rendererSurfaces: [LabRendererMode: LabRendererSurface] {
        [
            .trace: canvasView,
            .paperKit: paperKitSurface,
            .tldraw: tldrawSurface,
        ]
    }

    init(model: LabModel, showsAnchors: Bool = false) {
        self.model = model
#if canImport(PaperKit)
        if #available(macOS 26.0, *) {
            paperKitSurface = PaperKitRendererSurface()
        } else {
            paperKitSurface = UnavailableLabRendererSurface(
                title: "PaperKit",
                reason: "PaperKit requires macOS 26 or later."
            )
        }
#else
        paperKitSurface = UnavailableLabRendererSurface(
            title: "PaperKit",
            reason: "PaperKit requires the macOS 26 SDK and runtime."
        )
#endif
        anchorsControl.state = showsAnchors ? .on : .off
        canvasView.showsAnchors = showsAnchors
        super.init(nibName: nil, bundle: nil)
    }

    required init?(coder: NSCoder) {
        nil
    }

    override func loadView() {
        let root = NSView()

        let statusBar = NSView()
        statusBar.translatesAutoresizingMaskIntoConstraints = false
        statusBar.wantsLayer = true
        statusBar.layer?.backgroundColor = NSColor.controlBackgroundColor.cgColor

        configureLabel(connectionLabel, weight: .medium)
        configureLabel(pageLabel, weight: .regular)
        metricsLabel.font = .monospacedDigitSystemFont(
            ofSize: 11,
            weight: .regular
        )
        metricsLabel.textColor = .secondaryLabelColor
        metricsLabel.lineBreakMode = .byTruncatingTail
        metricsLabel.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)

        rendererControl.addItems(
            withTitles: LabRendererMode.allCases.map(\.title)
        )
        rendererControl.target = self
        rendererControl.action = #selector(changeRenderer)
        rendererControl.controlSize = .small
        rendererControl.toolTip = "Drawing renderer"
        rendererControl.setAccessibilityLabel("Drawing renderer")

        eraseButton.target = self
        eraseButton.action = #selector(eraseDrawing)
        eraseButton.controlSize = .small
        eraseButton.toolTip = "Erase the drawing while keeping measurements"
        eraseButton.setAccessibilityLabel("Erase drawing")

        calibrateButton.target = self
        calibrateButton.action = #selector(recalibrate)
        calibrateButton.controlSize = .small
        calibrateButton.toolTip = "Replace the saved four-corner paper calibration"
        calibrateButton.setAccessibilityLabel("Recalibrate paper")

        modeControl.target = self
        modeControl.action = #selector(changeProcessingMode)
        modeControl.controlSize = .small
        modeControl.selectedSegment = 0
        modeControl.setAccessibilityLabel("Stroke processing mode")

        strategyControl.addItems(
            withTitles: ["Linear", "Arc", "Bézier", "Smooth"]
        )
        strategyControl.target = self
        strategyControl.action = #selector(changeStrategy)
        strategyControl.controlSize = .small
        strategyControl.toolTip = "Stroke reconstruction strategy"
        strategyControl.setAccessibilityLabel(
            "Stroke reconstruction strategy"
        )
        anchorsControl.target = self
        anchorsControl.action = #selector(changeAnchorVisibility)
        anchorsControl.controlSize = .small
        anchorsControl.toolTip =
            "Overlay measured and generated control points"
        anchorsControl.setAccessibilityLabel(
            "Show stroke anchors"
        )
        for control in [
            rendererControl,
            modeControl,
            strategyControl,
            anchorsControl,
            calibrateButton,
            eraseButton,
        ] {
            control.setContentCompressionResistancePriority(
                .required,
                for: .horizontal
            )
        }

        let stack = NSStackView(views: [
            connectionLabel,
            separator(),
            pageLabel,
            separator(),
            metricsLabel,
            rendererControl,
            modeControl,
            strategyControl,
            anchorsControl,
            calibrateButton,
            eraseButton,
        ])
        stack.translatesAutoresizingMaskIntoConstraints = false
        stack.orientation = .horizontal
        stack.alignment = .centerY
        stack.spacing = 8
        statusBar.addSubview(stack)

        rendererContainer.translatesAutoresizingMaskIntoConstraints = false
        hoverCursorView.translatesAutoresizingMaskIntoConstraints = false
        root.addSubview(statusBar)
        root.addSubview(rendererContainer)
        root.addSubview(hoverCursorView)

        for surface in rendererSurfaces.values {
            for child in surface.childViewControllers {
                addChild(child)
            }
            surface.view.translatesAutoresizingMaskIntoConstraints = false
            rendererContainer.addSubview(surface.view)
            NSLayoutConstraint.activate([
                surface.view.topAnchor.constraint(
                    equalTo: rendererContainer.topAnchor
                ),
                surface.view.leadingAnchor.constraint(
                    equalTo: rendererContainer.leadingAnchor
                ),
                surface.view.trailingAnchor.constraint(
                    equalTo: rendererContainer.trailingAnchor
                ),
                surface.view.bottomAnchor.constraint(
                    equalTo: rendererContainer.bottomAnchor
                ),
            ])
        }

        NSLayoutConstraint.activate([
            statusBar.topAnchor.constraint(equalTo: root.topAnchor),
            statusBar.leadingAnchor.constraint(equalTo: root.leadingAnchor),
            statusBar.trailingAnchor.constraint(equalTo: root.trailingAnchor),
            statusBar.heightAnchor.constraint(
                equalToConstant: LabPaperLayout.statusBarHeight
            ),

            stack.leadingAnchor.constraint(equalTo: statusBar.leadingAnchor, constant: 14),
            stack.trailingAnchor.constraint(equalTo: statusBar.trailingAnchor, constant: -12),
            stack.centerYAnchor.constraint(equalTo: statusBar.centerYAnchor),

            rendererContainer.topAnchor.constraint(
                equalTo: statusBar.bottomAnchor
            ),
            rendererContainer.leadingAnchor.constraint(
                equalTo: root.leadingAnchor
            ),
            rendererContainer.trailingAnchor.constraint(
                equalTo: root.trailingAnchor
            ),
            rendererContainer.bottomAnchor.constraint(
                equalTo: root.bottomAnchor
            ),
            rendererContainer.widthAnchor.constraint(
                greaterThanOrEqualToConstant:
                    LabPaperLayout.minimumRendererSize.width
            ),
            rendererContainer.heightAnchor.constraint(
                greaterThanOrEqualToConstant:
                    LabPaperLayout.minimumRendererSize.height
            ),
            hoverCursorView.topAnchor.constraint(
                equalTo: rendererContainer.topAnchor
            ),
            hoverCursorView.leadingAnchor.constraint(
                equalTo: rendererContainer.leadingAnchor
            ),
            hoverCursorView.trailingAnchor.constraint(
                equalTo: rendererContainer.trailingAnchor
            ),
            hoverCursorView.bottomAnchor.constraint(
                equalTo: rendererContainer.bottomAnchor
            ),
        ])

        view = root
        bindModel()
    }

    override func viewDidAppear() {
        super.viewDidAppear()
        guard !hasStarted else {
            return
        }
        hasStarted = true
        model.start()
        updateTimer = Timer.scheduledTimer(
            timeInterval: 0.1,
            target: self,
            selector: #selector(refreshStatus),
            userInfo: nil,
            repeats: true
        )
        refreshStatus()
    }

    override func viewWillDisappear() {
        super.viewWillDisappear()
        updateTimer?.invalidate()
        updateTimer = nil
    }

    private func bindModel() {
        model.onRenderUpdate = { [weak self] update in
            guard let self else {
                return
            }
            self.rendererSurfaces[
                self.model.snapshot.rendererMode
            ]?.apply(update)
        }
        model.onHoverUpdate = { [weak self] sample in
            self?.hoverCursorView.setHover(sample)
        }
        model.onCanvasReset = { [weak self] in
            self?.rendererSurfaces.values.forEach { $0.clear() }
            self?.hoverCursorView.clear()
        }
        model.onStateChange = { [weak self] in
            self?.refreshStatus()
        }
        model.onReplayFinished = { [weak self] in
            self?.finishReplayWhenRendererDrains()
        }
        canvasView.onSamplesRendered = { [weak self] samples, uptime in
            self?.model.recordRendered(samples, at: uptime)
        }
        paperKitSurface.onSamplesRendered = {
            [weak self] samples, uptime in
            self?.model.recordRendered(samples, at: uptime)
        }
        tldrawSurface.onSamplesRendered = {
            [weak self] samples, uptime in
            self?.model.recordRendered(samples, at: uptime)
        }
        canvasView.onRefinementRendered = { [weak self] measurement in
            self?.model.recordRefinementRendered(measurement)
        }
        canvasView.onCanvasDrawn = { [weak self] measurement in
            self?.model.recordCanvasDrawn(measurement)
        }
        canvasView.onMouseStrokeEvent = { [weak self] event in
            self?.model.handleMouseStroke(event)
        }
        tldrawSurface.onMouseStrokeEvent = { [weak self] event in
            self?.model.handleMouseStroke(event)
        }
        canvasView.mouseDrawingEnabled = true
    }

    private func finishReplayWhenRendererDrains() {
        Task { @MainActor [weak self] in
            guard let self else {
                return
            }
            let deadline =
                DispatchTime.now().uptimeNanoseconds + 10_000_000_000
            while let surface =
                    rendererSurfaces[model.snapshot.rendererMode],
                  (
                      !surface.isReadyForInput
                          || surface.pendingRenderWorkCount > 0
                  ),
                  DispatchTime.now().uptimeNanoseconds < deadline
            {
                try? await Task.sleep(nanoseconds: 50_000_000)
            }
            NSApp.terminate(nil)
        }
    }

    @objc private func eraseDrawing() {
        model.eraseDrawing()
    }

    @objc private func recalibrate() {
        model.recalibrate()
    }

    @objc private func changeProcessingMode() {
        guard processingControlsAvailable(for: model.snapshot) else {
            refreshStatus()
            return
        }
        let mode: StrokeRenderMode
        switch modeControl.selectedSegment {
        case 1:
            mode = .interpolate
        case 2:
            mode = .predict
        default:
            mode = .raw
        }
        model.setProcessingMode(mode)
    }

    @objc private func changeRenderer() {
        guard let title = rendererControl.titleOfSelectedItem,
              let mode = LabRendererMode.allCases.first(where: {
                  $0.title == title
              })
        else {
            return
        }
        model.setRendererMode(mode)
    }

    @objc private func changeStrategy() {
        let snapshot = model.snapshot
        guard processingControlsAvailable(for: snapshot) else {
            refreshStatus()
            return
        }
        if snapshot.processingMode == .predict {
            let algorithm: PredictionAlgorithm
            switch strategyControl.indexOfSelectedItem {
            case 1:
                algorithm = .velocity
            case 2:
                algorithm = .curve
            default:
                algorithm = .safe
            }
            model.setPredictionAlgorithm(algorithm)
            return
        }

        let interpolation: GapInterpolationAlgorithm
        let refinement: StrokeRefinementAlgorithm
        switch strategyControl.indexOfSelectedItem {
        case 1:
            interpolation = .circularArc
            refinement = .none
        case 2:
            interpolation = .cubicBezier
            refinement = .none
        case 3:
            interpolation = .circularArc
            refinement = .smoothPath
        default:
            interpolation = .linear
            refinement = .none
        }
        model.setStrokeReconstruction(
            interpolationAlgorithm: interpolation,
            refinementAlgorithm: refinement
        )
    }

    @objc private func changeAnchorVisibility() {
        canvasView.showsAnchors = anchorsControl.state == .on
    }

    @objc private func refreshStatus() {
        let snapshot = model.snapshot
        let presentation = LabRendererPresentation(
            calibration: snapshot.calibration,
            calibrationActive:
                snapshot.penInputEnabled && snapshot.calibrationActive,
            pagePriming:
                snapshot.penInputEnabled
                    && snapshot.pagePrimingMessage != nil,
            calibrationCorner: snapshot.calibrationCorner,
            message:
                snapshot.calibrationMessage
                    ?? snapshot.pagePrimingMessage
        )
        if presentation != lastRendererPresentation {
            lastRendererPresentation = presentation
            for surface in rendererSurfaces.values {
                surface.updatePresentation(presentation)
            }
        }
        for (mode, surface) in rendererSurfaces {
            if mode == snapshot.rendererMode {
                surface.activate()
            } else {
                surface.deactivate()
            }
        }
        rendererControl.selectItem(
            withTitle: snapshot.rendererMode.title
        )
        hoverCursorView.setCalibration(snapshot.calibration)
        hoverCursorView.isHidden = snapshot.rendererMode != .trace
        if snapshot.calibrationActive
            || !snapshot.pagePrimed
            || snapshot.rendererMode != .trace
        {
            hoverCursorView.clear()
        }
        calibrateButton.isEnabled = snapshot.penInputEnabled
            && !snapshot.isReplay
            && !snapshot.calibrationActive
            && !snapshot.isStrokeActive
        eraseButton.isEnabled = (
            !snapshot.penInputEnabled || !snapshot.calibrationActive
        ) && !snapshot.isStrokeActive
        rendererControl.isEnabled = !snapshot.isStrokeActive
        let processingAvailable =
            processingControlsAvailable(for: snapshot)
        modeControl.isEnabled = processingAvailable
            && snapshot.inputReady
            && !snapshot.isStrokeActive
        modeControl.toolTip = processingScopeToolTip(snapshot)
        modeControl.selectedSegment = segment(for: snapshot.processingMode)
        configureStrategyMenu(for: snapshot)
        strategyControl.isEnabled = processingAvailable
            && snapshot.inputReady
            && snapshot.processingMode != .raw
            && !snapshot.isStrokeActive
        anchorsControl.isEnabled = snapshot.rendererMode == .trace
            && !(snapshot.penInputEnabled && snapshot.calibrationActive)
            && !snapshot.isStrokeActive
        if snapshot.processingMode == .predict {
            strategyControl.selectItem(
                at: predictionIndex(for: snapshot.predictionAlgorithm)
            )
            strategyControl.toolTip = processingAvailable
                ? predictionToolTip(snapshot.predictionAlgorithm)
                : processingScopeToolTip(snapshot)
        } else {
            strategyControl.selectItem(
                at: reconstructionIndex(
                    interpolationAlgorithm:
                        snapshot.interpolationAlgorithm,
                    refinementAlgorithm: snapshot.refinementAlgorithm
                )
            )
            strategyControl.toolTip = processingAvailable
                ? "Choose how known optical gaps are reconstructed."
                : processingScopeToolTip(snapshot)
        }

        if let reason = rendererSurfaces[snapshot.rendererMode]?
            .unavailableReason
        {
            connectionLabel.stringValue = "● Renderer unavailable"
            connectionLabel.textColor = .systemRed
            pageLabel.stringValue = snapshot.rendererMode.title
            metricsLabel.stringValue = reason
            metricsLabel.textColor = .systemRed
            return
        }

        if !snapshot.penInputEnabled {
            connectionLabel.stringValue = connectionText(snapshot)
            connectionLabel.textColor = connectionColor(snapshot)
            pageLabel.stringValue = snapshot.rendererMode.title
            metricsLabel.stringValue = snapshot.lastError
                ?? mouseReadyText(snapshot)
            metricsLabel.textColor = snapshot.lastError == nil
                ? .secondaryLabelColor
                : .systemRed
            return
        }

        if snapshot.calibrationActive {
            connectionLabel.stringValue = "● Calibrating"
            connectionLabel.textColor = .systemOrange
            if snapshot.calibrationAwaitingPageRegistration {
                pageLabel.stringValue = "Register page"
            } else if let corner = snapshot.calibrationCorner {
                pageLabel.stringValue = "Corner \(corner.rawValue + 1)/4"
            }
            metricsLabel.stringValue = snapshot.calibrationMessage ?? "Tap paper corner"
            return
        }

        if !snapshot.pagePrimed {
            connectionLabel.stringValue = "● Prime paper"
            connectionLabel.textColor = snapshot.lastError == nil
                ? .systemOrange
                : .systemRed
            pageLabel.stringValue = "Page --"
            metricsLabel.stringValue = snapshot.lastError
                ?? snapshot.pagePrimingMessage
                ?? "Tap once anywhere on the paper."
            metricsLabel.textColor = snapshot.lastError == nil
                ? .secondaryLabelColor
                : .systemRed
            return
        }

        connectionLabel.stringValue = connectionText(snapshot)
        connectionLabel.textColor = connectionColor(snapshot)
        pageLabel.stringValue = pageText(snapshot.page)
        metricsLabel.stringValue = snapshot.lastError ?? metricsText(snapshot)
        metricsLabel.textColor = snapshot.lastError == nil
            ? .secondaryLabelColor
            : .systemRed
        let clockOffset = number(
            snapshot.performance.clockOffsetEstimateMilliseconds,
            suffix: " ms"
        )
        let completion = distribution(snapshot.performance.completionLatency)
        metricsLabel.toolTip = "Start Δ is clock-corrected pen-down transport. "
            + "End Δ is clock-corrected pen-up transport: \(completion) ms. "
            + "Raw pen clock delta: \(clockOffset). "
            + "Session log: \(snapshot.logFileURL.path)"
    }

    private func configureLabel(
        _ label: NSTextField,
        weight: NSFont.Weight
    ) {
        label.font = .systemFont(ofSize: 12, weight: weight)
        label.textColor = .secondaryLabelColor
        label.setContentCompressionResistancePriority(.required, for: .horizontal)
    }

    private func separator() -> NSView {
        let view = NSBox()
        view.boxType = .separator
        view.translatesAutoresizingMaskIntoConstraints = false
        view.widthAnchor.constraint(equalToConstant: 1).isActive = true
        view.heightAnchor.constraint(equalToConstant: 18).isActive = true
        return view
    }

    private func connectionText(_ snapshot: LabSnapshot) -> String {
        if snapshot.penInputReady {
            return "● Ready"
        }
        if !snapshot.penInputEnabled {
            return "● Mouse ready"
        }
        switch snapshot.connectionState {
        case .discovering:
            return "● Discovering"
        case .connecting, .reconnecting:
            return "● Connecting"
        case .connected:
            return "● Preparing"
        case .failed:
            return "● Error"
        case .disconnected:
            return "● Disconnected"
        default:
            return "● Waiting"
        }
    }

    private func connectionColor(_ snapshot: LabSnapshot) -> NSColor {
        if snapshot.penInputReady || !snapshot.penInputEnabled {
            return .systemGreen
        }
        switch snapshot.connectionState {
        case .failed, .disconnected:
            return .systemRed
        case .connecting, .discovering, .reconnecting:
            return .systemOrange
        default:
            return .secondaryLabelColor
        }
    }

    private func pageText(_ page: PenPageID?) -> String {
        guard let page else {
            return "Page --"
        }
        return "\(page.section)/\(page.owner)/\(page.note)/\(page.page)"
    }

    private func metricsText(_ snapshot: LabSnapshot) -> String {
        let metrics = snapshot.performance
        let battery = snapshot.batteryPercent.map { "\($0)%" } ?? "--"
        return [
            "Renderer \(snapshot.rendererMode.title)",
            "Start Δ \(distribution(metrics.startLatency)) ms",
            "Draw \(distribution(metrics.renderLatency)) ms",
            "Proc \(processingText(metrics.processingLatency))",
            "Rate \(number(metrics.effectiveSampleRateHz, suffix: " Hz"))",
            "Burst \(metrics.maximumFramesPerBatch.map(String.init) ?? "--")",
            "Gaps \(metrics.gapCount)",
            "Errors \(metrics.opticalErrorCount)",
            "Recognition \(percent(metrics.latestRecognitionRate))",
            "Pressure \(percent(snapshot.latestPressure))",
            "Hover \(hoverText(snapshot.hoverEnabled))",
            "Battery \(battery)",
        ].joined(separator: "   ")
    }

    private func distribution(_ value: MetricDistribution) -> String {
        "p50 \(number(value.p50)) / p95 \(number(value.p95))"
    }

    private func number(_ value: Double?, suffix: String = "") -> String {
        guard let value else {
            return "--\(suffix)"
        }
        return String(format: "%.1f%@", value, suffix)
    }

    private func percent(_ value: Double?) -> String {
        guard let value else {
            return "--"
        }
        return String(format: "%.0f%%", value * 100)
    }

    private func hoverText(_ enabled: Bool?) -> String {
        switch enabled {
        case true:
            return "On"
        case false:
            return "Off"
        case nil:
            return "--"
        }
    }

    private func processingText(_ distribution: MetricDistribution) -> String {
        guard let p95 = distribution.p95 else {
            return "--"
        }
        return String(format: "p95 %.1f µs", p95 * 1_000)
    }

    private func segment(for mode: StrokeRenderMode) -> Int {
        switch mode {
        case .raw:
            return 0
        case .interpolate:
            return 1
        case .predict:
            return 2
        }
    }

    private func reconstructionIndex(
        interpolationAlgorithm: GapInterpolationAlgorithm,
        refinementAlgorithm: StrokeRefinementAlgorithm
    ) -> Int {
        if refinementAlgorithm == .smoothPath {
            return 3
        }
        switch interpolationAlgorithm {
        case .linear:
            return 0
        case .circularArc:
            return 1
        case .cubicBezier:
            return 2
        }
    }

    private func predictionIndex(
        for algorithm: PredictionAlgorithm
    ) -> Int {
        switch algorithm {
        case .safe:
            return 0
        case .velocity:
            return 1
        case .curve:
            return 2
        }
    }

    private func predictionToolTip(
        _ algorithm: PredictionAlgorithm
    ) -> String {
        switch algorithm {
        case .safe:
            return "Three-point tail after three stable samples; direction "
                + "and speed gated, damped by 0.82, max 0.35 Ncode per step."
        case .velocity:
            return "Three-point tail after two samples; repeats the latest "
                + "displacement, max 0.35 Ncode per step."
        case .curve:
            return "Three-point tail after three samples; continues the "
                + "observed turn up to 45° per step with 0.9 damping."
        }
    }

    private func processingControlsAvailable(
        for snapshot: LabSnapshot
    ) -> Bool {
        guard rendererSurfaces[snapshot.rendererMode]?
            .unavailableReason == nil
        else {
            return false
        }
        return snapshot.rendererMode.supportsTraceProcessing(
            penInputReady: snapshot.penInputReady,
            isReplay: snapshot.isReplay
        )
    }

    private func processingScopeToolTip(
        _ snapshot: LabSnapshot
    ) -> String {
        if snapshot.rendererMode == .tldraw {
            return "Predict adds the selected Trace trajectory tail to Neo "
                + "and tldraw Draw-tool mouse input. Fill Gaps affects Neo "
                + "only; the native tldraw mouse stroke remains unchanged."
        }
        if snapshot.rendererMode.supportsTraceProcessingForMouse {
            return "Applies Raw, Fill Gaps, and Predict to mouse, Neo, "
                + "and replay input."
        }
        if snapshot.isReplay {
            return "Applies Trace processing to replayed input. Native "
                + "\(snapshot.rendererMode.title) mouse tools are unchanged."
        }
        if snapshot.penInputReady {
            return "Applies Trace processing to injected Neo input. Native "
                + "\(snapshot.rendererMode.title) mouse tools are unchanged."
        }
        return "Native \(snapshot.rendererMode.title) mouse tools use their "
            + "own engine. Connect the Neo pen to enable Trace processing."
    }

    private func mouseReadyText(_ snapshot: LabSnapshot) -> String {
        if snapshot.rendererMode == .tldraw {
            return "tldraw mouse ready · Predict adds a trajectory tail "
                + "to the freehand Draw tool."
        }
        guard !snapshot.rendererMode.supportsTraceProcessingForMouse else {
            return "Mouse ready · Connect the pen for calibrated input."
        }
        return "\(snapshot.rendererMode.title) mouse tools ready · Connect "
            + "the pen for Raw, Fill Gaps, and Predict."
    }

    private func configureStrategyMenu(_ menu: StrategyMenu) {
        guard menu != strategyMenu else {
            return
        }
        strategyMenu = menu
        strategyControl.removeAllItems()
        switch menu {
        case .reconstruction:
            strategyControl.addItems(
                withTitles: ["Linear", "Arc", "Bézier", "Smooth"]
            )
            strategyControl.toolTip = "Stroke reconstruction strategy"
            strategyControl.setAccessibilityLabel(
                "Stroke reconstruction strategy"
            )
        case .prediction:
            strategyControl.addItems(
                withTitles: ["Safe", "Velocity", "Curve"]
            )
            strategyControl.toolTip = "Trajectory prediction algorithm"
            strategyControl.setAccessibilityLabel(
                "Trajectory prediction algorithm"
            )
        }
    }

    private func configureStrategyMenu(for snapshot: LabSnapshot) {
        configureStrategyMenu(
            snapshot.processingMode == .predict
                ? .prediction
                : .reconstruction
        )
    }
}
