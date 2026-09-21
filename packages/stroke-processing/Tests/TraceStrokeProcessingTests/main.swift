import Darwin
import Foundation
import NeoInput
import TraceStrokeProcessing

private struct TestFailure: Error, CustomStringConvertible {
    let description: String
}

private var failureCount = 0

private func test(_ name: String, _ body: () throws -> Void) {
    do {
        try body()
        print("PASS \(name)")
    } catch {
        failureCount += 1
        fputs("FAIL \(name): \(error)\n", stderr)
    }
}

private func expect(
    _ condition: @autoclosure () -> Bool,
    _ message: String,
    file: StaticString = #filePath,
    line: UInt = #line
) throws {
    guard condition() else {
        throw TestFailure(description: "\(message) (\(file):\(line))")
    }
}

private func rawSample(
    id: UInt64,
    x: Double,
    y: Double,
    pressure: Double = 0.5,
    continuity: SampleContinuity = .continuous
) -> RawPenSample {
    RawPenSample(
        id: id,
        strokeID: 1,
        sampleIndex: Int(id),
        eventCount: UInt8(id),
        page: nil,
        penTimestampMilliseconds: id * 10,
        receivedWallClockMilliseconds: id * 10,
        receivedUptimeNanoseconds: id * 10_000_000,
        protocolClockDeltaMilliseconds: 0,
        interArrivalMilliseconds: 10,
        x: x,
        y: y,
        force: UInt16(pressure * 852),
        pressure: pressure,
        tiltX: 90,
        tiltY: 45,
        twist: 120,
        continuity: id == 0 ? .first : continuity
    )
}

test("stroke width policy separates light normal and firm pressure") {
    let policy = StrokeWidthPolicy(
        minimumWidth: 1,
        maximumWidth: 5.25,
        minimumPressure: 0.2,
        maximumPressure: 0.9,
        responseExponent: 1.2
    )

    let light = policy.width(for: 0.2)
    let normal = policy.width(for: 0.55)
    let firm = policy.width(for: 0.9)
    try expect(abs(light - 1) < 0.000_001, "light width changed")
    try expect(
        abs(normal - 2.849_919_947) < 0.000_001,
        "normal pressure curve changed"
    )
    try expect(abs(firm - 5.25) < 0.000_001, "firm width changed")
    try expect(
        light < normal && normal < firm,
        "pressure no longer increases stroke width"
    )
    try expect(
        policy.width(for: -1) == light
            && policy.width(for: 2) == firm,
        "pressure width stopped clamping sensor outliers"
    )
}

test("nib geometry separates tilt magnitude from twist orientation") {
    let policy = StrokeNibPolicy(
        minimumTiltMagnitude: 15,
        maximumTiltMagnitude: 45,
        maximumAspectRatio: 2.3
    )
    let upright = policy.geometry(
        baseWidth: 4,
        tiltX: 90,
        tiltY: 90,
        twistDegrees: 15
    )
    let firstRotation = policy.geometry(
        baseWidth: 4,
        tiltX: 120,
        tiltY: 90,
        twistDegrees: 15
    )
    let secondRotation = policy.geometry(
        baseWidth: 4,
        tiltX: 90,
        tiltY: 120,
        twistDegrees: 195
    )

    try expect(
        abs(upright.majorAxis - 4) < 0.000_001
            && abs(upright.minorAxis - 4) < 0.000_001,
        "upright nib stopped being circular"
    )
    try expect(
        firstRotation.majorAxis > firstRotation.minorAxis,
        "tilt no longer elongates the nib"
    )
    try expect(
        abs(firstRotation.majorAxis - secondRotation.majorAxis)
            < 0.000_001
            && abs(firstRotation.minorAxis - secondRotation.minorAxis)
                < 0.000_001,
        "barrel rotation changed tilt magnitude"
    )
    try expect(
        abs(
            firstRotation.majorAxis * firstRotation.minorAxis - 16
        ) < 0.000_001,
        "tilt changed the pressure-defined nib area"
    )
    try expect(
        abs(firstRotation.rotationRadians - .pi / 12) < 0.000_001
            && abs(secondRotation.rotationRadians - .pi / 12)
                < 0.000_001,
        "twist stopped wrapping modulo 180 degrees"
    )
}

test("swept nib width follows path direction without stamping anchors") {
    let geometry = StrokeNibGeometry(
        majorAxis: 8,
        minorAxis: 2,
        rotationRadians: 0
    )
    try expect(
        abs(
            geometry.sweptWidth(
                directionX: 1,
                directionY: 0
            ) - 2
        ) < 0.000_001,
        "horizontal sweep did not use the nib minor axis"
    )
    try expect(
        abs(
            geometry.sweptWidth(
                directionX: 0,
                directionY: 1
            ) - 8
        ) < 0.000_001,
        "vertical sweep did not use the nib major axis"
    )
}

test("only continuous path endpoints receive nib caps") {
    try expect(
        StrokePathTopology.isEndpoint(
            hasPrevious: false,
            connectsToPrevious: false,
            hasNext: true,
            nextConnectsToPrevious: true
        ),
        "stroke start lost its nib cap"
    )
    try expect(
        !StrokePathTopology.isEndpoint(
            hasPrevious: true,
            connectsToPrevious: true,
            hasNext: true,
            nextConnectsToPrevious: true
        ),
        "interior anchor was rendered as a nib cap"
    )
    try expect(
        StrokePathTopology.isEndpoint(
            hasPrevious: true,
            connectsToPrevious: true,
            hasNext: false,
            nextConnectsToPrevious: false
        ),
        "stroke end lost its nib cap"
    )
}

test("raw mode emits only the received sample") {
    let processor = LiveStrokeProcessor(mode: .raw)
    let sample = rawSample(id: 0, x: 10, y: 20)
    let update = processor.receive(sample)

    try expect(update.committed.count == 1, "raw sample was not emitted")
    try expect(update.committed[0].kind == .raw, "raw sample changed kind")
    try expect(update.committed[0].sourceSampleID == 0, "raw identity was lost")
    try expect(
        update.committed[0].tiltX == 90
            && update.committed[0].tiltY == 45
            && update.committed[0].twistDegrees == 120,
        "raw nib orientation was lost"
    )
    try expect(update.predicted.isEmpty, "raw mode predicted points")
}

test("gap interpolation fills a straight two-point hole") {
    let processor = LiveStrokeProcessor(
        mode: .interpolate,
        interpolationOptions: GapInterpolationOptions(
            maximumPoints: 8,
            minimumTargetSpacing: 0.01
        )
    )
    _ = processor.receive(rawSample(id: 0, x: 0, y: 0))
    _ = processor.receive(rawSample(id: 1, x: 0, y: 0))
    let update = processor.receive(
        rawSample(
            id: 4,
            x: 3,
            y: 0,
            pressure: 0.8,
            continuity: .gap(opticalErrors: 2, eventCountDelta: 3)
        )
    )

    let interpolated = update.committed.filter { $0.kind == .interpolated }
    try expect(interpolated.count == 2, "wrong interpolation count")
    try expect(abs(interpolated[0].x - 1) < 0.000_001, "first gap point changed")
    try expect(abs(interpolated[1].x - 2) < 0.000_001, "second gap point changed")
    try expect(
        abs((interpolated[0].pressure ?? 0) - 0.6) < 0.000_001,
        "interpolated pressure changed"
    )
    try expect(
        abs((interpolated[1].pressure ?? 0) - 0.7) < 0.000_001,
        "interpolated pressure changed"
    )
    try expect(update.committed.last?.kind == .raw, "real endpoint was lost")
}

test("circular arc interpolation rounds a known circle gap") {
    let processor = LiveStrokeProcessor(
        mode: .interpolate,
        interpolationAlgorithm: .circularArc,
        interpolationOptions: GapInterpolationOptions(
            maximumPoints: 8,
            minimumTargetSpacing: 0.01
        )
    )
    _ = processor.receive(rawSample(id: 0, x: 1, y: 0))
    _ = processor.receive(
        rawSample(
            id: 1,
            x: sqrt(3) / 2,
            y: 0.5
        )
    )
    let update = processor.receive(
        rawSample(
            id: 3,
            x: 0,
            y: 1,
            continuity: .gap(opticalErrors: 1, eventCountDelta: 2)
        )
    )

    let interpolated = update.committed.filter { $0.kind == .interpolated }
    try expect(interpolated.count == 1, "arc interpolation count changed")
    try expect(
        abs(interpolated[0].x - 0.5) < 0.000_001,
        "arc did not preserve circular curvature"
    )
    try expect(
        abs(interpolated[0].y - sqrt(3) / 2) < 0.000_001,
        "arc did not preserve circular curvature"
    )
}

test("cubic bezier interpolation preserves the incoming tangent") {
    let processor = LiveStrokeProcessor(
        mode: .interpolate,
        interpolationAlgorithm: .cubicBezier,
        interpolationOptions: GapInterpolationOptions(
            maximumPoints: 8,
            minimumTargetSpacing: 0.01
        )
    )
    _ = processor.receive(rawSample(id: 0, x: 0, y: 0))
    _ = processor.receive(rawSample(id: 1, x: 1, y: 0))
    let update = processor.receive(
        rawSample(
            id: 3,
            x: 2,
            y: 1,
            continuity: .gap(opticalErrors: 1, eventCountDelta: 2)
        )
    )

    let interpolated = update.committed.filter { $0.kind == .interpolated }
    try expect(interpolated.count == 1, "Bézier interpolation count changed")
    try expect(
        abs(interpolated[0].x - (1 + 1 / sqrt(2))) < 0.000_001,
        "Bézier control geometry changed"
    )
    try expect(
        abs(interpolated[0].y - (1 - 1 / sqrt(2))) < 0.000_001,
        "Bézier no longer eases from the incoming tangent"
    )
}

test("two-sided bezier keeps an aligned gap straight") {
    let interpolator = GapInterpolator(algorithm: .cubicBezier)
    let generated = interpolator.interpolate(
        previousPrevious: rawSample(id: 0, x: 0, y: 0),
        previous: rawSample(id: 1, x: 1, y: 0),
        current: rawSample(
            id: 4,
            x: 3,
            y: 1,
            continuity: .gap(opticalErrors: 2, eventCountDelta: 3)
        ),
        next: rawSample(id: 5, x: 4, y: 1)
    )

    try expect(generated.count == 2, "two-sided straight gap count changed")
    try expect(
        abs(generated[0].x - (5.0 / 3.0)) < 0.000_001
            && abs(generated[0].y - (1.0 / 3.0)) < 0.000_001
            && abs(generated[1].x - (7.0 / 3.0)) < 0.000_001
            && abs(generated[1].y - (2.0 / 3.0)) < 0.000_001,
        "aligned boundary vectors no longer produce a straight gap"
    )
}

test("two-sided bezier follows a changed outgoing vector") {
    let interpolator = GapInterpolator(algorithm: .cubicBezier)
    let generated = interpolator.interpolate(
        previousPrevious: rawSample(id: 0, x: 0, y: 0),
        previous: rawSample(id: 1, x: 1, y: 0),
        current: rawSample(
            id: 3,
            x: 2,
            y: 1,
            continuity: .gap(opticalErrors: 1, eventCountDelta: 2)
        ),
        next: rawSample(id: 4, x: 3, y: 2)
    )

    try expect(generated.count == 1, "two-sided curved gap count changed")
    try expect(
        abs(generated[0].x - 1.551_776_695) < 0.000_001
            && abs(generated[0].y - 0.375) < 0.000_001,
        "outgoing vector no longer shapes the missing curve"
    )
}

test("curve interpolation falls back to linear when curvature is unsafe") {
    for algorithm in [
        GapInterpolationAlgorithm.circularArc,
        .cubicBezier,
    ] {
        let processor = LiveStrokeProcessor(
            mode: .interpolate,
            interpolationAlgorithm: algorithm,
            interpolationOptions: GapInterpolationOptions(
                maximumPoints: 8,
                minimumTargetSpacing: 0.01
            )
        )
        _ = processor.receive(rawSample(id: 0, x: 0, y: 0))
        _ = processor.receive(rawSample(id: 1, x: 1, y: 0))
        let update = processor.receive(
            rawSample(
                id: 3,
                x: 2,
                y: 0,
                continuity: .gap(opticalErrors: 1, eventCountDelta: 2)
            )
        )
        let interpolated = update.committed.filter {
            $0.kind == .interpolated
        }

        try expect(
            interpolated.count == 1,
            "\(algorithm.rawValue) fallback count changed"
        )
        try expect(
            abs(interpolated[0].x - 1.5) < 0.000_001
                && abs(interpolated[0].y) < 0.000_001,
            "\(algorithm.rawValue) did not fall back to linear"
        )
    }
}

test("path smoothing preserves an open ellipse and its endpoints") {
    let processor = LiveStrokeProcessor(
        mode: .interpolate,
        refinementAlgorithm: .smoothPath
    )
    var input: [(x: Double, y: Double)] = []
    for index in 0...10 {
        let angle = Double(index) * 5 * .pi / 30
        let point = (x: 2 * cos(angle), y: sin(angle))
        input.append(point)
        _ = processor.receive(
            rawSample(
                id: UInt64(index),
                x: point.x,
                y: point.y
            )
        )
    }
    let replacement = processor.endStroke()?.replacement

    guard let replacement else {
        throw TestFailure(description: "open ellipse was not smoothed")
    }
    try expect(
        replacement.allSatisfy { $0.kind == .refined },
        "smoothed path was not labeled as refined"
    )
    try expect(
        replacement.count > input.count,
        "post-stroke path was not actually smoothed"
    )
    try expect(
        replacement.count < input.count * 4,
        "smoothed display path kept redundant tessellation points"
    )
    let first = replacement[0]
    let last = replacement[replacement.count - 1]
    try expect(
        abs(first.x - input[0].x) < 0.000_001
            && abs(first.y - input[0].y) < 0.000_001
            && abs(last.x - input[10].x) < 0.000_001
            && abs(last.y - input[10].y) < 0.000_001,
        "smoothing changed the open endpoints"
    )
    try expect(
        hypot(last.x - first.x, last.y - first.y) > 0.5,
        "smoothing closed an intentionally open path"
    )
    let width = replacement.map(\.x).max()! - replacement.map(\.x).min()!
    let height = replacement.map(\.y).max()! - replacement.map(\.y).min()!
    try expect(
        width / height > 1.5,
        "smoothing replaced the ellipse aspect ratio"
    )
}

test("path smoothing preserves an explicit sensor discontinuity") {
    let processor = LiveStrokeProcessor(
        mode: .interpolate,
        refinementAlgorithm: .smoothPath
    )
    for index in 0..<4 {
        _ = processor.receive(
            rawSample(
                id: UInt64(index),
                x: Double(index),
                y: index.isMultiple(of: 2) ? 0.1 : -0.1,
                continuity: index == 3
                    ? .gap(opticalErrors: 0, eventCountDelta: 1)
                    : .continuous
            )
        )
    }
    let replacement = processor.endStroke()?.replacement
    try expect(
        replacement?.filter { !$0.connectsToPrevious }.count == 2,
        "smoothing bridged a measured discontinuity"
    )
}

test("path smoothing respects its maximum deviation bound") {
    let refiner = PathStrokeRefiner(
        options: PathSmoothingOptions(maximumDeviation: 0)
    )
    let points = [
        RenderPoint(
            x: 0,
            y: 0,
            pressure: 0.5,
            kind: .raw,
            sourceSampleID: 1,
            connectsToPrevious: false
        ),
        RenderPoint(
            x: 1,
            y: 1,
            pressure: 0.5,
            kind: .raw,
            sourceSampleID: 2,
            connectsToPrevious: true
        ),
        RenderPoint(
            x: 2,
            y: 0,
            pressure: 0.5,
            kind: .raw,
            sourceSampleID: 3,
            connectsToPrevious: true
        ),
    ]

    try expect(
        refiner.refine(points) == nil,
        "smoothing exceeded a zero-deviation budget"
    )
}

test("path smoothing checks segment interiors against its deviation bound") {
    let coordinates: [(Double, Double)] = [
        (1.457_737_973_711_324_5, 2.915_475_947_422_649),
        (1.457_737_973_711_324_5, -2.915_475_947_422_649),
        (-2.915_475_947_422_649, -1.457_737_973_711_324_5),
        (-2.915_475_947_422_649, -2.915_475_947_422_649),
        (1.457_737_973_711_324_5, -2.915_475_947_422_649),
    ]
    let points = coordinates.enumerated().map { index, coordinate in
        RenderPoint(
            x: coordinate.0,
            y: coordinate.1,
            pressure: 0.5,
            kind: .raw,
            sourceSampleID: UInt64(index),
            connectsToPrevious: index > 0
        )
    }

    try expect(
        PathStrokeRefiner().refine(points) == nil,
        "segment interior exceeded the smoothing deviation bound"
    )
}

test("raw mode never applies post-stroke path smoothing") {
    let processor = LiveStrokeProcessor(
        mode: .raw,
        refinementAlgorithm: .smoothPath
    )
    for index in 0...8 {
        let angle = Double(index) * .pi / 4
        _ = processor.receive(
            rawSample(
                id: UInt64(index),
                x: cos(angle),
                y: sin(angle)
            )
        )
    }

    try expect(
        processor.endStroke()?.replacement == nil,
        "Raw mode replaced measured input"
    )
}

test("trajectory predictor extrapolates a bounded straight tail") {
    let predictor = TrajectoryPredictor(
        options: PredictionOptions(
            pointCount: 3,
            damping: 1,
            accelerationWeight: 0,
            maximumStepMultiplier: 1.5,
            maximumStepDistance: 2
        )
    )
    let predictions = predictor.predict(
        from: [
            rawSample(id: 0, x: 0, y: 0),
            rawSample(id: 1, x: 1, y: 0),
            rawSample(id: 2, x: 2, y: 0),
        ]
    )

    try expect(predictions.count == 3, "prediction horizon changed")
    try expect(abs(predictions[0].x - 3) < 0.000_001, "first prediction changed")
    try expect(abs(predictions[2].x - 5) < 0.000_001, "third prediction changed")
    try expect(predictions.allSatisfy { $0.kind == .predicted }, "prediction kind changed")
}

test("velocity prediction continues the latest measured displacement") {
    let predictor = TrajectoryPredictor(
        algorithm: .velocity,
        options: PredictionOptions(
            pointCount: 3,
            maximumStepMultiplier: 2,
            maximumStepDistance: 2
        )
    )
    let predictions = predictor.predict(
        from: [
            rawSample(id: 0, x: 0, y: 0),
            rawSample(id: 1, x: 1, y: 0),
        ]
    )

    try expect(predictions.count == 3, "velocity horizon changed")
    try expect(
        predictions.map(\.x) == [2, 3, 4]
            && predictions.allSatisfy { abs($0.y) < 0.000_001 },
        "velocity predictor changed the latest displacement"
    )
}

test("curve prediction continues the measured turn") {
    let predictor = TrajectoryPredictor(
        algorithm: .curve,
        options: PredictionOptions(
            pointCount: 2,
            maximumStepMultiplier: 2,
            maximumStepDistance: 2,
            curveDamping: 1,
            maximumCurveTurnRadians: .pi / 2
        )
    )
    let predictions = predictor.predict(
        from: [
            rawSample(id: 0, x: 0, y: 0),
            rawSample(id: 1, x: 1, y: 0),
            rawSample(
                id: 2,
                x: 1 + sqrt(3) / 2,
                y: 0.5
            ),
        ]
    )

    try expect(predictions.count == 2, "curve horizon changed")
    try expect(
        abs(predictions[0].x - (1.5 + sqrt(3) / 2)) < 0.000_001
            && abs(predictions[0].y - (0.5 + sqrt(3) / 2))
                < 0.000_001,
        "curve predictor did not continue the observed turn"
    )
    try expect(
        abs(predictions[1].x - predictions[0].x) < 0.000_001
            && abs(predictions[1].y - (1.5 + sqrt(3) / 2))
                < 0.000_001,
        "curve predictor did not keep turning"
    )
}

test("prediction algorithms never cross an optical gap") {
    for algorithm in PredictionAlgorithm.allCases {
        let predictor = TrajectoryPredictor(algorithm: algorithm)
        let predictions = predictor.predict(
            from: [
                rawSample(id: 0, x: 0, y: 0),
                rawSample(id: 1, x: 1, y: 0),
                rawSample(
                    id: 2,
                    x: 2,
                    y: 0,
                    continuity: .gap(
                        opticalErrors: 1,
                        eventCountDelta: 2
                    )
                ),
            ]
        )

        try expect(
            predictions.isEmpty,
            "\(algorithm.rawValue) predicted across an optical gap"
        )
    }
}

test("trajectory predictor extrapolates and clamps pressure trend") {
    let predictor = TrajectoryPredictor(
        options: PredictionOptions(
            pointCount: 3,
            damping: 1,
            accelerationWeight: 0,
            maximumStepMultiplier: 1.5,
            maximumStepDistance: 2
        )
    )
    let predictions = predictor.predict(
        from: [
            rawSample(id: 0, x: 0, y: 0, pressure: 0.2),
            rawSample(id: 1, x: 1, y: 0, pressure: 0.4),
            rawSample(id: 2, x: 2, y: 0, pressure: 0.6),
        ]
    )

    let pressures = predictions.compactMap(\.pressure)
    try expect(pressures.count == 3, "predicted pressure was missing")
    try expect(abs(pressures[0] - 0.8) < 0.000_001, "pressure trend changed")
    try expect(
        abs(pressures[1] - 1) < 0.000_001
            && abs(pressures[2] - 1) < 0.000_001,
        "pressure was not clamped"
    )
}

test("trajectory predictor refuses a sharp reversal") {
    let predictor = TrajectoryPredictor()
    let predictions = predictor.predict(
        from: [
            rawSample(id: 0, x: 0, y: 0),
            rawSample(id: 1, x: 1, y: 0),
            rawSample(id: 2, x: 0.2, y: 0),
        ]
    )

    try expect(predictions.isEmpty, "sharp reversal produced a speculative tail")
}

test("streaming reducer removes redundant collinear points") {
    var reducer = StreamingPointReducer(
        options: PointReductionOptions(
            distanceTolerance: 0.01,
            pressureTolerance: 0.05
        )
    )
    var output: [RenderPoint] = []
    for index in 0...20 {
        output.append(
            contentsOf: reducer.append(
                RenderPoint(
                    x: Double(index),
                    y: 0,
                    pressure: 0.5,
                    kind: .raw,
                    sourceSampleID: UInt64(index),
                    connectsToPrevious: index > 0
                )
            )
        )
    }
    output.append(contentsOf: reducer.finish())

    try expect(output.count == 2, "collinear path was not reduced to endpoints")
    try expect(output.first?.x == 0 && output.last?.x == 20, "endpoints changed")
}

test("streaming reducer preserves pressure changes and gaps") {
    var reducer = StreamingPointReducer()
    let points = [
        RenderPoint(
            x: 0,
            y: 0,
            pressure: 0.2,
            kind: .raw,
            sourceSampleID: 1,
            connectsToPrevious: false
        ),
        RenderPoint(
            x: 1,
            y: 0,
            pressure: 0.8,
            kind: .raw,
            sourceSampleID: 2,
            connectsToPrevious: true
        ),
        RenderPoint(
            x: 2,
            y: 0,
            pressure: 0.8,
            kind: .raw,
            sourceSampleID: 3,
            connectsToPrevious: false
        ),
    ]
    let output = points.flatMap { reducer.append($0) } + reducer.finish()

    try expect(output == points, "pressure or gap evidence was reduced")
}

if failureCount > 0 {
    fputs("\(failureCount) test(s) failed\n", stderr)
    exit(1)
}

print("All Trace stroke processing tests passed.")
