import Foundation
import NeoInput
import TraceStrokeProcessing

struct BenchmarkError: Error, CustomStringConvertible {
    let description: String
}

struct ErrorSummary {
    let count: Int
    let eligibleCount: Int
    let mean: Double?
    let p50: Double?
    let p95: Double?
    let maximum: Double?
}

struct LoadedSamples {
    let samples: [RawPenSample]
    let filterDescription: String
}

struct InterpolationEvaluation {
    let all: ErrorSummary
    let curved: ErrorSummary
}

struct RefinementSummary {
    let appliedStrokeCount: Int
    let strokeCount: Int
    let inputPointCount: Int
    let outputPointCount: Int
    let nanosecondsPerStroke: Double
}

struct RefinementReductionSummary {
    let tolerance: Double
    let inputPointCount: Int
    let outputPointCount: Int
    let maximumDeviation: Double
}

struct PredictionEvaluation {
    let error: ErrorSummary
    let sharedError: ErrorSummary
    let lead: ErrorSummary
}

private let arguments = Array(CommandLine.arguments.dropFirst())
let logURL: URL
if let first = arguments.first {
    logURL = URL(fileURLWithPath: first)
} else {
    let logs = URL(
        fileURLWithPath: FileManager.default.currentDirectoryPath,
        isDirectory: true
    ).appendingPathComponent("logs", isDirectory: true)
    let candidates = try FileManager.default.contentsOfDirectory(
        at: logs,
        includingPropertiesForKeys: [.contentModificationDateKey]
    ).filter {
        $0.lastPathComponent.hasPrefix("input-lab-")
            && $0.pathExtension == "jsonl"
    }
    guard let latest = candidates.max(by: {
        modificationDate($0) < modificationDate($1)
    }) else {
        throw BenchmarkError(description: "No input-lab JSONL logs found")
    }
    logURL = latest
}

let loaded = try loadSamples(from: logURL)
let samples = loaded.samples
guard !samples.isEmpty else {
    throw BenchmarkError(description: "No samples found in \(logURL.path)")
}
let strokes = Dictionary(grouping: samples, by: \.strokeID)
    .values
    .map { $0.sorted { $0.sampleIndex < $1.sampleIndex } }

let interpolationEvaluations = GapInterpolationAlgorithm.allCases.map {
    ($0, evaluateInterpolation(strokes, algorithm: $0))
}
let lookaheadInterpolation = evaluateInterpolation(
    strokes,
    algorithm: .cubicBezier,
    useLookahead: true
)
let interpolationSmoothness = GapInterpolationAlgorithm.allCases.map {
    ($0, evaluateGapSmoothness(strokes, algorithm: $0))
}
let predictionEvaluations = PredictionAlgorithm.allCases.map {
    ($0, evaluatePrediction(strokes, algorithm: $0))
}
let reduction = evaluateReduction(strokes)
let refinement = evaluateRefinement(strokes)
let refinementReductions = [0.01, 0.02, 0.03, 0.05].map {
    evaluateRefinementReduction(strokes, tolerance: $0)
}
let rawCost = benchmark(mode: .raw, samples: samples)
let interpolationCosts = GapInterpolationAlgorithm.allCases.map {
    (
        $0,
        benchmark(
            mode: .interpolate,
            interpolationAlgorithm: $0,
            samples: samples
        )
    )
}
let predictionCosts = PredictionAlgorithm.allCases.map {
    (
        $0,
        benchmark(
            mode: .predict,
            predictionAlgorithm: $0,
            samples: samples
        )
    )
}

print("Trace stroke benchmark")
print("log: \(logURL.path)")
print("filter: \(loaded.filterDescription)")
print("samples: \(samples.count), strokes: \(strokes.count)")
print("")
for (algorithm, evaluation) in interpolationEvaluations {
    printError(
        "\(algorithmLabel(algorithm)) interpolation span holdout",
        evaluation.all
    )
    printError(
        "\(algorithmLabel(algorithm)) curved-span holdout",
        evaluation.curved
    )
}
printError(
    "Two-sided Bézier interpolation span holdout",
    lookaheadInterpolation.all
)
printError(
    "Two-sided Bézier curved-span holdout",
    lookaheadInterpolation.curved
)
for (algorithm, smoothness) in interpolationSmoothness {
    printAngles(
        "\(algorithmLabel(algorithm)) gap-boundary turn",
        smoothness
    )
}
for (algorithm, evaluation) in predictionEvaluations {
    printError(
        "\(predictionLabel(algorithm)) prediction next-point",
        evaluation.error
    )
    printError(
        "\(predictionLabel(algorithm)) prediction lead",
        evaluation.lead
    )
    printError(
        "\(predictionLabel(algorithm)) shared prediction error",
        evaluation.sharedError
    )
}
print(
    String(
        format: "Reduction: %d → %d points (%.1f%% removed), max deviation %.4f Ncode",
        reduction.inputCount,
        reduction.outputCount,
        reduction.removalRate * 100,
        reduction.maximumDeviation
    )
)
print(
    String(
        format: "Smooth path: %d/%d strokes, %d → %d points, %.1f µs/stroke",
        refinement.appliedStrokeCount,
        refinement.strokeCount,
        refinement.inputPointCount,
        refinement.outputPointCount,
        refinement.nanosecondsPerStroke / 1_000
    )
)
for reduction in refinementReductions {
    print(
        String(
            format: "Smooth reduction %.2f: %d → %d points, max deviation %.4f Ncode",
            reduction.tolerance,
            reduction.inputPointCount,
            reduction.outputPointCount,
            reduction.maximumDeviation
        )
    )
}
print("")
printCost("Raw", rawCost)
for (algorithm, cost) in interpolationCosts {
    printCost("Fill gaps · \(algorithmLabel(algorithm))", cost)
}
for (algorithm, cost) in predictionCosts {
    printCost(
        "Predict · \(predictionLabel(algorithm))",
        cost
    )
}

private func loadSamples(from url: URL) throws -> LoadedSamples {
    let text = try String(contentsOf: url, encoding: .utf8)
    let rows = try text.split(separator: "\n").compactMap { line -> [String: Any]? in
        let object = try JSONSerialization.jsonObject(with: Data(line.utf8))
        return object as? [String: Any]
    }
    let hasReadinessMarkers = rows.contains {
        let type = $0["type"] as? String
        return type == "page-primed"
            || type == "calibration"
            || type == "measurement-paused"
    }
    var measurementReady = !hasReadinessMarkers
    var samples: [RawPenSample] = []

    for row in rows {
        switch row["type"] as? String {
        case "measurement-paused":
            measurementReady = false
            continue
        case "page-primed", "calibration":
            measurementReady = true
            continue
        case "sample":
            let explicitlyEligible = row["measurement_eligible"] as? Bool
            guard explicitlyEligible ?? measurementReady else {
                continue
            }
        default:
            continue
        }

        let continuity: SampleContinuity
        switch row["continuity"] as? String {
        case "first":
            continuity = .first
        case "continuous":
            continuity = .continuous
        case "gap":
            continuity = .gap(
                opticalErrors: int(row, "gap_optical_errors"),
                eventCountDelta: UInt8(int(row, "gap_event_count_delta"))
            )
        default:
            throw BenchmarkError(description: "Unknown sample continuity")
        }

        let page: PenPageID?
        if row["page_section"] != nil {
            page = PenPageID(
                section: UInt8(int(row, "page_section")),
                owner: UInt32(int(row, "page_owner")),
                note: UInt32(int(row, "page_note")),
                page: UInt32(int(row, "page_number"))
            )
        } else {
            page = nil
        }

        samples.append(
            RawPenSample(
            id: uint64(row, "id"),
            strokeID: uint64(row, "stroke_id"),
            sampleIndex: int(row, "sample_index"),
            eventCount: UInt8(int(row, "event_count")),
            page: page,
            penTimestampMilliseconds: uint64(row, "pen_ms"),
            receivedWallClockMilliseconds: uint64(row, "received_ms"),
            receivedUptimeNanoseconds: uint64(row, "received_uptime_ns"),
            protocolClockDeltaMilliseconds: Int64(
                int(
                    row,
                    row["protocol_reconstructed_latency_ms"] == nil
                        ? "input_latency_ms"
                        : "protocol_reconstructed_latency_ms"
                )
            ),
            interArrivalMilliseconds: doubleOptional(row, "inter_arrival_ms"),
            x: double(row, "x"),
            y: double(row, "y"),
            force: UInt16(int(row, "force")),
            pressure: doubleOptional(row, "pressure"),
            tiltX: UInt8(int(row, "tilt_x")),
            tiltY: UInt8(int(row, "tilt_y")),
            twist: UInt16(int(row, "twist")),
            continuity: continuity,
            transportBatchID: uint64Optional(row, "transport_batch_id"),
            transportBatchFrameCount: intOptional(
                row,
                "transport_batch_frame_count"
            ),
            transportBatchByteCount: intOptional(
                row,
                "transport_batch_byte_count"
            )
            )
        )
    }

    return LoadedSamples(
        samples: samples,
        filterDescription: hasReadinessMarkers
            ? "measurement-ready samples only"
            : "legacy log without readiness markers"
    )
}

private func evaluateInterpolation(
    _ strokes: [[RawPenSample]],
    algorithm: GapInterpolationAlgorithm,
    useLookahead: Bool = false
) -> InterpolationEvaluation {
    let interpolator = GapInterpolator(algorithm: algorithm)
    var allErrors: [Double] = []
    var curvedErrors: [Double] = []
    var allEligibleCount = 0
    var curvedEligibleCount = 0

    for stroke in strokes where stroke.count >= 4 {
        for hiddenCount in 1...3 {
            guard stroke.count > hiddenCount + 2 else {
                continue
            }
            for index in 2..<(stroke.count - hiddenCount) {
                let previousPrevious = stroke[index - 2]
                let previous = stroke[index - 1]
                let hidden = Array(stroke[index..<(index + hiddenCount)])
                let next = stroke[index + hiddenCount]
                let lookaheadIndex = index + hiddenCount + 1
                let lookahead = lookaheadIndex < stroke.count
                    ? stroke[lookaheadIndex]
                    : nil
                guard previous.continuity == .continuous,
                      (hidden + [next]).allSatisfy({
                          $0.continuity == .continuous
                      }),
                      !useLookahead || lookahead?.continuity == .continuous
                else {
                    continue
                }

                let curved = isCurvedSpan(
                    previousPrevious: previousPrevious,
                    previous: previous,
                    current: next
                )
                allEligibleCount += hidden.count
                if curved {
                    curvedEligibleCount += hidden.count
                }
                let syntheticNext = copy(
                    next,
                    continuity: .gap(
                        opticalErrors: hiddenCount,
                        eventCountDelta: UInt8(hiddenCount + 1)
                    )
                )
                let generated = interpolator.interpolate(
                    previousPrevious: previousPrevious,
                    previous: previous,
                    current: syntheticNext,
                    next: useLookahead ? lookahead : nil
                )
                guard generated.count == hidden.count else {
                    continue
                }
                for (estimate, target) in zip(generated, hidden) {
                    let error = distance(
                        estimate.x,
                        estimate.y,
                        target.x,
                        target.y
                    )
                    allErrors.append(error)
                    if curved {
                        curvedErrors.append(error)
                    }
                }
            }
        }
    }
    return InterpolationEvaluation(
        all: summarize(allErrors, eligibleCount: allEligibleCount),
        curved: summarize(
            curvedErrors,
            eligibleCount: curvedEligibleCount
        )
    )
}

private func evaluatePrediction(
    _ strokes: [[RawPenSample]],
    algorithm: PredictionAlgorithm
) -> PredictionEvaluation {
    let predictor = TrajectoryPredictor(
        algorithm: algorithm,
        options: PredictionOptions(pointCount: 1)
    )
    var errors: [Double] = []
    var leads: [Double] = []
    var eligibleCount = 0

    for stroke in strokes where stroke.count >= 3 {
        for index in 1..<(stroke.count - 1) {
            let history = Array(stroke[0...index])
            let target = stroke[index + 1]
            guard target.continuity == .continuous else {
                continue
            }

            eligibleCount += 1
            guard let estimate = predictor.predict(from: history).first else {
                continue
            }
            errors.append(distance(estimate.x, estimate.y, target.x, target.y))
            let latest = history[history.count - 1]
            leads.append(distance(estimate.x, estimate.y, latest.x, latest.y))
        }
    }
    return PredictionEvaluation(
        error: summarize(errors, eligibleCount: eligibleCount),
        sharedError: evaluateSharedPrediction(
            strokes,
            algorithm: algorithm
        ),
        lead: summarize(leads, eligibleCount: eligibleCount)
    )
}

private func evaluateSharedPrediction(
    _ strokes: [[RawPenSample]],
    algorithm: PredictionAlgorithm
) -> ErrorSummary {
    let algorithms = PredictionAlgorithm.allCases
    let predictors = algorithms.map {
        TrajectoryPredictor(
            algorithm: $0,
            options: PredictionOptions(pointCount: 1)
        )
    }
    var errors: [Double] = []
    var sharedCount = 0

    for stroke in strokes where stroke.count >= 3 {
        for index in 1..<(stroke.count - 1) {
            let history = Array(stroke[0...index])
            let target = stroke[index + 1]
            guard target.continuity == .continuous else {
                continue
            }
            let predictions = predictors.map {
                $0.predict(from: history).first
            }
            guard predictions.allSatisfy({ $0 != nil }) else {
                continue
            }
            sharedCount += 1
            let prediction = predictions[
                algorithms.firstIndex(of: algorithm)!
            ]!
            errors.append(
                distance(
                    prediction.x,
                    prediction.y,
                    target.x,
                    target.y
                )
            )
        }
    }
    return summarize(errors, eligibleCount: sharedCount)
}

private func evaluateGapSmoothness(
    _ strokes: [[RawPenSample]],
    algorithm: GapInterpolationAlgorithm
) -> ErrorSummary {
    let interpolator = GapInterpolator(algorithm: algorithm)
    var angles: [Double] = []
    var eligibleCount = 0

    for stroke in strokes where stroke.count >= 3 {
        for index in 2..<stroke.count {
            let previousPrevious = stroke[index - 2]
            let previous = stroke[index - 1]
            let current = stroke[index]
            guard case .gap = current.continuity else {
                continue
            }
            let generated = interpolator.interpolate(
                previousPrevious: previousPrevious,
                previous: previous,
                current: current
            )
            guard let first = generated.first, let last = generated.last else {
                continue
            }

            eligibleCount += 1
            if let angle = turnAngle(
                firstX: previous.x - previousPrevious.x,
                firstY: previous.y - previousPrevious.y,
                secondX: first.x - previous.x,
                secondY: first.y - previous.y
            ) {
                angles.append(angle)
            }

            guard index + 1 < stroke.count,
                  stroke[index + 1].continuity == .continuous
            else {
                continue
            }
            eligibleCount += 1
            let next = stroke[index + 1]
            if let angle = turnAngle(
                firstX: current.x - last.x,
                firstY: current.y - last.y,
                secondX: next.x - current.x,
                secondY: next.y - current.y
            ) {
                angles.append(angle)
            }
        }
    }
    return summarize(angles, eligibleCount: eligibleCount)
}

private func evaluateReduction(
    _ strokes: [[RawPenSample]]
) -> (
    inputCount: Int,
    outputCount: Int,
    removalRate: Double,
    maximumDeviation: Double
) {
    var inputCount = 0
    var outputCount = 0
    var maximumDeviation = 0.0

    for stroke in strokes {
        let input = stroke.map(renderPoint)
        inputCount += input.count
        var reducer = StreamingPointReducer()
        var output: [RenderPoint] = []
        for point in input {
            output.append(contentsOf: reducer.append(point))
        }
        output.append(contentsOf: reducer.finish())
        outputCount += output.count
        maximumDeviation = max(
            maximumDeviation,
            maximumPolylineDeviation(input: input, output: output)
        )
    }

    return (
        inputCount,
        outputCount,
        inputCount == 0 ? 0 : 1 - Double(outputCount) / Double(inputCount),
        maximumDeviation
    )
}

private func evaluateRefinement(
    _ strokes: [[RawPenSample]]
) -> RefinementSummary {
    let iterations = max(5, 200 / max(1, strokes.count))
    let refiner = PathStrokeRefiner()
    var appliedStrokeCount = 0
    var inputPointCount = 0
    var outputPointCount = 0
    for stroke in strokes {
        inputPointCount += stroke.count
        if let output = refiner.refine(samples: stroke) {
            appliedStrokeCount += 1
            outputPointCount += output.count
        }
    }

    let start = DispatchTime.now().uptimeNanoseconds
    for _ in 0..<iterations {
        for stroke in strokes {
            _ = refiner.refine(samples: stroke)
        }
    }
    let elapsed = DispatchTime.now().uptimeNanoseconds - start
    return RefinementSummary(
        appliedStrokeCount: appliedStrokeCount,
        strokeCount: strokes.count,
        inputPointCount: inputPointCount,
        outputPointCount: outputPointCount,
        nanosecondsPerStroke: Double(elapsed)
            / Double(iterations * max(1, strokes.count))
    )
}

private func evaluateRefinementReduction(
    _ strokes: [[RawPenSample]],
    tolerance: Double
) -> RefinementReductionSummary {
    let refiner = PathStrokeRefiner()
    var inputPointCount = 0
    var outputPointCount = 0
    var maximumDeviation = 0.0

    for stroke in strokes {
        guard let refined = refiner.refine(samples: stroke) else {
            continue
        }
        var reducer = StreamingPointReducer(
            options: PointReductionOptions(
                distanceTolerance: tolerance,
                pressureTolerance: 0.04
            )
        )
        var reduced: [RenderPoint] = []
        for point in refined {
            reduced.append(contentsOf: reducer.append(point))
        }
        reduced.append(contentsOf: reducer.finish())

        inputPointCount += refined.count
        outputPointCount += reduced.count
        maximumDeviation = max(
            maximumDeviation,
            maximumPolylineDeviation(input: refined, output: reduced),
            maximumPolylineDeviation(input: reduced, output: refined)
        )
    }
    return RefinementReductionSummary(
        tolerance: tolerance,
        inputPointCount: inputPointCount,
        outputPointCount: outputPointCount,
        maximumDeviation: maximumDeviation
    )
}

private func benchmark(
    mode: StrokeRenderMode,
    interpolationAlgorithm: GapInterpolationAlgorithm = .linear,
    predictionAlgorithm: PredictionAlgorithm = .safe,
    samples: [RawPenSample]
) -> (iterations: Int, nanosecondsPerSample: Double) {
    let iterations = max(20, 200_000 / samples.count)
    let start = DispatchTime.now().uptimeNanoseconds
    for _ in 0..<iterations {
        let processor = LiveStrokeProcessor(
            mode: mode,
            interpolationAlgorithm: interpolationAlgorithm,
            predictionAlgorithm: predictionAlgorithm
        )
        for sample in samples {
            _ = processor.receive(sample)
        }
        _ = processor.endStroke()
    }
    let elapsed = DispatchTime.now().uptimeNanoseconds - start
    return (
        iterations,
        Double(elapsed) / Double(iterations * samples.count)
    )
}

private func isCurvedSpan(
    previousPrevious: RawPenSample,
    previous: RawPenSample,
    current: RawPenSample
) -> Bool {
    let incomingAngle = atan2(
        previous.y - previousPrevious.y,
        previous.x - previousPrevious.x
    )
    let chordAngle = atan2(
        current.y - previous.y,
        current.x - previous.x
    )
    return abs(normalizedAngle(chordAngle - incomingAngle))
        > 8 * Double.pi / 180
}

private func normalizedAngle(_ angle: Double) -> Double {
    var result = angle
    while result <= -.pi {
        result += 2 * .pi
    }
    while result > .pi {
        result -= 2 * .pi
    }
    return result
}

private func turnAngle(
    firstX: Double,
    firstY: Double,
    secondX: Double,
    secondY: Double
) -> Double? {
    guard hypot(firstX, firstY) > 0, hypot(secondX, secondY) > 0 else {
        return nil
    }
    let firstAngle = atan2(firstY, firstX)
    let secondAngle = atan2(secondY, secondX)
    return abs(normalizedAngle(secondAngle - firstAngle)) * 180 / .pi
}

private func algorithmLabel(
    _ algorithm: GapInterpolationAlgorithm
) -> String {
    switch algorithm {
    case .linear:
        return "Linear"
    case .circularArc:
        return "Circular arc"
    case .cubicBezier:
        return "Cubic Bézier"
    }
}

private func predictionLabel(_ algorithm: PredictionAlgorithm) -> String {
    switch algorithm {
    case .safe:
        return "Safe"
    case .velocity:
        return "Velocity"
    case .curve:
        return "Curve"
    }
}

private func renderPoint(_ sample: RawPenSample) -> RenderPoint {
    RenderPoint(
        x: sample.x,
        y: sample.y,
        pressure: sample.pressure,
        kind: .raw,
        sourceSampleID: sample.id,
        connectsToPrevious: sample.continuity == .continuous
    )
}

private func copy(
    _ sample: RawPenSample,
    continuity: SampleContinuity
) -> RawPenSample {
    RawPenSample(
        id: sample.id,
        strokeID: sample.strokeID,
        sampleIndex: sample.sampleIndex,
        eventCount: sample.eventCount,
        page: sample.page,
        penTimestampMilliseconds: sample.penTimestampMilliseconds,
        receivedWallClockMilliseconds: sample.receivedWallClockMilliseconds,
        receivedUptimeNanoseconds: sample.receivedUptimeNanoseconds,
        protocolClockDeltaMilliseconds: sample.protocolClockDeltaMilliseconds,
        interArrivalMilliseconds: sample.interArrivalMilliseconds,
        x: sample.x,
        y: sample.y,
        force: sample.force,
        pressure: sample.pressure,
        tiltX: sample.tiltX,
        tiltY: sample.tiltY,
        twist: sample.twist,
        continuity: continuity,
        transportBatchID: sample.transportBatchID,
        transportBatchFrameCount: sample.transportBatchFrameCount,
        transportBatchByteCount: sample.transportBatchByteCount
    )
}

private func maximumPolylineDeviation(
    input: [RenderPoint],
    output: [RenderPoint]
) -> Double {
    let inputPaths = splitContinuousPaths(input)
    let outputPaths = splitContinuousPaths(output)
    guard inputPaths.count == outputPaths.count else {
        return .infinity
    }
    return zip(inputPaths, outputPaths).map {
        maximumSubpathDeviation(input: $0, output: $1)
    }.max() ?? 0
}

private func splitContinuousPaths(_ points: [RenderPoint]) -> [[RenderPoint]] {
    var paths: [[RenderPoint]] = []
    var current: [RenderPoint] = []
    for point in points {
        if !point.connectsToPrevious, !current.isEmpty {
            paths.append(current)
            current = []
        }
        current.append(point)
    }
    if !current.isEmpty {
        paths.append(current)
    }
    return paths
}

private func maximumSubpathDeviation(
    input: [RenderPoint],
    output: [RenderPoint]
) -> Double {
    guard !output.isEmpty else {
        return input.isEmpty ? 0 : .infinity
    }
    if output.count == 1 {
        return input.map {
            distance($0.x, $0.y, output[0].x, output[0].y)
        }.max() ?? 0
    }
    return input.map { point in
        zip(output, output.dropFirst()).map {
            distanceToSegment(point, $0, $1)
        }.min() ?? 0
    }.max() ?? 0
}

private func distanceToSegment(
    _ point: RenderPoint,
    _ start: RenderPoint,
    _ end: RenderPoint
) -> Double {
    let dx = end.x - start.x
    let dy = end.y - start.y
    let lengthSquared = dx * dx + dy * dy
    guard lengthSquared > 0 else {
        return distance(point.x, point.y, start.x, start.y)
    }
    let progress = max(
        0,
        min(
            1,
            ((point.x - start.x) * dx + (point.y - start.y) * dy)
                / lengthSquared
        )
    )
    return distance(
        point.x,
        point.y,
        start.x + progress * dx,
        start.y + progress * dy
    )
}

private func summarize(
    _ values: [Double],
    eligibleCount: Int
) -> ErrorSummary {
    guard !values.isEmpty else {
        return ErrorSummary(
            count: 0,
            eligibleCount: eligibleCount,
            mean: nil,
            p50: nil,
            p95: nil,
            maximum: nil
        )
    }
    let sorted = values.sorted()
    return ErrorSummary(
        count: sorted.count,
        eligibleCount: eligibleCount,
        mean: sorted.reduce(0, +) / Double(sorted.count),
        p50: percentile(0.50, sorted),
        p95: percentile(0.95, sorted),
        maximum: sorted.last
    )
}

private func percentile(_ value: Double, _ sorted: [Double]) -> Double {
    let rank = max(1, Int(ceil(value * Double(sorted.count))))
    return sorted[min(sorted.count - 1, rank - 1)]
}

private func printError(_ label: String, _ summary: ErrorSummary) {
    guard let mean = summary.mean,
          let p50 = summary.p50,
          let p95 = summary.p95,
          let maximum = summary.maximum
    else {
        print("\(label): no eligible samples")
        return
    }
    print(
        String(
            format: "%@: n=%d/%d (%.1f%%), mean %.4f, p50 %.4f, p95 %.4f, max %.4f Ncode",
            label,
            summary.count,
            summary.eligibleCount,
            summary.eligibleCount == 0
                ? 0
                : Double(summary.count) / Double(summary.eligibleCount) * 100,
            mean,
            p50,
            p95,
            maximum
        )
    )
}

private func printAngles(_ label: String, _ summary: ErrorSummary) {
    guard let mean = summary.mean,
          let p50 = summary.p50,
          let p95 = summary.p95,
          let maximum = summary.maximum
    else {
        print("\(label): no eligible boundaries")
        return
    }
    print(
        String(
            format: "%@: n=%d/%d, mean %.1f°, p50 %.1f°, p95 %.1f°, max %.1f°",
            label,
            summary.count,
            summary.eligibleCount,
            mean,
            p50,
            p95,
            maximum
        )
    )
}

private func printCost(
    _ label: String,
    _ cost: (iterations: Int, nanosecondsPerSample: Double)
) {
    print(
        String(
            format: "%@ processing: %.1f ns/sample (%d iterations)",
            label,
            cost.nanosecondsPerSample,
            cost.iterations
        )
    )
}

private func modificationDate(_ url: URL) -> Date {
    (
        try? url.resourceValues(forKeys: [.contentModificationDateKey])
            .contentModificationDate
    ) ?? .distantPast
}

private func distance(_ x1: Double, _ y1: Double, _ x2: Double, _ y2: Double) -> Double {
    hypot(x2 - x1, y2 - y1)
}

private func int(_ row: [String: Any], _ key: String) -> Int {
    (row[key] as? NSNumber)?.intValue ?? 0
}

private func intOptional(_ row: [String: Any], _ key: String) -> Int? {
    (row[key] as? NSNumber)?.intValue
}

private func uint64(_ row: [String: Any], _ key: String) -> UInt64 {
    (row[key] as? NSNumber)?.uint64Value ?? 0
}

private func uint64Optional(_ row: [String: Any], _ key: String) -> UInt64? {
    (row[key] as? NSNumber)?.uint64Value
}

private func double(_ row: [String: Any], _ key: String) -> Double {
    (row[key] as? NSNumber)?.doubleValue ?? 0
}

private func doubleOptional(_ row: [String: Any], _ key: String) -> Double? {
    (row[key] as? NSNumber)?.doubleValue
}
