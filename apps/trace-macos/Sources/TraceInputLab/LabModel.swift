import Foundation
import NeoInput
import NeoTransport
import TraceCalibration
import TraceGeometry
import TraceLabReplay
import TraceMetrics
import TraceStrokeProcessing

struct LabSnapshot {
    let connectionState: PenConnectionState
    let penInputEnabled: Bool
    let pagePrimed: Bool
    let inputReady: Bool
    let penInputReady: Bool
    let deviceName: String?
    let page: PenPageID?
    let batteryPercent: UInt8?
    let isCharging: Bool
    let hoverEnabled: Bool?
    let latestPressure: Double?
    let processingMode: StrokeRenderMode
    let interpolationAlgorithm: GapInterpolationAlgorithm
    let refinementAlgorithm: StrokeRefinementAlgorithm
    let predictionAlgorithm: PredictionAlgorithm
    let rendererMode: LabRendererMode
    let isStrokeActive: Bool
    let isReplay: Bool
    let performance: PerformanceSnapshot
    let calibration: CalibratedSurface?
    let calibrationActive: Bool
    let calibrationAwaitingPageRegistration: Bool
    let calibrationCorner: CalibrationCorner?
    let calibrationMessage: String?
    let pagePrimingMessage: String?
    let lastError: String?
    let logFileURL: URL
}

final class LabModel {
    private static let hoverCursorIdleSeconds = 0.5

    var onRenderUpdate: ((LabRendererUpdate) -> Void)?
    var onHoverUpdate: ((RawHoverSample?) -> Void)?
    var onCanvasReset: (() -> Void)?
    var onStateChange: (() -> Void)?
    var onReplayFinished: (() -> Void)?

    var snapshot: LabSnapshot {
        let penInputReady = inputEnabled
            && calibratedSurface != nil
            && calibrationSession == nil
            && pagePrimed
        return LabSnapshot(
            connectionState: connectionState,
            penInputEnabled: inputEnabled,
            pagePrimed: pagePrimed,
            inputReady: true,
            penInputReady: penInputReady,
            deviceName: deviceName,
            page: currentPage,
            batteryPercent: batteryPercent,
            isCharging: isCharging,
            hoverEnabled: hoverEnabled,
            latestPressure: latestPressure,
            processingMode: processingMode,
            interpolationAlgorithm: interpolationAlgorithm,
            refinementAlgorithm: refinementAlgorithm,
            predictionAlgorithm: predictionAlgorithm,
            rendererMode: rendererMode,
            isStrokeActive: isStrokeActive,
            isReplay: replayURL != nil,
            performance: performance.snapshot,
            calibration: calibratedSurface,
            calibrationActive: calibrationSession != nil,
            calibrationAwaitingPageRegistration:
                calibrationSession?.isAwaitingPageRegistration == true,
            calibrationCorner: calibrationSession?.currentCorner,
            calibrationMessage: calibrationMessage,
            pagePrimingMessage: inputEnabled
                && calibrationSession == nil
                && calibratedSurface != nil
                && !pagePrimed
                ? "Tap once anywhere on the paper to prime its Ncode page."
                : nil,
            lastError: lastError,
            logFileURL: recorder.fileURL
        )
    }

    private let transport: any NeoTransport
    private let normalizer = NeoInputNormalizer()
    private let performance = TracePerformanceMonitor()
    private let strokeProcessor = LiveStrokeProcessor(mode: .raw)
    private let mouseStrokeProcessor = LiveStrokeProcessor(mode: .raw)
    private let calibrationStore: LocalCalibrationStore
    private let recorder: LabSessionRecorder
    private let replayURL: URL?
    private let replaySpeed: Double
    private let quitAfterReplay: Bool

    private var didRequestConnection = false
    private var clockSyncRequested = false
    private var clockSynchronized = false
    private var didEnableInput = false
    private var inputEnabled = false
    private var pagePrimed = false
    private var primingStrokeID: UInt64?
    private var connectionState: PenConnectionState = .idle
    private var deviceName: String?
    private var currentPage: PenPageID?
    private var batteryPercent: UInt8?
    private var isCharging = false
    private var hoverEnabled: Bool?
    private var latestPressure: Double?
    private var processingMode: StrokeRenderMode
    private var interpolationAlgorithm: GapInterpolationAlgorithm
    private var refinementAlgorithm: StrokeRefinementAlgorithm
    private var predictionAlgorithm: PredictionAlgorithm
    private var rendererMode: LabRendererMode
    private var isStrokeActive = false
    private var calibratedSurface: CalibratedSurface?
    private var calibrationSession: SurfaceCalibrationSession?
    private var calibrationMessage: String?
    private var lastError: String?
    private var isStarted = false
    private var currentNotificationBatch: NeoNotificationBatch?
    private var hoverGeneration: UInt64 = 0
    private var hoverClearWorkItem: DispatchWorkItem?
    private var activeMouseStrokeID: UInt64?
    private var nextMouseStrokeID = LabMouseIdentifier.base
    private var nextMouseSampleID = LabMouseIdentifier.base
    private var mouseSampleIndex = 0
    private var previousMouseSample: LabMouseSample?
    private var replayMouseLastSample: LabMouseSample?
    private var mouseStrokeStartedAt: LabMouseSample?

    init(
        configuration: LabConfiguration,
        transport: any NeoTransport = CoreBluetoothNeoTransport()
    ) throws {
        self.transport = transport
        replayURL = configuration.replayURL
        replaySpeed = configuration.replaySpeed
        quitAfterReplay = configuration.quitAfterReplay
        processingMode = configuration.processingMode
        interpolationAlgorithm = configuration.interpolationAlgorithm
        refinementAlgorithm = configuration.refinementAlgorithm
        predictionAlgorithm = configuration.predictionAlgorithm
        rendererMode = configuration.rendererMode
        strokeProcessor.mode = configuration.processingMode
        strokeProcessor.interpolationAlgorithm =
            configuration.interpolationAlgorithm
        strokeProcessor.refinementAlgorithm =
            configuration.refinementAlgorithm
        strokeProcessor.predictionAlgorithm =
            configuration.predictionAlgorithm
        mouseStrokeProcessor.mode = configuration.processingMode
        mouseStrokeProcessor.interpolationAlgorithm =
            configuration.interpolationAlgorithm
        mouseStrokeProcessor.refinementAlgorithm =
            configuration.refinementAlgorithm
        mouseStrokeProcessor.predictionAlgorithm =
            configuration.predictionAlgorithm
        recorder = try LabSessionRecorder(
            directory: configuration.logDirectory,
            implementationID: configuration.implementationID,
            paperProfile: configuration.paperProfile,
            processingMode: configuration.processingMode,
            interpolationAlgorithm: configuration.interpolationAlgorithm,
            refinementAlgorithm: configuration.refinementAlgorithm,
            predictionAlgorithm: configuration.predictionAlgorithm,
            rendererMode: configuration.rendererMode,
            replayURL: configuration.replayURL,
            replaySpeed: configuration.replaySpeed
        )
        let applicationSupport = FileManager.default.urls(
            for: .applicationSupportDirectory,
            in: .userDomainMask
        ).first ?? FileManager.default.homeDirectoryForCurrentUser
        let inputLabDirectory = applicationSupport
            .appendingPathComponent("Trace", isDirectory: true)
            .appendingPathComponent("InputLab", isDirectory: true)
        let profileFileName = Self.safeFileName(configuration.paperProfile)
        calibrationStore = LocalCalibrationStore(
            fileURL: inputLabDirectory
                .appendingPathComponent("calibrations", isDirectory: true)
                .appendingPathComponent("\(profileFileName).json")
        )

        do {
            calibratedSurface = try calibrationStore.load()
            if calibratedSurface == nil,
               configuration.paperProfile == "b-native-100"
            {
                let legacyStore = LocalCalibrationStore(
                    fileURL: inputLabDirectory.appendingPathComponent("calibration.json")
                )
                if let legacyCalibration = try legacyStore.load() {
                    calibratedSurface = legacyCalibration
                    try calibrationStore.save(legacyCalibration)
                }
            }
        } catch {
            lastError = "Saved calibration could not be loaded: \(error.localizedDescription)"
        }
        if calibratedSurface == nil {
            beginCalibration()
        }

        normalizer.eventHandler = { [weak self] event in
            self?.handleInput(event)
        }
    }

    private static func safeFileName(_ value: String) -> String {
        let allowed = CharacterSet.alphanumerics.union(
            CharacterSet(charactersIn: "-_")
        )
        let scalars = value.unicodeScalars.map {
            allowed.contains($0) ? Character(String($0)) : "-"
        }
        let result = String(scalars)
        return result.isEmpty ? "unlabeled" : result
    }

    func start() {
        guard !isStarted else {
            return
        }
        isStarted = true
        if let replayURL {
            startReplay(from: replayURL)
            return
        }
        transport.eventHandler = { [weak self] event in
            self?.handleTransport(event)
        }
        transport.startDiscovery()
    }

    func stop() {
        clearHover()
        if replayURL == nil {
            transport.disconnect()
        }
        recorder.recordPerformance(performance.snapshot)
        recorder.close()
    }

    private func startReplay(from url: URL) {
        do {
            let replay = try LabReplay.load(from: url)
            let hasPenSamples = replay.events.contains { entry in
                guard entry.inputSource == .pen else {
                    return false
                }
                if case .sample = entry.event {
                    return true
                }
                return false
            }
            guard !hasPenSamples || calibratedSurface != nil else {
                lastError =
                    "Replay requires an existing calibration for this paper profile."
                onStateChange?()
                scheduleReplayFinished(after: 1)
                return
            }
            connectionState = .connected
            inputEnabled = hasPenSamples
            pagePrimed = hasPenSamples
            currentPage = hasPenSamples ? calibratedSurface?.page : nil
            replayMouseLastSample = nil
            onStateChange?()

            let firstUptime = replay.events.first?.uptimeNanoseconds ?? 0
            for entry in replay.events {
                let relative = entry.uptimeNanoseconds >= firstUptime
                    ? entry.uptimeNanoseconds - firstUptime
                    : 0
                let delay = Double(relative) / 1_000_000_000 / replaySpeed
                DispatchQueue.main.asyncAfter(deadline: .now() + delay) { [weak self] in
                    self?.handleReplayEntry(entry)
                }
            }

            if quitAfterReplay {
                let finalUptime = replay.events.last?.uptimeNanoseconds ?? firstUptime
                let duration = Double(finalUptime - firstUptime)
                    / 1_000_000_000 / replaySpeed
                scheduleReplayFinished(after: duration + 0.5)
            }
        } catch {
            lastError = "Replay could not load: \(error.localizedDescription)"
            onStateChange?()
            scheduleReplayFinished(after: 1)
        }
    }

    private func handleReplayEntry(_ entry: LabReplay.Entry) {
        let event = entry.event.replayed(at: .now())
        guard entry.inputSource == .mouse else {
            handleInput(event)
            return
        }
        switch event {
        case .strokeStarted:
            replayMouseLastSample = nil
        case let .sample(sample):
            let mouseSample = LabMouseSample(
                point: UnitPoint(
                    x: min(1, max(0, sample.x)),
                    y: min(1, max(0, sample.y))
                ),
                pressure: sample.pressure,
                wallClockMilliseconds:
                    sample.receivedWallClockMilliseconds,
                uptimeNanoseconds:
                    sample.receivedUptimeNanoseconds
            )
            handleMouseStroke(
                activeMouseStrokeID == nil
                    ? .began(mouseSample)
                    : .moved(mouseSample)
            )
            replayMouseLastSample = mouseSample
        case let .strokeCompleted(stroke):
            guard let lastSample = replayMouseLastSample else {
                return
            }
            handleMouseStroke(
                .ended(
                    LabMouseSample(
                        point: lastSample.point,
                        pressure: lastSample.pressure,
                        wallClockMilliseconds:
                            stroke.receivedWallClockMilliseconds,
                        uptimeNanoseconds:
                            stroke.receivedUptimeNanoseconds
                    )
                )
            )
            replayMouseLastSample = nil
        case .pageChanged, .hover, .opticalError, .anomaly:
            break
        }
    }

    private func scheduleReplayFinished(after seconds: Double) {
        guard quitAfterReplay else {
            return
        }
        DispatchQueue.main.asyncAfter(
            deadline: .now() + seconds
        ) { [weak self] in
            self?.onReplayFinished?()
        }
    }

    func eraseDrawing() {
        guard !isStrokeActive,
              calibrationSession == nil || !inputEnabled
        else {
            return
        }
        strokeProcessor.reset()
        resetMouseStroke()
        recorder.recordCanvasErased()
        onCanvasReset?()
        onStateChange?()
    }

    func recalibrate() {
        guard replayURL == nil,
              inputEnabled,
              !isStrokeActive,
              calibrationSession == nil
        else {
            return
        }
        beginCalibration()
        onCanvasReset?()
        onStateChange?()
    }

    func setProcessingMode(_ mode: StrokeRenderMode) {
        guard mode != processingMode, !isStrokeActive else {
            return
        }
        processingMode = mode
        strokeProcessor.mode = mode
        mouseStrokeProcessor.mode = mode
        performance.reset()
        latestPressure = nil
        recorder.setProcessingMode(mode)
        onCanvasReset?()
        onStateChange?()
    }

    func setStrokeReconstruction(
        interpolationAlgorithm: GapInterpolationAlgorithm,
        refinementAlgorithm: StrokeRefinementAlgorithm
    ) {
        guard (
            interpolationAlgorithm != self.interpolationAlgorithm
                || refinementAlgorithm != self.refinementAlgorithm
        ), !isStrokeActive else {
            return
        }
        self.interpolationAlgorithm = interpolationAlgorithm
        self.refinementAlgorithm = refinementAlgorithm
        strokeProcessor.interpolationAlgorithm = interpolationAlgorithm
        strokeProcessor.refinementAlgorithm = refinementAlgorithm
        mouseStrokeProcessor.interpolationAlgorithm = interpolationAlgorithm
        mouseStrokeProcessor.refinementAlgorithm = refinementAlgorithm
        performance.reset()
        latestPressure = nil
        recorder.setStrokeReconstruction(
            interpolationAlgorithm: interpolationAlgorithm,
            refinementAlgorithm: refinementAlgorithm
        )
        onCanvasReset?()
        onStateChange?()
    }

    func setPredictionAlgorithm(_ algorithm: PredictionAlgorithm) {
        guard algorithm != predictionAlgorithm, !isStrokeActive else {
            return
        }
        predictionAlgorithm = algorithm
        strokeProcessor.predictionAlgorithm = algorithm
        mouseStrokeProcessor.predictionAlgorithm = algorithm
        performance.reset()
        latestPressure = nil
        recorder.setPredictionAlgorithm(algorithm)
        onCanvasReset?()
        onStateChange?()
    }

    func setRendererMode(_ mode: LabRendererMode) {
        guard rendererMode != mode, !isStrokeActive else {
            return
        }
        rendererMode = mode
        recorder.setRendererMode(mode)
        strokeProcessor.reset()
        resetMouseStroke()
        performance.reset()
        onCanvasReset?()
        onStateChange?()
    }

    func handleMouseStroke(_ event: LabMouseStrokeEvent) {
        guard calibrationSession == nil || !inputEnabled else {
            return
        }
        switch event {
        case let .began(sample):
            guard !isStrokeActive else {
                return
            }
            isStrokeActive = true
            activeMouseStrokeID = nextMouseStrokeID
            nextMouseStrokeID &+= 1
            mouseSampleIndex = 0
            previousMouseSample = nil
            mouseStrokeStartedAt = sample
            mouseStrokeProcessor.reset()
            let started = InputStrokeStarted(
                strokeID: activeMouseStrokeID ?? 0,
                penTimestampMilliseconds:
                    sample.wallClockMilliseconds,
                receivedWallClockMilliseconds:
                    sample.wallClockMilliseconds,
                receivedUptimeNanoseconds:
                    sample.uptimeNanoseconds,
                inputLatencyMilliseconds: 0,
                tipType: .normal,
                color: 0
            )
            let input = makeMouseSample(sample, first: true)
            recorder.record(
                .strokeStarted(started),
                inputSource: "mouse"
            )
            performance.record(.strokeStarted(started))
            processMouseSample(input)
            onStateChange?()
        case let .moved(sample):
            guard activeMouseStrokeID != nil else {
                return
            }
            processMouseSample(makeMouseSample(sample, first: false))
        case let .ended(sample):
            guard let strokeID = activeMouseStrokeID else {
                return
            }
            if previousMouseSample?.point != sample.point {
                processMouseSample(makeMouseSample(sample, first: false))
            }
            let refinementStarted =
                DispatchTime.now().uptimeNanoseconds
            let finalUpdate = mouseStrokeProcessor.endStroke()
            let refinementNanoseconds =
                DispatchTime.now().uptimeNanoseconds
                    - refinementStarted
            if let finalUpdate {
                emitMouseUpdate(
                    finalUpdate,
                    sourceSample: nil,
                    isFinal: true,
                    refinementReadyUptimeNanoseconds:
                        finalUpdate.replacement == nil
                            ? nil
                            : DispatchTime.now().uptimeNanoseconds
                )
                if refinementAlgorithm != .none {
                    recorder.recordStrokeRefinement(
                        strokeID: strokeID,
                        algorithm: refinementAlgorithm,
                        nanoseconds: refinementNanoseconds,
                        outputPointCount:
                            finalUpdate.replacement?.count
                    )
                }
            }
            let duration = mouseStrokeStartedAt.map {
                sample.wallClockMilliseconds
                    >= $0.wallClockMilliseconds
                    ? sample.wallClockMilliseconds
                        - $0.wallClockMilliseconds
                    : 0
            } ?? 0
            let completed = InputStrokeCompleted(
                strokeID: strokeID,
                page: nil,
                startedAtPenMilliseconds:
                    mouseStrokeStartedAt?.wallClockMilliseconds
                        ?? sample.wallClockMilliseconds,
                endedAtPenMilliseconds:
                    sample.wallClockMilliseconds,
                durationMilliseconds: duration,
                sampleCount: mouseSampleIndex,
                opticalErrorCount: 0,
                reportedDotCount: UInt16(
                    min(mouseSampleIndex, Int(UInt16.max))
                ),
                totalImageCount: 0,
                processedImageCount: 0,
                successfulImageCount: 0,
                sentImageCount: 0,
                imageRecognitionRate: 1,
                receivedWallClockMilliseconds:
                    sample.wallClockMilliseconds,
                receivedUptimeNanoseconds:
                    sample.uptimeNanoseconds,
                completionLatencyMilliseconds: 0
            )
            recorder.record(
                .strokeCompleted(completed),
                inputSource: "mouse"
            )
            performance.record(.strokeCompleted(completed))
            resetMouseStroke()
            isStrokeActive = false
            recorder.recordPerformance(performance.snapshot)
            onStateChange?()
        }
    }

    func recordRendered(_ samples: [RawPenSample], at uptimeNanoseconds: UInt64) {
        for sample in samples {
            performance.recordRendered(
                sample,
                atUptimeNanoseconds: uptimeNanoseconds
            )
            recorder.recordRendered(sample, at: uptimeNanoseconds)
        }
    }

    func recordRefinementRendered(
        _ measurement: RefinementRenderMeasurement
    ) {
        recorder.recordRefinementRendered(measurement)
    }

    func recordCanvasDrawn(_ measurement: CanvasDrawMeasurement) {
        recorder.recordCanvasDrawn(measurement)
    }

    private func configureMouseProcessor() {
        mouseStrokeProcessor.mode = processingMode
        mouseStrokeProcessor.interpolationAlgorithm =
            interpolationAlgorithm
        mouseStrokeProcessor.refinementAlgorithm =
            refinementAlgorithm
        mouseStrokeProcessor.predictionAlgorithm =
            predictionAlgorithm
    }

    private func makeMouseSample(
        _ sample: LabMouseSample,
        first: Bool
    ) -> RawPenSample {
        let pressure = mousePressure(for: sample)
        let interArrivalMilliseconds: Double? = previousMouseSample.map {
            previous in
            guard sample.uptimeNanoseconds
                >= previous.uptimeNanoseconds
            else {
                return 0.0
            }
            return Double(
                sample.uptimeNanoseconds
                    - previous.uptimeNanoseconds
            ) / 1_000_000
        }
        defer {
            previousMouseSample = sample
            mouseSampleIndex += 1
            nextMouseSampleID &+= 1
        }
        return RawPenSample(
            id: nextMouseSampleID,
            strokeID: activeMouseStrokeID ?? 0,
            sampleIndex: mouseSampleIndex,
            eventCount: UInt8(truncatingIfNeeded: mouseSampleIndex),
            page: nil,
            penTimestampMilliseconds: sample.wallClockMilliseconds,
            receivedWallClockMilliseconds:
                sample.wallClockMilliseconds,
            receivedUptimeNanoseconds: sample.uptimeNanoseconds,
            protocolClockDeltaMilliseconds: 0,
            interArrivalMilliseconds: interArrivalMilliseconds,
            x: sample.point.x,
            y: sample.point.y,
            force: UInt16((pressure * 852).rounded()),
            pressure: pressure,
            tiltX: 90,
            tiltY: 90,
            twist: 0,
            continuity: first ? .first : .continuous
        )
    }

    private func mousePressure(for sample: LabMouseSample) -> Double {
        if let pressure = sample.pressure {
            return min(1, max(0, pressure))
        }
        guard let previousMouseSample,
              sample.uptimeNanoseconds
                > previousMouseSample.uptimeNanoseconds
        else {
            return 0.55
        }
        let seconds = Double(
            sample.uptimeNanoseconds
                - previousMouseSample.uptimeNanoseconds
        ) / 1_000_000_000
        let distance = hypot(
            sample.point.x - previousMouseSample.point.x,
            sample.point.y - previousMouseSample.point.y
        )
        let speed = distance / max(seconds, 0.000_001)
        return min(0.82, max(0.18, 0.76 - speed * 0.12))
    }

    private func processMouseSample(_ sample: RawPenSample) {
        let event = NeoInputEvent.sample(sample)
        recorder.record(
            event,
            measurementEligible: true,
            inputSource: "mouse"
        )
        performance.record(event)
        let processingStarted =
            DispatchTime.now().uptimeNanoseconds
        let update = mouseStrokeProcessor.receive(sample)
        let processingNanoseconds =
            DispatchTime.now().uptimeNanoseconds - processingStarted
        performance.recordProcessingLatency(
            nanoseconds: processingNanoseconds
        )
        recorder.recordProcessing(
            sample: sample,
            mode: processingMode,
            interpolationAlgorithm: interpolationAlgorithm,
            refinementAlgorithm: refinementAlgorithm,
            predictionAlgorithm: predictionAlgorithm,
            nanoseconds: processingNanoseconds,
            update: update
        )
        emitMouseUpdate(
            update,
            sourceSample: sample,
            isFinal: false,
            refinementReadyUptimeNanoseconds: nil
        )
    }

    private func emitMouseUpdate(
        _ update: StrokeRenderUpdate,
        sourceSample: RawPenSample?,
        isFinal: Bool,
        refinementReadyUptimeNanoseconds: UInt64?
    ) {
        publish(
            LabRendererUpdate(
                strokeID: update.strokeID,
                committed: update.committed.map(mouseRenderPoint),
                predicted: update.predicted.map(mouseRenderPoint),
                replacement: update.replacement?.map(mouseRenderPoint),
                sourceSamples: sourceSample.map { [$0] } ?? [],
                refinementReadyUptimeNanoseconds:
                    refinementReadyUptimeNanoseconds,
                isFinal: isFinal
            )
        )
    }

    private func mouseRenderPoint(_ point: RenderPoint) -> LabRenderPoint {
        LabRenderPoint(
            render: point,
            normalized: UnitPoint(
                x: min(1, max(0, point.x)),
                y: min(1, max(0, point.y))
            )
        )
    }

    private func emitPenUpdate(
        _ update: StrokeRenderUpdate,
        sourceSample: RawPenSample?,
        isFinal: Bool,
        refinementReadyUptimeNanoseconds: UInt64?
    ) {
        guard let calibration = calibratedSurface?.calibration else {
            return
        }
        func map(_ point: RenderPoint) -> LabRenderPoint? {
            guard let normalized = calibration.normalize(
                NcodePoint(x: point.x, y: point.y)
            ) else {
                return nil
            }
            return LabRenderPoint(
                render: point,
                normalized: normalized
            )
        }
        publish(
            LabRendererUpdate(
                strokeID: update.strokeID,
                committed: update.committed.compactMap(map),
                predicted: update.predicted.compactMap(map),
                replacement: update.replacement?.compactMap(map),
                sourceSamples: sourceSample.map { [$0] } ?? [],
                refinementReadyUptimeNanoseconds:
                    refinementReadyUptimeNanoseconds,
                isFinal: isFinal
            )
        )
    }

    private func publish(_ update: LabRendererUpdate) {
        onRenderUpdate?(rendererMode.prepare(update))
    }

    private func resetMouseStroke() {
        mouseStrokeProcessor.reset()
        activeMouseStrokeID = nil
        mouseSampleIndex = 0
        previousMouseSample = nil
        mouseStrokeStartedAt = nil
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
            if state == .disconnected || state == .reconnecting || state == .failed {
                normalizer.resetConnectionState()
                clockSyncRequested = false
                clockSynchronized = false
                didEnableInput = false
                inputEnabled = false
                pagePrimed = false
                primingStrokeID = nil
                currentPage = nil
                currentNotificationBatch = nil
                hoverEnabled = nil
                strokeProcessor.reset()
                isStrokeActive = false
                clearHover()
                recorder.recordMeasurementPaused(reason: "connection-\(state.rawValue)")
            }
            onStateChange?()
        case let .deviceInfo(info):
            deviceName = info.subName.isEmpty ? info.modelName : info.subName
            onStateChange?()
        case let .status(status):
            batteryPercent = status.batteryPercent
            isCharging = status.isCharging
            if hoverEnabled != status.hoverEnabled {
                recorder.recordHoverSetting(enabled: status.hoverEnabled)
            }
            hoverEnabled = status.hoverEnabled
            guard !status.isLocked else {
                lastError = "The pen is locked; input authentication is not available."
                onStateChange?()
                return
            }
            if !clockSyncRequested {
                clockSyncRequested = true
                transport.setCurrentTime(
                    milliseconds: UInt64(Date().timeIntervalSince1970 * 1_000)
                )
            } else if clockSynchronized, !didEnableInput {
                enableInput()
            }
            onStateChange?()
        case .settingChanged(.timestamp):
            clockSynchronized = true
            enableInput()
        case .settingChanged(.hover):
            transport.requestStatus()
        case .onlineDataEnabled:
            inputEnabled = true
            lastError = nil
            onStateChange?()
        case let .failure(failure):
            lastError = "\(failure.stage): \(failure.message)"
            onStateChange?()
        default:
            break
        }
    }

    private func enableInput() {
        guard !didEnableInput else {
            return
        }
        didEnableInput = true
        transport.enableOnlineData()
    }

    private func handleInput(_ event: NeoInputEvent) {
        if case let .hover(sample) = event {
            handleHover(sample)
            return
        }
        if let calibrationSession {
            recorder.record(event, measurementEligible: false)
            if let update = calibrationSession.receive(event) {
                handleCalibration(update)
            }
            return
        }

        if !pagePrimed {
            recorder.record(event, measurementEligible: false)
            handlePagePriming(event)
            return
        }

        switch event {
        case let .pageChanged(page):
            recorder.record(event)
            guard calibratedSurface?.isCalibrationCompatible(
                with: page
            ) == true else {
                clearHover()
                performance.reset()
                pagePrimed = false
                isStrokeActive = false
                strokeProcessor.reset()
                currentPage = page
                lastError = "This Ncode page differs from the saved calibration."
                recorder.recordMeasurementPaused(reason: "different-page")
                onCanvasReset?()
                onStateChange?()
                return
            }
            currentPage = page
            onStateChange?()
        case let .sample(sample):
            currentPage = sample.page ?? currentPage
            latestPressure = sample.pressure
            guard let calibratedSurface else {
                recorder.record(event, measurementEligible: false)
                beginCalibration()
                onStateChange?()
                return
            }
            guard calibratedSurface.isCalibrationCompatible(
                with: sample.page
            ) else {
                recorder.record(event, measurementEligible: false)
                clearHover()
                performance.reset()
                pagePrimed = false
                isStrokeActive = false
                strokeProcessor.reset()
                lastError = "This Ncode page differs from the saved calibration."
                recorder.recordMeasurementPaused(reason: "different-page")
                onCanvasReset?()
                onStateChange?()
                return
            }
            recorder.record(event, measurementEligible: true)
            performance.record(event)
            let processingStarted = DispatchTime.now().uptimeNanoseconds
            let update = strokeProcessor.receive(sample)
            let processingNanoseconds = DispatchTime.now().uptimeNanoseconds
                - processingStarted
            performance.recordProcessingLatency(
                nanoseconds: processingNanoseconds
            )
            recorder.recordProcessing(
                sample: sample,
                mode: processingMode,
                interpolationAlgorithm: interpolationAlgorithm,
                refinementAlgorithm: refinementAlgorithm,
                predictionAlgorithm: predictionAlgorithm,
                nanoseconds: processingNanoseconds,
                update: update
            )
            emitPenUpdate(
                update,
                sourceSample: sample,
                isFinal: false,
                refinementReadyUptimeNanoseconds: nil
            )
        case .strokeCompleted:
            recorder.record(event)
            let refinementStarted = DispatchTime.now().uptimeNanoseconds
            let refinementUpdate = strokeProcessor.endStroke()
            let refinementNanoseconds = DispatchTime.now().uptimeNanoseconds
                - refinementStarted
            if let update = refinementUpdate {
                emitPenUpdate(
                    update,
                    sourceSample: nil,
                    isFinal: true,
                    refinementReadyUptimeNanoseconds:
                        update.replacement == nil
                        ? nil
                        : DispatchTime.now().uptimeNanoseconds
                )
                if refinementAlgorithm != .none {
                    recorder.recordStrokeRefinement(
                        strokeID: update.strokeID,
                        algorithm: refinementAlgorithm,
                        nanoseconds: refinementNanoseconds,
                        outputPointCount: update.replacement?.count
                    )
                }
            }
            performance.record(event)
            isStrokeActive = false
            recorder.recordPerformance(performance.snapshot)
            onStateChange?()
        case .strokeStarted:
            recorder.record(event)
            clearHover()
            isStrokeActive = true
            lastError = nil
            performance.record(event)
            onStateChange?()
        case .opticalError, .anomaly:
            recorder.record(event)
            performance.record(event)
            onStateChange?()
        case .hover:
            break
        }
    }

    private func handleHover(_ sample: RawHoverSample) {
        recorder.record(.hover(sample), measurementEligible: false)
        guard calibrationSession == nil,
              pagePrimed,
              let calibratedSurface,
              calibratedSurface.isCalibrationCompatible(with: sample.page)
        else {
            clearHover()
            return
        }
        hoverClearWorkItem?.cancel()
        hoverGeneration &+= 1
        let generation = hoverGeneration
        onHoverUpdate?(sample)
        let workItem = DispatchWorkItem { [weak self] in
            guard let self, self.hoverGeneration == generation else {
                return
            }
            self.hoverClearWorkItem = nil
            self.onHoverUpdate?(nil)
        }
        hoverClearWorkItem = workItem
        DispatchQueue.main.asyncAfter(
            deadline: .now() + Self.hoverCursorIdleSeconds,
            execute: workItem
        )
    }

    private func clearHover() {
        hoverGeneration &+= 1
        hoverClearWorkItem?.cancel()
        hoverClearWorkItem = nil
        onHoverUpdate?(nil)
    }

    private func beginCalibration() {
        clearHover()
        recorder.recordMeasurementPaused(reason: "calibration")
        calibrationSession = SurfaceCalibrationSession()
        pagePrimed = false
        primingStrokeID = nil
        isStrokeActive = false
        calibrationMessage = pageRegistrationInstruction()
        lastError = nil
        performance.reset()
        strokeProcessor.reset()
        latestPressure = nil
    }

    private func handleCalibration(_ update: CalibrationUpdate) {
        switch update {
        case let .pageRegistered(page, next):
            currentPage = page
            calibrationMessage = calibrationInstruction(for: next)
        case .retryPageRegistration:
            calibrationMessage = "No page identity recognized. "
                + pageRegistrationInstruction()
        case let .captured(_, _, next):
            calibrationMessage = calibrationInstruction(for: next)
        case let .retry(corner, reason):
            calibrationMessage = retryInstruction(for: corner, reason: reason)
        case let .completed(surface):
            calibratedSurface = surface
            currentPage = surface.page
            calibrationSession = nil
            pagePrimed = true
            primingStrokeID = nil
            calibrationMessage = nil
            performance.reset()
            strokeProcessor.reset()
            latestPressure = nil
            do {
                try calibrationStore.save(surface)
            } catch {
                lastError = "Calibration works but could not be saved: \(error.localizedDescription)"
            }
            recorder.recordCalibration(surface)
            onCanvasReset?()
        }
        onStateChange?()
    }

    private func handlePagePriming(_ event: NeoInputEvent) {
        switch event {
        case let .strokeStarted(stroke):
            primingStrokeID = stroke.strokeID
            currentPage = nil
            lastError = nil
        case let .pageChanged(page):
            currentPage = page
        case let .sample(sample):
            currentPage = sample.page ?? currentPage
        case let .strokeCompleted(stroke):
            guard stroke.strokeID == primingStrokeID else {
                return
            }
            primingStrokeID = nil
            guard let currentPage else {
                lastError = "No page identity recognized. Tap the paper once again."
                onStateChange?()
                return
            }
            guard calibratedSurface?.isCalibrationCompatible(
                with: currentPage
            ) == true else {
                lastError = "This Ncode page differs from the saved calibration."
                onStateChange?()
                return
            }
            pagePrimed = true
            lastError = nil
            performance.reset()
            strokeProcessor.reset()
            latestPressure = nil
            recorder.recordPagePrimed(currentPage)
            onCanvasReset?()
        case .anomaly:
            lastError = "The priming tap was incomplete. Tap the paper once again."
        case .opticalError:
            break
        case .hover:
            break
        }
        onStateChange?()
    }

    private func calibrationInstruction(for corner: CalibrationCorner) -> String {
        "Tap the \(corner.displayName) paper corner, then lift."
    }

    private func pageRegistrationInstruction() -> String {
        "Tap once anywhere on the paper to register its Ncode page."
    }

    private func retryInstruction(
        for corner: CalibrationCorner,
        reason: CalibrationRetryReason
    ) -> String {
        switch reason {
        case .noRecognizedSamples:
            return "No Ncode point recognized. Tap the \(corner.displayName) corner again."
        case .differentPage:
            return "Use the same paper page. Tap the \(corner.displayName) corner again."
        case .degenerateGeometry:
            return "Corners could not form a surface. Restarting at top-left."
        }
    }
}
