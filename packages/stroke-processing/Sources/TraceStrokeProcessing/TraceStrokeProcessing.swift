import Foundation
import NeoInput

public enum StrokeRenderMode: String, CaseIterable, Equatable, Sendable {
    case raw
    case interpolate
    case predict
}

public enum GapInterpolationAlgorithm: String, CaseIterable, Equatable, Sendable {
    case linear
    case circularArc = "circular-arc"
    case cubicBezier = "cubic-bezier"
}

public enum StrokeRefinementAlgorithm: String, CaseIterable, Equatable, Sendable {
    case none
    case smoothPath = "smooth-path"
}

public enum PredictionAlgorithm: String, CaseIterable, Equatable, Sendable {
    case safe
    case velocity
    case curve
}

public enum RenderPointKind: String, Equatable, Sendable {
    case raw
    case interpolated
    case predicted
    case refined
}

public struct StrokeWidthPolicy: Equatable, Sendable {
    public let minimumWidth: Double
    public let maximumWidth: Double
    public let minimumPressure: Double
    public let maximumPressure: Double
    public let responseExponent: Double
    public let fallbackPressure: Double

    public init(
        minimumWidth: Double = 1,
        maximumWidth: Double = 5.25,
        minimumPressure: Double = 0.2,
        maximumPressure: Double = 0.9,
        responseExponent: Double = 1.2,
        fallbackPressure: Double = 0.55
    ) {
        precondition(minimumWidth > 0)
        precondition(maximumWidth >= minimumWidth)
        precondition(maximumPressure > minimumPressure)
        precondition(responseExponent > 0)
        self.minimumWidth = minimumWidth
        self.maximumWidth = maximumWidth
        self.minimumPressure = minimumPressure
        self.maximumPressure = maximumPressure
        self.responseExponent = responseExponent
        self.fallbackPressure = fallbackPressure
    }

    public func width(for pressure: Double?) -> Double {
        let pressure = pressure ?? fallbackPressure
        let normalized = min(
            1,
            max(
                0,
                (pressure - minimumPressure)
                    / (maximumPressure - minimumPressure)
            )
        )
        return minimumWidth
            + (maximumWidth - minimumWidth)
                * pow(normalized, responseExponent)
    }
}

public struct StrokeNibGeometry: Equatable, Sendable {
    public let majorAxis: Double
    public let minorAxis: Double
    public let rotationRadians: Double

    public init(
        majorAxis: Double,
        minorAxis: Double,
        rotationRadians: Double
    ) {
        self.majorAxis = majorAxis
        self.minorAxis = minorAxis
        self.rotationRadians = rotationRadians
    }

    public func sweptWidth(
        directionX: Double,
        directionY: Double
    ) -> Double {
        let directionLength = hypot(directionX, directionY)
        guard directionLength > 0.000_001 else {
            return minorAxis
        }
        let normalX = -directionY / directionLength
        let normalY = directionX / directionLength
        let majorX = cos(rotationRadians)
        let majorY = sin(rotationRadians)
        let minorX = -majorY
        let minorY = majorX
        let majorProjection = normalX * majorX + normalY * majorY
        let minorProjection = normalX * minorX + normalY * minorY
        let majorRadius = majorAxis / 2
        let minorRadius = minorAxis / 2
        return 2 * sqrt(
            pow(majorRadius * majorProjection, 2)
                + pow(minorRadius * minorProjection, 2)
        )
    }
}

public enum StrokePathTopology {
    public static func isEndpoint(
        hasPrevious: Bool,
        connectsToPrevious: Bool,
        hasNext: Bool,
        nextConnectsToPrevious: Bool
    ) -> Bool {
        !hasPrevious
            || !connectsToPrevious
            || !hasNext
            || !nextConnectsToPrevious
    }
}

public struct StrokeNibPolicy: Equatable, Sendable {
    public let minimumTiltMagnitude: Double
    public let maximumTiltMagnitude: Double
    public let maximumAspectRatio: Double

    public init(
        minimumTiltMagnitude: Double = 15,
        maximumTiltMagnitude: Double = 45,
        maximumAspectRatio: Double = 2.3
    ) {
        precondition(minimumTiltMagnitude >= 0)
        precondition(maximumTiltMagnitude > minimumTiltMagnitude)
        precondition(maximumAspectRatio >= 1)
        self.minimumTiltMagnitude = minimumTiltMagnitude
        self.maximumTiltMagnitude = maximumTiltMagnitude
        self.maximumAspectRatio = maximumAspectRatio
    }

    public func geometry(
        baseWidth: Double,
        tiltX: Double?,
        tiltY: Double?,
        twistDegrees: Double?
    ) -> StrokeNibGeometry {
        let tiltMagnitude = hypot(
            (tiltX ?? 90) - 90,
            (tiltY ?? 90) - 90
        )
        let normalizedTilt = min(
            1,
            max(
                0,
                (tiltMagnitude - minimumTiltMagnitude)
                    / (maximumTiltMagnitude - minimumTiltMagnitude)
            )
        )
        let aspectRatio = 1
            + (maximumAspectRatio - 1) * normalizedTilt
        let aspectScale = sqrt(aspectRatio)
        var rotationDegrees = (twistDegrees ?? 0)
            .truncatingRemainder(dividingBy: 180)
        if rotationDegrees < 0 {
            rotationDegrees += 180
        }
        return StrokeNibGeometry(
            majorAxis: baseWidth * aspectScale,
            minorAxis: baseWidth / aspectScale,
            rotationRadians: rotationDegrees * .pi / 180
        )
    }
}

public struct RenderPoint: Equatable, Sendable {
    public let x: Double
    public let y: Double
    public let pressure: Double?
    public let tiltX: Double?
    public let tiltY: Double?
    public let twistDegrees: Double?
    public let kind: RenderPointKind
    public let sourceSampleID: UInt64?
    public let connectsToPrevious: Bool
    public let marksGap: Bool

    public init(
        x: Double,
        y: Double,
        pressure: Double?,
        tiltX: Double? = nil,
        tiltY: Double? = nil,
        twistDegrees: Double? = nil,
        kind: RenderPointKind,
        sourceSampleID: UInt64?,
        connectsToPrevious: Bool,
        marksGap: Bool = false
    ) {
        self.x = x
        self.y = y
        self.pressure = pressure
        self.tiltX = tiltX
        self.tiltY = tiltY
        self.twistDegrees = twistDegrees
        self.kind = kind
        self.sourceSampleID = sourceSampleID
        self.connectsToPrevious = connectsToPrevious
        self.marksGap = marksGap
    }
}

public struct StrokeRenderUpdate: Equatable, Sendable {
    public let strokeID: UInt64
    public let committed: [RenderPoint]
    public let predicted: [RenderPoint]
    public let replacement: [RenderPoint]?

    public init(
        strokeID: UInt64,
        committed: [RenderPoint],
        predicted: [RenderPoint],
        replacement: [RenderPoint]? = nil
    ) {
        self.strokeID = strokeID
        self.committed = committed
        self.predicted = predicted
        self.replacement = replacement
    }
}

public struct GapInterpolationOptions: Equatable, Sendable {
    public let maximumPoints: Int
    public let minimumTargetSpacing: Double

    public init(
        maximumPoints: Int = 12,
        minimumTargetSpacing: Double = 0.05
    ) {
        precondition(maximumPoints > 0)
        precondition(minimumTargetSpacing > 0)
        self.maximumPoints = maximumPoints
        self.minimumTargetSpacing = minimumTargetSpacing
    }
}

public struct PredictionOptions: Equatable, Sendable {
    public let pointCount: Int
    public let damping: Double
    public let accelerationWeight: Double
    public let maximumStepMultiplier: Double
    public let maximumStepDistance: Double
    public let minimumDirectionCosine: Double
    public let minimumSpeedRatio: Double
    public let maximumSpeedRatio: Double
    public let curveDamping: Double
    public let maximumCurveTurnRadians: Double

    public init(
        pointCount: Int = 3,
        damping: Double = 0.82,
        accelerationWeight: Double = 0.2,
        maximumStepMultiplier: Double = 1.5,
        maximumStepDistance: Double = 0.35,
        minimumDirectionCosine: Double = 0.85,
        minimumSpeedRatio: Double = 0.6,
        maximumSpeedRatio: Double = 1.8,
        curveDamping: Double = 0.9,
        maximumCurveTurnRadians: Double = .pi / 4
    ) {
        precondition(pointCount >= 0)
        precondition(damping > 0 && damping <= 1)
        precondition(accelerationWeight >= 0)
        precondition(maximumStepMultiplier > 0)
        precondition(maximumStepDistance > 0)
        precondition((-1...1).contains(minimumDirectionCosine))
        precondition(minimumSpeedRatio > 0)
        precondition(maximumSpeedRatio >= minimumSpeedRatio)
        precondition(curveDamping > 0 && curveDamping <= 1)
        precondition(maximumCurveTurnRadians > 0)
        self.pointCount = pointCount
        self.damping = damping
        self.accelerationWeight = accelerationWeight
        self.maximumStepMultiplier = maximumStepMultiplier
        self.maximumStepDistance = maximumStepDistance
        self.minimumDirectionCosine = minimumDirectionCosine
        self.minimumSpeedRatio = minimumSpeedRatio
        self.maximumSpeedRatio = maximumSpeedRatio
        self.curveDamping = curveDamping
        self.maximumCurveTurnRadians = maximumCurveTurnRadians
    }
}

public struct PointReductionOptions: Equatable, Sendable {
    public let distanceTolerance: Double
    public let pressureTolerance: Double

    public init(
        distanceTolerance: Double = 0.03,
        pressureTolerance: Double = 0.04
    ) {
        precondition(distanceTolerance >= 0)
        precondition(pressureTolerance >= 0)
        self.distanceTolerance = distanceTolerance
        self.pressureTolerance = pressureTolerance
    }
}

public struct PathSmoothingOptions: Equatable, Sendable {
    public let iterations: Int
    public let cornerCuttingRatio: Double
    public let maximumDeviation: Double
    public let maximumOutputPointCount: Int
    public let outputReductionOptions: PointReductionOptions

    public init(
        iterations: Int = 2,
        cornerCuttingRatio: Double = 0.2,
        maximumDeviation: Double = 0.35,
        maximumOutputPointCount: Int = 1_024,
        outputReductionOptions: PointReductionOptions =
            PointReductionOptions(
                distanceTolerance: 0.01,
                pressureTolerance: 0.04
            )
    ) {
        precondition(iterations > 0)
        precondition(cornerCuttingRatio > 0 && cornerCuttingRatio < 0.5)
        precondition(maximumDeviation >= 0)
        precondition(maximumOutputPointCount > 0)
        self.iterations = iterations
        self.cornerCuttingRatio = cornerCuttingRatio
        self.maximumDeviation = maximumDeviation
        self.maximumOutputPointCount = maximumOutputPointCount
        self.outputReductionOptions = outputReductionOptions
    }
}

public struct PathStrokeRefiner {
    public let options: PathSmoothingOptions

    public init(options: PathSmoothingOptions = PathSmoothingOptions()) {
        self.options = options
    }

    public func refine(samples: [RawPenSample]) -> [RenderPoint]? {
        refine(reconstructedPath(from: samples))
    }

    public func refine(_ points: [RenderPoint]) -> [RenderPoint]? {
        let paths = splitContinuousPaths(points)
        guard paths.contains(where: { $0.count >= 3 }) else {
            return nil
        }

        for iterationCount in stride(
            from: options.iterations,
            through: 1,
            by: -1
        ) {
            let smoothedPaths = paths.map {
                smooth($0, iterations: iterationCount)
            }
            let refinedPaths = smoothedPaths.map(reduce)
            let outputCount = refinedPaths.reduce(0) {
                $0 + $1.count
            }
            guard outputCount <= options.maximumOutputPointCount else {
                continue
            }
            guard zip(paths, refinedPaths).allSatisfy({
                isWithinDeviation(
                    between: $0,
                    and: $1,
                    limit: options.maximumDeviation
                )
            }) else {
                continue
            }
            return refinedPaths.flatMap { $0 }
        }
        return nil
    }

    private func reduce(_ points: [RenderPoint]) -> [RenderPoint] {
        var reducer = StreamingPointReducer(
            options: options.outputReductionOptions
        )
        var output: [RenderPoint] = []
        for point in points {
            output.append(contentsOf: reducer.append(point))
        }
        output.append(contentsOf: reducer.finish())
        return output
    }

    private func reconstructedPath(
        from samples: [RawPenSample]
    ) -> [RenderPoint] {
        let interpolator = GapInterpolator(algorithm: .cubicBezier)
        var output: [RenderPoint] = []
        for index in samples.indices {
            let sample = samples[index]
            var interpolated: [RenderPoint] = []
            if index > samples.startIndex {
                interpolated = interpolator.interpolate(
                    previousPrevious: index >= 2
                        ? samples[index - 2]
                        : nil,
                    previous: samples[index - 1],
                    current: sample,
                    next: index + 1 < samples.endIndex
                        ? samples[index + 1]
                        : nil
                )
                output.append(contentsOf: interpolated)
            }
            output.append(
                RenderPoint(
                    x: sample.x,
                    y: sample.y,
                    pressure: sample.pressure,
                    tiltX: Double(sample.tiltX),
                    tiltY: Double(sample.tiltY),
                    twistDegrees: Double(sample.twist),
                    kind: .raw,
                    sourceSampleID: sample.id,
                    connectsToPrevious: sample.continuity == .continuous
                        || !interpolated.isEmpty,
                    marksGap: {
                        if case .gap = sample.continuity {
                            return true
                        }
                        return false
                    }()
                )
            )
        }
        return output
    }

    private func splitContinuousPaths(
        _ points: [RenderPoint]
    ) -> [[RenderPoint]] {
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

    private func smooth(
        _ points: [RenderPoint],
        iterations: Int
    ) -> [RenderPoint] {
        guard points.count >= 3 else {
            return refined(points)
        }
        var output = points
        for _ in 0..<iterations {
            var next: [RenderPoint] = [refined(output[0], connects: false)]
            for (first, second) in zip(output, output.dropFirst()) {
                next.append(
                    interpolate(
                        first,
                        second,
                        progress: options.cornerCuttingRatio
                    )
                )
                next.append(
                    interpolate(
                        first,
                        second,
                        progress: 1 - options.cornerCuttingRatio
                    )
                )
            }
            next.append(
                refined(output[output.count - 1], connects: true)
            )
            output = next
        }
        return output
    }

    private func refined(_ points: [RenderPoint]) -> [RenderPoint] {
        points.enumerated().map {
            refined($0.element, connects: $0.offset > 0)
        }
    }

    private func refined(
        _ point: RenderPoint,
        connects: Bool
    ) -> RenderPoint {
        RenderPoint(
            x: point.x,
            y: point.y,
            pressure: point.pressure,
            tiltX: point.tiltX,
            tiltY: point.tiltY,
            twistDegrees: point.twistDegrees,
            kind: .refined,
            sourceSampleID: nil,
            connectsToPrevious: connects
        )
    }

    private func interpolate(
        _ first: RenderPoint,
        _ second: RenderPoint,
        progress: Double
    ) -> RenderPoint {
        RenderPoint(
            x: first.x + (second.x - first.x) * progress,
            y: first.y + (second.y - first.y) * progress,
            pressure: interpolatePressure(
                first.pressure,
                second.pressure,
                progress: progress
            ),
            tiltX: interpolateOptional(
                first.tiltX,
                second.tiltX,
                progress: progress
            ),
            tiltY: interpolateOptional(
                first.tiltY,
                second.tiltY,
                progress: progress
            ),
            twistDegrees: interpolateTwist(
                first.twistDegrees,
                second.twistDegrees,
                progress: progress
            ),
            kind: .refined,
            sourceSampleID: nil,
            connectsToPrevious: true
        )
    }

    private func interpolatePressure(
        _ first: Double?,
        _ second: Double?,
        progress: Double
    ) -> Double? {
        guard let first, let second else {
            return first ?? second
        }
        return first + (second - first) * progress
    }

    private func interpolateOptional(
        _ first: Double?,
        _ second: Double?,
        progress: Double
    ) -> Double? {
        guard let first, let second else {
            return first ?? second
        }
        return first + (second - first) * progress
    }

    private func interpolateTwist(
        _ first: Double?,
        _ second: Double?,
        progress: Double
    ) -> Double? {
        guard let first, let second else {
            return first ?? second
        }
        var delta = (second - first)
            .truncatingRemainder(dividingBy: 180)
        if delta > 90 {
            delta -= 180
        } else if delta < -90 {
            delta += 180
        }
        var result = first + delta * progress
        result = result.truncatingRemainder(dividingBy: 180)
        return result < 0 ? result + 180 : result
    }

    private func isWithinDeviation(
        between input: [RenderPoint],
        and output: [RenderPoint],
        limit: Double
    ) -> Bool {
        isWithinDirectedDeviation(
            from: input,
            to: output,
            limit: limit
        ) && isWithinDirectedDeviation(
            from: output,
            to: input,
            limit: limit
        )
    }

    private func isWithinDirectedDeviation(
        from points: [RenderPoint],
        to polyline: [RenderPoint],
        limit: Double
    ) -> Bool {
        guard let first = points.first else {
            return true
        }
        if points.count == 1 {
            return distanceToPolyline(first, polyline) <= limit
        }
        return zip(points, points.dropFirst()).allSatisfy {
            segmentIsWithinDeviation(
                start: $0,
                end: $1,
                startDistance: distanceToPolyline($0, polyline),
                endDistance: distanceToPolyline($1, polyline),
                polyline: polyline,
                limit: limit,
                depth: 0
            )
        }
    }

    private func segmentIsWithinDeviation(
        start: RenderPoint,
        end: RenderPoint,
        startDistance: Double,
        endDistance: Double,
        polyline: [RenderPoint],
        limit: Double,
        depth: Int
    ) -> Bool {
        guard startDistance <= limit, endDistance <= limit else {
            return false
        }
        let length = hypot(end.x - start.x, end.y - start.y)
        if max(startDistance, endDistance) + length / 2 <= limit {
            return true
        }
        guard depth < 16 else {
            return false
        }
        let midpoint = RenderPoint(
            x: (start.x + end.x) / 2,
            y: (start.y + end.y) / 2,
            pressure: nil,
            kind: .refined,
            sourceSampleID: nil,
            connectsToPrevious: true
        )
        let midpointDistance = distanceToPolyline(midpoint, polyline)
        guard midpointDistance <= limit else {
            return false
        }
        return segmentIsWithinDeviation(
            start: start,
            end: midpoint,
            startDistance: startDistance,
            endDistance: midpointDistance,
            polyline: polyline,
            limit: limit,
            depth: depth + 1
        ) && segmentIsWithinDeviation(
            start: midpoint,
            end: end,
            startDistance: midpointDistance,
            endDistance: endDistance,
            polyline: polyline,
            limit: limit,
            depth: depth + 1
        )
    }

    private func distanceToPolyline(
        _ point: RenderPoint,
        _ polyline: [RenderPoint]
    ) -> Double {
        guard let first = polyline.first else {
            return .infinity
        }
        if polyline.count == 1 {
            return hypot(point.x - first.x, point.y - first.y)
        }
        return zip(polyline, polyline.dropFirst()).map {
            distanceToSegment(
                point: point,
                start: $0,
                end: $1
            )
        }.min() ?? .infinity
    }

    private func distanceToSegment(
        point: RenderPoint,
        start: RenderPoint,
        end: RenderPoint
    ) -> Double {
        let dx = end.x - start.x
        let dy = end.y - start.y
        let lengthSquared = dx * dx + dy * dy
        guard lengthSquared > 0 else {
            return hypot(point.x - start.x, point.y - start.y)
        }
        let progress = max(
            0,
            min(
                1,
                (
                    (point.x - start.x) * dx
                        + (point.y - start.y) * dy
                ) / lengthSquared
            )
        )
        return hypot(
            point.x - (start.x + progress * dx),
            point.y - (start.y + progress * dy)
        )
    }
}

public struct GapInterpolator {
    public let algorithm: GapInterpolationAlgorithm
    public let options: GapInterpolationOptions

    public init(
        algorithm: GapInterpolationAlgorithm = .linear,
        options: GapInterpolationOptions = GapInterpolationOptions()
    ) {
        self.algorithm = algorithm
        self.options = options
    }

    public func interpolate(
        previousPrevious: RawPenSample?,
        previous: RawPenSample,
        current: RawPenSample,
        next: RawPenSample? = nil
    ) -> [RenderPoint] {
        guard case let .gap(opticalErrors, eventCountDelta) = current.continuity else {
            return []
        }

        let missingEstimate = max(
            opticalErrors,
            max(0, Int(eventCountDelta) - 1)
        )
        guard missingEstimate > 0 else {
            return []
        }

        let distance = hypot(current.x - previous.x, current.y - previous.y)
        guard distance > 0 else {
            return []
        }

        let previousSpacing = previousPrevious.map {
            hypot(previous.x - $0.x, previous.y - $0.y)
        } ?? 0
        let targetSpacing = previousSpacing >= options.minimumTargetSpacing
            ? previousSpacing
            : max(
                options.minimumTargetSpacing,
                distance / Double(missingEstimate + 1)
            )
        let spatialCount = max(1, Int(ceil(distance / targetSpacing)) - 1)
        let count = min(
            options.maximumPoints,
            max(1, min(missingEstimate, spatialCount))
        )
        let progressValues = (1...count).map {
            Double($0) / Double(count + 1)
        }
        let linear = progressValues.map { progress in
            (
                x: previous.x + (current.x - previous.x) * progress,
                y: previous.y + (current.y - previous.y) * progress
            )
        }
        let curved: [(x: Double, y: Double)]?
        switch algorithm {
        case .linear:
            curved = nil
        case .circularArc:
            curved = circularArc(
                previousPrevious: previousPrevious,
                previous: previous,
                current: current,
                progressValues: progressValues
            )
        case .cubicBezier:
            curved = cubicBezier(
                previousPrevious: previousPrevious,
                previous: previous,
                current: current,
                next: next,
                progressValues: progressValues
            )
        }
        let coordinates = boundedCurve(
            curved,
            linear: linear,
            chordLength: distance
        ) ?? linear

        return zip(progressValues, coordinates).map { progress, point in
            return RenderPoint(
                x: point.x,
                y: point.y,
                pressure: interpolatePressure(
                    previous.pressure,
                    current.pressure,
                    progress: progress
                ),
                tiltX: Double(previous.tiltX)
                    + Double(Int(current.tiltX) - Int(previous.tiltX))
                        * progress,
                tiltY: Double(previous.tiltY)
                    + Double(Int(current.tiltY) - Int(previous.tiltY))
                        * progress,
                twistDegrees: interpolateTwist(
                    Double(previous.twist),
                    Double(current.twist),
                    progress: progress
                ),
                kind: .interpolated,
                sourceSampleID: nil,
                connectsToPrevious: true
            )
        }
    }

    private func circularArc(
        previousPrevious: RawPenSample?,
        previous: RawPenSample,
        current: RawPenSample,
        progressValues: [Double]
    ) -> [(x: Double, y: Double)]? {
        guard let first = previousPrevious,
              previous.continuity == .continuous
        else {
            return nil
        }

        let incomingLength = hypot(
            previous.x - first.x,
            previous.y - first.y
        )
        let chordLength = hypot(
            current.x - previous.x,
            current.y - previous.y
        )
        guard incomingLength >= options.minimumTargetSpacing,
              chordLength > 0
        else {
            return nil
        }

        let determinant = 2 * (
            first.x * (previous.y - current.y)
                + previous.x * (current.y - first.y)
                + current.x * (first.y - previous.y)
        )
        let scale = max(incomingLength, chordLength)
        guard abs(determinant)
            > scale * scale * Self.collinearityTolerance
        else {
            return nil
        }

        let firstSquared = first.x * first.x + first.y * first.y
        let previousSquared = previous.x * previous.x
            + previous.y * previous.y
        let currentSquared = current.x * current.x + current.y * current.y
        let centerX = (
            firstSquared * (previous.y - current.y)
                + previousSquared * (current.y - first.y)
                + currentSquared * (first.y - previous.y)
        ) / determinant
        let centerY = (
            firstSquared * (current.x - previous.x)
                + previousSquared * (first.x - current.x)
                + currentSquared * (previous.x - first.x)
        ) / determinant
        guard centerX.isFinite, centerY.isFinite else {
            return nil
        }

        let firstAngle = atan2(first.y - centerY, first.x - centerX)
        let previousAngle = atan2(
            previous.y - centerY,
            previous.x - centerX
        )
        let currentAngle = atan2(
            current.y - centerY,
            current.x - centerX
        )
        let incomingSweep = normalizedAngle(previousAngle - firstAngle)
        let sweep = normalizedAngle(currentAngle - previousAngle)
        guard abs(incomingSweep) >= Self.minimumCurveSweep,
              abs(incomingSweep) <= Self.maximumCurveSweep,
              abs(sweep) >= Self.minimumCurveSweep,
              abs(sweep) <= Self.maximumCurveSweep,
              incomingSweep * sweep > 0
        else {
            return nil
        }

        let radius = hypot(previous.x - centerX, previous.y - centerY)
        guard radius.isFinite,
              abs(sweep) * radius
                <= chordLength * Self.maximumArcLengthRatio
        else {
            return nil
        }
        return progressValues.map { progress in
            let angle = previousAngle + sweep * progress
            return (
                x: centerX + radius * cos(angle),
                y: centerY + radius * sin(angle)
            )
        }
    }

    private func cubicBezier(
        previousPrevious: RawPenSample?,
        previous: RawPenSample,
        current: RawPenSample,
        next: RawPenSample?,
        progressValues: [Double]
    ) -> [(x: Double, y: Double)]? {
        guard let first = previousPrevious,
              previous.continuity == .continuous
        else {
            return nil
        }

        let incomingX = previous.x - first.x
        let incomingY = previous.y - first.y
        let incomingLength = hypot(incomingX, incomingY)
        let chordX = current.x - previous.x
        let chordY = current.y - previous.y
        let chordLength = hypot(chordX, chordY)
        guard incomingLength >= options.minimumTargetSpacing,
              chordLength > 0
        else {
            return nil
        }

        let incomingAngle = atan2(incomingY, incomingX)
        if let next,
           next.strokeID == current.strokeID,
           next.continuity == .continuous
        {
            let outgoingX = next.x - current.x
            let outgoingY = next.y - current.y
            let outgoingLength = hypot(outgoingX, outgoingY)
            guard outgoingLength >= options.minimumTargetSpacing else {
                return nil
            }
            let directionCosine = (
                incomingX * outgoingX + incomingY * outgoingY
            ) / (incomingLength * outgoingLength)
            guard directionCosine < Self.straightBoundaryCosine else {
                return nil
            }
            let controlDistance = chordLength / 3
            let firstControl = (
                x: previous.x
                    + incomingX / incomingLength * controlDistance,
                y: previous.y
                    + incomingY / incomingLength * controlDistance
            )
            let secondControl = (
                x: current.x
                    - outgoingX / outgoingLength * controlDistance,
                y: current.y
                    - outgoingY / outgoingLength * controlDistance
            )
            return cubicCoordinates(
                previous: previous,
                current: current,
                firstControl: firstControl,
                secondControl: secondControl,
                progressValues: progressValues
            )
        }

        let chordAngle = atan2(chordY, chordX)
        let sweep = 2 * normalizedAngle(chordAngle - incomingAngle)
        guard abs(sweep) >= Self.minimumCurveSweep,
              abs(sweep) <= Self.maximumCurveSweep
        else {
            return nil
        }

        let endAngle = incomingAngle + sweep
        let cosine = cos(sweep / 4)
        let controlDistance = chordLength / (3 * cosine * cosine)
        let firstControl = (
            x: previous.x + cos(incomingAngle) * controlDistance,
            y: previous.y + sin(incomingAngle) * controlDistance
        )
        let secondControl = (
            x: current.x - cos(endAngle) * controlDistance,
            y: current.y - sin(endAngle) * controlDistance
        )

        return cubicCoordinates(
            previous: previous,
            current: current,
            firstControl: firstControl,
            secondControl: secondControl,
            progressValues: progressValues
        )
    }

    private func cubicCoordinates(
        previous: RawPenSample,
        current: RawPenSample,
        firstControl: (x: Double, y: Double),
        secondControl: (x: Double, y: Double),
        progressValues: [Double]
    ) -> [(x: Double, y: Double)] {
        progressValues.map { progress in
            let remaining = 1 - progress
            return (
                x: remaining * remaining * remaining * previous.x
                    + 3 * remaining * remaining * progress * firstControl.x
                    + 3 * remaining * progress * progress * secondControl.x
                    + progress * progress * progress * current.x,
                y: remaining * remaining * remaining * previous.y
                    + 3 * remaining * remaining * progress * firstControl.y
                    + 3 * remaining * progress * progress * secondControl.y
                    + progress * progress * progress * current.y
            )
        }
    }

    private func boundedCurve(
        _ curve: [(x: Double, y: Double)]?,
        linear: [(x: Double, y: Double)],
        chordLength: Double
    ) -> [(x: Double, y: Double)]? {
        guard let curve, curve.count == linear.count else {
            return nil
        }
        let maximumDeviation = chordLength
            * Self.maximumChordDeviationRatio
        guard zip(curve, linear).allSatisfy({
            $0.x.isFinite
                && $0.y.isFinite
                && hypot($0.x - $1.x, $0.y - $1.y) <= maximumDeviation
        }) else {
            return nil
        }
        return curve
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

    private func interpolatePressure(
        _ start: Double?,
        _ end: Double?,
        progress: Double
    ) -> Double? {
        guard let start, let end else {
            return start ?? end
        }
        return start + (end - start) * progress
    }

    private func interpolateTwist(
        _ start: Double,
        _ end: Double,
        progress: Double
    ) -> Double {
        var delta = (end - start)
            .truncatingRemainder(dividingBy: 180)
        if delta > 90 {
            delta -= 180
        } else if delta < -90 {
            delta += 180
        }
        var result = start + delta * progress
        result = result.truncatingRemainder(dividingBy: 180)
        return result < 0 ? result + 180 : result
    }

    private static let minimumCurveSweep = Double.pi / 180
    private static let maximumCurveSweep = 2 * Double.pi / 3
    private static let collinearityTolerance = 0.000_001
    private static let maximumArcLengthRatio = 1.25
    private static let maximumChordDeviationRatio = 0.35
    private static let straightBoundaryCosine = 0.95
}

public struct TrajectoryPredictor {
    public let algorithm: PredictionAlgorithm
    public let options: PredictionOptions

    public init(
        algorithm: PredictionAlgorithm = .safe,
        options: PredictionOptions = PredictionOptions()
    ) {
        self.algorithm = algorithm
        self.options = options
    }

    public func predict(from samples: [RawPenSample]) -> [RenderPoint] {
        guard options.pointCount > 0 else {
            return []
        }
        switch algorithm {
        case .safe:
            return predictSafely(from: samples)
        case .velocity:
            return predictVelocity(from: samples)
        case .curve:
            return predictCurve(from: samples)
        }
    }

    private func predictSafely(
        from samples: [RawPenSample]
    ) -> [RenderPoint] {
        guard let recent = continuousSuffix(samples, count: 3) else {
            return []
        }
        let firstVelocity = Vector(
            x: recent[1].x - recent[0].x,
            y: recent[1].y - recent[0].y
        )
        let latestVelocity = Vector(
            x: recent[2].x - recent[1].x,
            y: recent[2].y - recent[1].y
        )
        guard firstVelocity.length > 0.000_001,
              latestVelocity.length > 0.000_001,
              firstVelocity.cosine(with: latestVelocity)
                >= options.minimumDirectionCosine
        else {
            return []
        }
        let speedRatio = latestVelocity.length / firstVelocity.length
        guard speedRatio >= options.minimumSpeedRatio,
              speedRatio <= options.maximumSpeedRatio
        else {
            return []
        }

        let velocity = latestVelocity * 0.75 + firstVelocity * 0.25
        let acceleration = (latestVelocity - firstVelocity)
            * options.accelerationWeight
        let maximumStep = boundedMaximumStep(
            firstVelocity,
            latestVelocity
        )
        var position = Vector(x: recent[2].x, y: recent[2].y)
        var predictions: [RenderPoint] = []
        for index in 1...options.pointCount {
            let damping = pow(options.damping, Double(index - 1))
            let proposed = (
                velocity + acceleration * Double(index)
            ) * damping
            let step = bounded(proposed, maximum: maximumStep)
            position = position + step
            predictions.append(
                prediction(
                    position: position,
                    pressure: predictedPressure(
                        recent: recent,
                        index: index
                    ),
                    orientation: recent[2]
                )
            )
        }
        return predictions
    }

    private func predictVelocity(
        from samples: [RawPenSample]
    ) -> [RenderPoint] {
        guard let recent = continuousSuffix(samples, count: 2) else {
            return []
        }
        let measuredStep = Vector(
            x: recent[1].x - recent[0].x,
            y: recent[1].y - recent[0].y
        )
        guard measuredStep.length > 0.000_001 else {
            return []
        }
        let maximumStep = min(
            measuredStep.length * options.maximumStepMultiplier,
            options.maximumStepDistance
        )
        let step = bounded(measuredStep, maximum: maximumStep)
        var position = Vector(x: recent[1].x, y: recent[1].y)
        return (1...options.pointCount).map { index in
            position = position + step
            return prediction(
                position: position,
                pressure: predictedPressure(
                    recent: recent,
                    index: index
                ),
                orientation: recent[1]
            )
        }
    }

    private func predictCurve(
        from samples: [RawPenSample]
    ) -> [RenderPoint] {
        guard let recent = continuousSuffix(samples, count: 3) else {
            return []
        }
        let firstVelocity = Vector(
            x: recent[1].x - recent[0].x,
            y: recent[1].y - recent[0].y
        )
        let latestVelocity = Vector(
            x: recent[2].x - recent[1].x,
            y: recent[2].y - recent[1].y
        )
        guard firstVelocity.length > 0.000_001,
              latestVelocity.length > 0.000_001
        else {
            return []
        }
        let measuredTurn = normalizedAngle(
            latestVelocity.angle - firstVelocity.angle
        )
        let turn = max(
            -options.maximumCurveTurnRadians,
            min(options.maximumCurveTurnRadians, measuredTurn)
        )
        let maximumStep = boundedMaximumStep(
            firstVelocity,
            latestVelocity
        )
        var step = latestVelocity
        var position = Vector(x: recent[2].x, y: recent[2].y)
        var predictions: [RenderPoint] = []
        for index in 1...options.pointCount {
            step = step.rotated(by: turn)
            if index > 1 {
                step = step * options.curveDamping
            }
            step = bounded(step, maximum: maximumStep)
            position = position + step
            predictions.append(
                prediction(
                    position: position,
                    pressure: predictedPressure(
                        recent: recent,
                        index: index
                    ),
                    orientation: recent[2]
                )
            )
        }
        return predictions
    }

    private func continuousSuffix(
        _ samples: [RawPenSample],
        count: Int
    ) -> [RawPenSample]? {
        guard samples.count >= count else {
            return nil
        }
        let recent = Array(samples.suffix(count))
        let strokeID = recent[0].strokeID
        guard recent.allSatisfy({ $0.strokeID == strokeID }),
              recent.dropFirst().allSatisfy({
                  $0.continuity == .continuous
              })
        else {
            return nil
        }
        return recent
    }

    private func boundedMaximumStep(
        _ first: Vector,
        _ second: Vector
    ) -> Double {
        min(
            max(first.length, second.length)
                * options.maximumStepMultiplier,
            options.maximumStepDistance
        )
    }

    private func bounded(
        _ vector: Vector,
        maximum: Double
    ) -> Vector {
        vector.length > maximum
            ? vector.normalized * maximum
            : vector
    }

    private func predictedPressure(
        recent: [RawPenSample],
        index: Int
    ) -> Double {
        let latest = recent[recent.count - 1]
        let previous = recent[recent.count - 2]
        let pressureVelocity = (latest.pressure ?? 0.5)
            - (previous.pressure ?? latest.pressure ?? 0.5)
        return min(
            1,
            max(
                0,
                (latest.pressure ?? 0.5)
                    + pressureVelocity * Double(index)
            )
        )
    }

    private func prediction(
        position: Vector,
        pressure: Double,
        orientation: RawPenSample
    ) -> RenderPoint {
        RenderPoint(
            x: position.x,
            y: position.y,
            pressure: pressure,
            tiltX: Double(orientation.tiltX),
            tiltY: Double(orientation.tiltY),
            twistDegrees: Double(orientation.twist),
            kind: .predicted,
            sourceSampleID: nil,
            connectsToPrevious: true
        )
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

    private struct Vector {
        let x: Double
        let y: Double

        var length: Double {
            hypot(x, y)
        }

        var angle: Double {
            atan2(y, x)
        }

        var normalized: Vector {
            guard length > 0 else {
                return Vector(x: 0, y: 0)
            }
            return self * (1 / length)
        }

        func dot(_ other: Vector) -> Double {
            x * other.x + y * other.y
        }

        func cosine(with other: Vector) -> Double {
            guard length > 0, other.length > 0 else {
                return -1
            }
            return dot(other) / (length * other.length)
        }

        func rotated(by angle: Double) -> Vector {
            Vector(
                x: x * cos(angle) - y * sin(angle),
                y: x * sin(angle) + y * cos(angle)
            )
        }

        static func + (lhs: Vector, rhs: Vector) -> Vector {
            Vector(x: lhs.x + rhs.x, y: lhs.y + rhs.y)
        }

        static func - (lhs: Vector, rhs: Vector) -> Vector {
            Vector(x: lhs.x - rhs.x, y: lhs.y - rhs.y)
        }

        static func * (lhs: Vector, rhs: Double) -> Vector {
            Vector(x: lhs.x * rhs, y: lhs.y * rhs)
        }
    }
}

public struct StreamingPointReducer {
    public let options: PointReductionOptions

    private var lastEmitted: RenderPoint?
    private var candidate: RenderPoint?

    public init(options: PointReductionOptions = PointReductionOptions()) {
        self.options = options
    }

    public mutating func append(_ point: RenderPoint) -> [RenderPoint] {
        guard let lastEmitted else {
            self.lastEmitted = point
            return [point]
        }
        guard let candidate else {
            self.candidate = point
            return []
        }

        if canDiscard(candidate, between: lastEmitted, and: point) {
            self.candidate = point
            return []
        }

        self.lastEmitted = candidate
        self.candidate = point
        return [candidate]
    }

    public mutating func finish() -> [RenderPoint] {
        defer {
            lastEmitted = nil
            candidate = nil
        }
        guard let candidate else {
            return []
        }
        return [candidate]
    }

    private func canDiscard(
        _ candidate: RenderPoint,
        between start: RenderPoint,
        and end: RenderPoint
    ) -> Bool {
        guard candidate.connectsToPrevious, end.connectsToPrevious else {
            return false
        }
        let pressureStart = start.pressure ?? 0.5
        let pressureCandidate = candidate.pressure ?? 0.5
        let pressureEnd = end.pressure ?? 0.5
        let expectedPressure = (pressureStart + pressureEnd) / 2
        guard abs(pressureCandidate - expectedPressure)
            <= options.pressureTolerance
        else {
            return false
        }

        return perpendicularDistance(
            point: candidate,
            lineStart: start,
            lineEnd: end
        ) <= options.distanceTolerance
    }

    private func perpendicularDistance(
        point: RenderPoint,
        lineStart: RenderPoint,
        lineEnd: RenderPoint
    ) -> Double {
        let dx = lineEnd.x - lineStart.x
        let dy = lineEnd.y - lineStart.y
        let lengthSquared = dx * dx + dy * dy
        guard lengthSquared > 0 else {
            return hypot(point.x - lineStart.x, point.y - lineStart.y)
        }
        let progress = max(
            0,
            min(
                1,
                (
                    (point.x - lineStart.x) * dx
                        + (point.y - lineStart.y) * dy
                ) / lengthSquared
            )
        )
        let projectedX = lineStart.x + progress * dx
        let projectedY = lineStart.y + progress * dy
        return hypot(point.x - projectedX, point.y - projectedY)
    }
}

public final class LiveStrokeProcessor {
    public var mode: StrokeRenderMode {
        didSet {
            reset()
        }
    }
    public var interpolationAlgorithm: GapInterpolationAlgorithm {
        didSet {
            interpolator = GapInterpolator(
                algorithm: interpolationAlgorithm,
                options: interpolator.options
            )
            reset()
        }
    }
    public var refinementAlgorithm: StrokeRefinementAlgorithm {
        didSet {
            reset()
        }
    }
    public var predictionAlgorithm: PredictionAlgorithm {
        didSet {
            predictor = TrajectoryPredictor(
                algorithm: predictionAlgorithm,
                options: predictor.options
            )
            reset()
        }
    }

    private var interpolator: GapInterpolator
    private var predictor: TrajectoryPredictor
    private let pathRefiner = PathStrokeRefiner()
    private var history: [RawPenSample] = []
    private var rawStroke: [RawPenSample] = []
    private var activeStrokeID: UInt64?

    public init(
        mode: StrokeRenderMode,
        interpolationAlgorithm: GapInterpolationAlgorithm = .linear,
        refinementAlgorithm: StrokeRefinementAlgorithm = .none,
        predictionAlgorithm: PredictionAlgorithm = .safe,
        interpolationOptions: GapInterpolationOptions = GapInterpolationOptions(),
        predictionOptions: PredictionOptions = PredictionOptions()
    ) {
        self.mode = mode
        self.interpolationAlgorithm = interpolationAlgorithm
        self.refinementAlgorithm = refinementAlgorithm
        self.predictionAlgorithm = predictionAlgorithm
        interpolator = GapInterpolator(
            algorithm: interpolationAlgorithm,
            options: interpolationOptions
        )
        predictor = TrajectoryPredictor(
            algorithm: predictionAlgorithm,
            options: predictionOptions
        )
    }

    public func receive(_ sample: RawPenSample) -> StrokeRenderUpdate {
        if activeStrokeID != sample.strokeID {
            history.removeAll(keepingCapacity: true)
            rawStroke.removeAll(keepingCapacity: true)
            activeStrokeID = sample.strokeID
        }
        rawStroke.append(sample)

        let previousHistory = history
        var committed: [RenderPoint] = []
        if mode != .raw,
           let previous = previousHistory.last
        {
            committed.append(
                contentsOf: interpolator.interpolate(
                    previousPrevious: previousHistory.dropLast().last,
                    previous: previous,
                    current: sample
                )
            )
        }

        committed.append(
            RenderPoint(
                x: sample.x,
                y: sample.y,
                pressure: sample.pressure,
                tiltX: Double(sample.tiltX),
                tiltY: Double(sample.tiltY),
                twistDegrees: Double(sample.twist),
                kind: .raw,
                sourceSampleID: sample.id,
                connectsToPrevious: sample.continuity == .continuous
                    || !committed.isEmpty,
                marksGap: {
                    if case .gap = sample.continuity {
                        return true
                    }
                    return false
                }()
            )
        )
        if case .gap = sample.continuity {
            history = [sample]
        } else {
            history.append(sample)
            if history.count > 4 {
                history.removeFirst(history.count - 4)
            }
        }

        let predicted = mode == .predict
            ? predictor.predict(from: history)
            : []
        return StrokeRenderUpdate(
            strokeID: sample.strokeID,
            committed: committed,
            predicted: predicted,
            replacement: nil
        )
    }

    public func endStroke() -> StrokeRenderUpdate? {
        defer {
            reset()
        }
        guard let activeStrokeID else {
            return nil
        }
        let replacement = mode != .raw && refinementAlgorithm == .smoothPath
            ? pathRefiner.refine(samples: rawStroke)
            : nil
        return StrokeRenderUpdate(
            strokeID: activeStrokeID,
            committed: [],
            predicted: [],
            replacement: replacement
        )
    }

    public func reset() {
        history.removeAll(keepingCapacity: true)
        rawStroke.removeAll(keepingCapacity: true)
        activeStrokeID = nil
    }
}
