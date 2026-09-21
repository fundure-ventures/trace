import Foundation
import NeoInput
import TraceCalibration
import TraceMetrics
import TraceStrokeProcessing

final class LabSessionRecorder {
    let fileURL: URL

    private let queue = DispatchQueue(label: "com.traceproject.input-lab.recorder")
    private let fileHandle: FileHandle
    private var isClosed = false

    private let implementationID: String
    private let paperProfile: String
    private var processingMode: StrokeRenderMode
    private var interpolationAlgorithm: GapInterpolationAlgorithm
    private var refinementAlgorithm: StrokeRefinementAlgorithm
    private var predictionAlgorithm: PredictionAlgorithm
    private var rendererMode: LabRendererMode

    init(
        directory: URL,
        implementationID: String,
        paperProfile: String,
        processingMode: StrokeRenderMode,
        interpolationAlgorithm: GapInterpolationAlgorithm,
        refinementAlgorithm: StrokeRefinementAlgorithm,
        predictionAlgorithm: PredictionAlgorithm,
        rendererMode: LabRendererMode,
        replayURL: URL?,
        replaySpeed: Double
    ) throws {
        self.implementationID = implementationID
        self.paperProfile = paperProfile
        self.processingMode = processingMode
        self.interpolationAlgorithm = interpolationAlgorithm
        self.refinementAlgorithm = refinementAlgorithm
        self.predictionAlgorithm = predictionAlgorithm
        self.rendererMode = rendererMode
        try FileManager.default.createDirectory(
            at: directory,
            withIntermediateDirectories: true
        )
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyyMMdd-HHmmss"
        let suffix = UUID().uuidString.lowercased().prefix(8)
        fileURL = directory.appendingPathComponent(
            "input-lab-\(formatter.string(from: Date()))-\(suffix).jsonl"
        )
        guard FileManager.default.createFile(atPath: fileURL.path, contents: nil) else {
            throw CocoaError(.fileWriteUnknown)
        }
        fileHandle = try FileHandle(forWritingTo: fileURL)
        var session: [String: Any] = [
            "type": "session-start",
            "schema_version": 1,
            "wall_clock_ms": wallClockMilliseconds(),
            "implementation_id": implementationID,
            "paper_profile": paperProfile,
            "processing_mode": processingMode.rawValue,
            "interpolation_algorithm": interpolationAlgorithm.rawValue,
            "stroke_refinement": refinementAlgorithm.rawValue,
            "prediction_algorithm": predictionAlgorithm.rawValue,
            "renderer": rendererMode.rawValue,
            "input_source": replayURL == nil ? "live" : "replay",
        ]
        if let replayURL {
            session["replay_file"] = replayURL.lastPathComponent
            session["replay_speed"] = replaySpeed
        }
        write(session)
    }

    deinit {
        close()
    }

    func record(
        _ event: NeoInputEvent,
        measurementEligible: Bool? = nil,
        inputSource: String? = nil
    ) {
        switch event {
        case let .strokeStarted(stroke):
            var row: [String: Any] = [
                "type": "stroke-start",
                "stroke_id": stroke.strokeID,
                "pen_ms": stroke.penTimestampMilliseconds,
                "received_ms": stroke.receivedWallClockMilliseconds,
                "received_uptime_ns": stroke.receivedUptimeNanoseconds,
                "raw_start_clock_delta_ms": stroke.inputLatencyMilliseconds,
            ]
            if let inputSource {
                row["input_source"] = inputSource
            }
            write(row)
        case let .pageChanged(page):
            write(pageFields(page).merging(["type": "page"]) { _, new in new })
        case let .sample(sample):
            var row: [String: Any] = [
                "type": "sample",
                "id": sample.id,
                "stroke_id": sample.strokeID,
                "sample_index": sample.sampleIndex,
                "event_count": sample.eventCount,
                "pen_ms": sample.penTimestampMilliseconds,
                "received_ms": sample.receivedWallClockMilliseconds,
                "received_uptime_ns": sample.receivedUptimeNanoseconds,
                "protocol_reconstructed_latency_ms":
                    sample.protocolClockDeltaMilliseconds,
                "x": sample.x,
                "y": sample.y,
                "force": sample.force,
                "tilt_x": sample.tiltX,
                "tilt_y": sample.tiltY,
                "twist": sample.twist,
            ]
            if let pressure = sample.pressure {
                row["pressure"] = pressure
            }
            if let interArrival = sample.interArrivalMilliseconds {
                row["inter_arrival_ms"] = interArrival
            }
            if let measurementEligible {
                row["measurement_eligible"] = measurementEligible
            }
            if let inputSource {
                row["input_source"] = inputSource
            }
            if let batchID = sample.transportBatchID {
                row["transport_batch_id"] = batchID
            }
            if let frameCount = sample.transportBatchFrameCount {
                row["transport_batch_frame_count"] = frameCount
            }
            if let byteCount = sample.transportBatchByteCount {
                row["transport_batch_byte_count"] = byteCount
            }
            if let page = sample.page {
                row.merge(pageFields(page)) { _, new in new }
            }
            switch sample.continuity {
            case .first:
                row["continuity"] = "first"
            case .continuous:
                row["continuity"] = "continuous"
            case let .gap(opticalErrors, eventCountDelta):
                row["continuity"] = "gap"
                row["gap_optical_errors"] = opticalErrors
                row["gap_event_count_delta"] = eventCountDelta
            }
            write(row)
        case let .hover(sample):
            var row: [String: Any] = [
                "type": "hover",
                "id": sample.id,
                "source": sample.source.rawValue,
                "time_delta_ms": sample.timeDeltaMilliseconds,
                "received_ms": sample.receivedWallClockMilliseconds,
                "received_uptime_ns": sample.receivedUptimeNanoseconds,
                "x": sample.x,
                "y": sample.y,
            ]
            if let eventCount = sample.eventCount {
                row["event_count"] = eventCount
            }
            if let interArrival = sample.interArrivalMilliseconds {
                row["inter_arrival_ms"] = interArrival
            }
            if let force = sample.force {
                row["force"] = force
            }
            if let pressure = sample.pressure {
                row["pressure"] = pressure
            }
            if let tiltX = sample.tiltX {
                row["tilt_x"] = tiltX
            }
            if let tiltY = sample.tiltY {
                row["tilt_y"] = tiltY
            }
            if let twist = sample.twist {
                row["twist"] = twist
            }
            if let measurementEligible {
                row["measurement_eligible"] = measurementEligible
            }
            if let batchID = sample.transportBatchID {
                row["transport_batch_id"] = batchID
            }
            if let frameCount = sample.transportBatchFrameCount {
                row["transport_batch_frame_count"] = frameCount
            }
            if let byteCount = sample.transportBatchByteCount {
                row["transport_batch_byte_count"] = byteCount
            }
            if let page = sample.page {
                row.merge(pageFields(page)) { _, new in new }
            }
            write(row)
        case let .opticalError(error):
            var row: [String: Any] = [
                "type": "optical-error",
                "stroke_id": error.strokeID,
                "pen_ms": error.penTimestampMilliseconds,
                "received_ms": error.receivedWallClockMilliseconds,
                "protocol_reconstructed_latency_ms":
                    error.protocolClockDeltaMilliseconds,
                "force": error.event.force,
                "error_code": error.event.errorCode,
                "error_count": error.event.errorCount,
                "brightness": error.event.imageBrightness,
                "exposure": error.event.exposureTime,
                "processing_time": error.event.processingTime,
                "label_count": error.event.labelCount,
            ]
            if let page = error.page {
                row.merge(pageFields(page)) { _, new in new }
            }
            write(row)
        case let .strokeCompleted(stroke):
            var row: [String: Any] = [
                "type": "stroke-complete",
                "stroke_id": stroke.strokeID,
                "duration_ms": stroke.durationMilliseconds,
                "sample_count": stroke.sampleCount,
                "optical_error_count": stroke.opticalErrorCount,
                "reported_dot_count": stroke.reportedDotCount,
                "total_image_count": stroke.totalImageCount,
                "processed_image_count": stroke.processedImageCount,
                "successful_image_count": stroke.successfulImageCount,
                "sent_image_count": stroke.sentImageCount,
                "image_recognition_rate": stroke.imageRecognitionRate,
                "received_ms": stroke.receivedWallClockMilliseconds,
                "received_uptime_ns": stroke.receivedUptimeNanoseconds,
                "raw_completion_clock_delta_ms":
                    stroke.completionLatencyMilliseconds,
            ]
            if let page = stroke.page {
                row.merge(pageFields(page)) { _, new in new }
            }
            if let inputSource {
                row["input_source"] = inputSource
            }
            write(row)
        case let .anomaly(anomaly):
            write([
                "type": "anomaly",
                "detail": String(describing: anomaly),
            ])
        }
    }

    func recordRendered(_ sample: RawPenSample, at uptimeNanoseconds: UInt64) {
        let latency = uptimeNanoseconds >= sample.receivedUptimeNanoseconds
            ? Double(uptimeNanoseconds - sample.receivedUptimeNanoseconds) / 1_000_000
            : 0
        write([
            "type": "render",
            "sample_id": sample.id,
            "stroke_id": sample.strokeID,
            "render_uptime_ns": uptimeNanoseconds,
            "render_latency_ms": latency,
        ])
    }

    func recordCalibration(_ surface: CalibratedSurface) {
        write([
            "type": "calibration",
            "page": pageFields(surface.page),
            "corners": surface.calibration.corners.map {
                ["x": $0.x, "y": $0.y]
            },
        ])
    }

    func recordCanvasErased() {
        write([
            "type": "canvas-erased",
            "wall_clock_ms": wallClockMilliseconds(),
        ])
    }

    func recordHoverSetting(enabled: Bool) {
        write([
            "type": "hover-setting",
            "enabled": enabled,
            "wall_clock_ms": wallClockMilliseconds(),
        ])
    }

    func setProcessingMode(_ mode: StrokeRenderMode) {
        processingMode = mode
        write([
            "type": "processing-mode",
            "mode": mode.rawValue,
            "wall_clock_ms": wallClockMilliseconds(),
        ])
    }

    func setStrokeReconstruction(
        interpolationAlgorithm: GapInterpolationAlgorithm,
        refinementAlgorithm: StrokeRefinementAlgorithm
    ) {
        self.interpolationAlgorithm = interpolationAlgorithm
        self.refinementAlgorithm = refinementAlgorithm
        write([
            "type": "stroke-reconstruction",
            "interpolation_algorithm": interpolationAlgorithm.rawValue,
            "stroke_refinement": refinementAlgorithm.rawValue,
            "wall_clock_ms": wallClockMilliseconds(),
        ])
    }

    func setPredictionAlgorithm(_ algorithm: PredictionAlgorithm) {
        predictionAlgorithm = algorithm
        write([
            "type": "prediction-algorithm",
            "algorithm": algorithm.rawValue,
            "wall_clock_ms": wallClockMilliseconds(),
        ])
    }

    func setRendererMode(_ mode: LabRendererMode) {
        rendererMode = mode
        write([
            "type": "renderer-mode",
            "renderer": mode.rawValue,
            "wall_clock_ms": wallClockMilliseconds(),
        ])
    }

    func recordStrokeRefinement(
        strokeID: UInt64,
        algorithm: StrokeRefinementAlgorithm,
        nanoseconds: UInt64,
        outputPointCount: Int?
    ) {
        var row: [String: Any] = [
            "type": "stroke-refinement",
            "stroke_id": strokeID,
            "algorithm": algorithm.rawValue,
            "processing_ns": nanoseconds,
            "applied": outputPointCount != nil,
        ]
        if let outputPointCount {
            row["output_point_count"] = outputPointCount
        }
        write(row)
    }

    func recordRefinementRendered(
        _ measurement: RefinementRenderMeasurement
    ) {
        write([
            "type": "refinement-render",
            "stroke_id": measurement.strokeID,
            "point_count": measurement.pointCount,
            "mapping_ns": measurement.mappingNanoseconds,
            "draw_ns": measurement.drawNanoseconds,
            "ready_to_draw_ms":
                Double(measurement.readyToDrawNanoseconds) / 1_000_000,
        ])
    }

    func recordCanvasDrawn(_ measurement: CanvasDrawMeasurement) {
        write([
            "type": "canvas-draw",
            "retained_point_count": measurement.retainedPointCount,
            "predicted_point_count": measurement.predictedPointCount,
            "acknowledged_sample_count":
                measurement.acknowledgedSampleCount,
            "draw_ns": measurement.drawNanoseconds,
            "draw_uptime_ns": measurement.completedUptimeNanoseconds,
        ])
    }

    func recordProcessing(
        sample: RawPenSample,
        mode: StrokeRenderMode,
        interpolationAlgorithm: GapInterpolationAlgorithm,
        refinementAlgorithm: StrokeRefinementAlgorithm,
        predictionAlgorithm: PredictionAlgorithm,
        nanoseconds: UInt64,
        update: StrokeRenderUpdate
    ) {
        write([
            "type": "processing",
            "sample_id": sample.id,
            "stroke_id": sample.strokeID,
            "mode": mode.rawValue,
            "interpolation_algorithm": interpolationAlgorithm.rawValue,
            "stroke_refinement": refinementAlgorithm.rawValue,
            "prediction_algorithm": predictionAlgorithm.rawValue,
            "processing_ns": nanoseconds,
            "committed_point_count": update.committed.count,
            "predicted_point_count": update.predicted.count,
        ])
    }

    func recordPagePrimed(_ page: PenPageID) {
        write(
            pageFields(page).merging([
                "type": "page-primed",
                "wall_clock_ms": wallClockMilliseconds(),
            ]) { _, new in new }
        )
    }

    func recordMeasurementPaused(reason: String) {
        write([
            "type": "measurement-paused",
            "reason": reason,
            "wall_clock_ms": wallClockMilliseconds(),
        ])
    }

    func recordPerformance(_ snapshot: PerformanceSnapshot) {
        var row: [String: Any] = [
            "type": "performance-snapshot",
            "implementation_id": implementationID,
            "paper_profile": paperProfile,
            "sample_count": snapshot.sampleCount,
            "gap_count": snapshot.gapCount,
            "optical_error_count": snapshot.opticalErrorCount,
            "stroke_count": snapshot.strokeCount,
            "anomaly_count": snapshot.anomalyCount,
            "transport_batch_count": snapshot.transportBatchCount,
            "processing_mode": processingMode.rawValue,
            "renderer": rendererMode.rawValue,
        ]
        if let recognition = snapshot.latestRecognitionRate {
            row["latest_recognition_rate"] = recognition
        }
        if let clockOffset = snapshot.clockOffsetEstimateMilliseconds {
            row["clock_offset_estimate_ms"] = clockOffset
        }
        if let rate = snapshot.effectiveSampleRateHz {
            row["effective_sample_rate_hz"] = rate
        }
        if let rate = snapshot.deliveryRateHz {
            row["delivery_rate_hz"] = rate
        }
        if let meanFrames = snapshot.meanFramesPerBatch {
            row["mean_frames_per_batch"] = meanFrames
        }
        if let maxFrames = snapshot.maximumFramesPerBatch {
            row["max_frames_per_batch"] = maxFrames
        }
        row["start_latency"] = distributionFields(snapshot.startLatency)
        row["raw_start_latency"] = distributionFields(snapshot.rawStartLatency)
        row["completion_latency"] = distributionFields(snapshot.completionLatency)
        row["raw_completion_latency"] = distributionFields(
            snapshot.rawCompletionLatency
        )
        row["first_sample_delay"] = distributionFields(snapshot.firstSampleDelay)
        row["processing_latency"] = distributionFields(snapshot.processingLatency)
        row["render_latency"] = distributionFields(snapshot.renderLatency)
        row["protocol_sample_interval"] = distributionFields(
            snapshot.protocolSampleInterval
        )
        row["delivery_interval"] = distributionFields(snapshot.deliveryInterval)
        write(row)
    }

    func close() {
        queue.sync {
            guard !isClosed else {
                return
            }
            isClosed = true
            try? fileHandle.close()
        }
    }

    private func pageFields(_ page: PenPageID) -> [String: Any] {
        [
            "page_section": page.section,
            "page_owner": page.owner,
            "page_note": page.note,
            "page_number": page.page,
        ]
    }

    private func distributionFields(
        _ distribution: MetricDistribution
    ) -> [String: Any] {
        var fields: [String: Any] = ["count": distribution.count]
        if let value = distribution.minimum { fields["min"] = value }
        if let value = distribution.mean { fields["mean"] = value }
        if let value = distribution.p50 { fields["p50"] = value }
        if let value = distribution.p95 { fields["p95"] = value }
        if let value = distribution.maximum { fields["max"] = value }
        return fields
    }

    private func write(_ object: [String: Any]) {
        queue.async { [weak self] in
            guard let self, !self.isClosed else {
                return
            }
            do {
                let data = try JSONSerialization.data(
                    withJSONObject: object,
                    options: [.sortedKeys]
                )
                self.fileHandle.write(data)
                self.fileHandle.write(Data([0x0A]))
            } catch {
                fputs("Trace Input Lab recorder error: \(error)\n", stderr)
            }
        }
    }

    private func wallClockMilliseconds() -> UInt64 {
        UInt64(Date().timeIntervalSince1970 * 1_000)
    }
}
