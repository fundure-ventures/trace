import Foundation
import NeoInput

public struct MetricDistribution: Equatable, Sendable {
    public let count: Int
    public let minimum: Double?
    public let mean: Double?
    public let p50: Double?
    public let p95: Double?
    public let maximum: Double?

    public static let empty = MetricDistribution(
        count: 0,
        minimum: nil,
        mean: nil,
        p50: nil,
        p95: nil,
        maximum: nil
    )

    public init(
        count: Int,
        minimum: Double?,
        mean: Double?,
        p50: Double?,
        p95: Double?,
        maximum: Double?
    ) {
        self.count = count
        self.minimum = minimum
        self.mean = mean
        self.p50 = p50
        self.p95 = p95
        self.maximum = maximum
    }
}

public struct PerformanceSnapshot: Equatable, Sendable {
    public let sampleCount: Int
    public let gapCount: Int
    public let opticalErrorCount: Int
    public let strokeCount: Int
    public let anomalyCount: Int
    public let latestRecognitionRate: Double?
    public let clockOffsetEstimateMilliseconds: Double?
    public let rawStartLatency: MetricDistribution
    public let startLatency: MetricDistribution
    public let rawCompletionLatency: MetricDistribution
    public let completionLatency: MetricDistribution
    public let firstSampleDelay: MetricDistribution
    public let processingLatency: MetricDistribution
    public let renderLatency: MetricDistribution
    public let protocolSampleInterval: MetricDistribution
    public let deliveryInterval: MetricDistribution
    public let effectiveSampleRateHz: Double?
    public let deliveryRateHz: Double?
    public let transportBatchCount: Int
    public let meanFramesPerBatch: Double?
    public let maximumFramesPerBatch: Int?

    public static let empty = PerformanceSnapshot(
        sampleCount: 0,
        gapCount: 0,
        opticalErrorCount: 0,
        strokeCount: 0,
        anomalyCount: 0,
        latestRecognitionRate: nil,
        clockOffsetEstimateMilliseconds: nil,
        rawStartLatency: .empty,
        startLatency: .empty,
        rawCompletionLatency: .empty,
        completionLatency: .empty,
        firstSampleDelay: .empty,
        processingLatency: .empty,
        renderLatency: .empty,
        protocolSampleInterval: .empty,
        deliveryInterval: .empty,
        effectiveSampleRateHz: nil,
        deliveryRateHz: nil,
        transportBatchCount: 0,
        meanFramesPerBatch: nil,
        maximumFramesPerBatch: nil
    )

    public init(
        sampleCount: Int,
        gapCount: Int,
        opticalErrorCount: Int,
        strokeCount: Int,
        anomalyCount: Int,
        latestRecognitionRate: Double?,
        clockOffsetEstimateMilliseconds: Double?,
        rawStartLatency: MetricDistribution,
        startLatency: MetricDistribution,
        rawCompletionLatency: MetricDistribution,
        completionLatency: MetricDistribution,
        firstSampleDelay: MetricDistribution,
        processingLatency: MetricDistribution,
        renderLatency: MetricDistribution,
        protocolSampleInterval: MetricDistribution,
        deliveryInterval: MetricDistribution,
        effectiveSampleRateHz: Double?,
        deliveryRateHz: Double?,
        transportBatchCount: Int,
        meanFramesPerBatch: Double?,
        maximumFramesPerBatch: Int?
    ) {
        self.sampleCount = sampleCount
        self.gapCount = gapCount
        self.opticalErrorCount = opticalErrorCount
        self.strokeCount = strokeCount
        self.anomalyCount = anomalyCount
        self.latestRecognitionRate = latestRecognitionRate
        self.clockOffsetEstimateMilliseconds = clockOffsetEstimateMilliseconds
        self.rawStartLatency = rawStartLatency
        self.startLatency = startLatency
        self.rawCompletionLatency = rawCompletionLatency
        self.completionLatency = completionLatency
        self.firstSampleDelay = firstSampleDelay
        self.processingLatency = processingLatency
        self.renderLatency = renderLatency
        self.protocolSampleInterval = protocolSampleInterval
        self.deliveryInterval = deliveryInterval
        self.effectiveSampleRateHz = effectiveSampleRateHz
        self.deliveryRateHz = deliveryRateHz
        self.transportBatchCount = transportBatchCount
        self.meanFramesPerBatch = meanFramesPerBatch
        self.maximumFramesPerBatch = maximumFramesPerBatch
    }
}

public final class TracePerformanceMonitor {
    public var snapshot: PerformanceSnapshot {
        let rawStartValues = startLatencies.values
        let rawCompletionValues = completionLatencies.values
        let clockOffset = (rawStartValues + rawCompletionValues).min()
        let correctedStartValues = corrected(rawStartValues, by: clockOffset)
        let correctedCompletionValues = corrected(
            rawCompletionValues,
            by: clockOffset
        )
        let protocolIntervals = distribution(for: protocolSampleIntervals.values)
        let deliveryIntervals = distribution(for: deliveryIntervals.values)
        let frameCounts = batchOrder.compactMap { transportBatchFrameCounts[$0] }
        return PerformanceSnapshot(
            sampleCount: sampleCount,
            gapCount: gapCount,
            opticalErrorCount: opticalErrorCount,
            strokeCount: strokeCount,
            anomalyCount: anomalyCount,
            latestRecognitionRate: latestRecognitionRate,
            clockOffsetEstimateMilliseconds: clockOffset,
            rawStartLatency: distribution(for: rawStartValues),
            startLatency: distribution(for: correctedStartValues),
            rawCompletionLatency: distribution(for: rawCompletionValues),
            completionLatency: distribution(for: correctedCompletionValues),
            firstSampleDelay: distribution(for: firstSampleDelays.values),
            processingLatency: distribution(for: processingLatencies.values),
            renderLatency: distribution(for: renderLatencies.values),
            protocolSampleInterval: protocolIntervals,
            deliveryInterval: deliveryIntervals,
            effectiveSampleRateHz: totalCompletedStrokeDurationMilliseconds > 0
                ? Double(completedStrokeSampleCount) * 1_000
                    / Double(totalCompletedStrokeDurationMilliseconds)
                : nil,
            deliveryRateHz: rate(from: deliveryIntervals.mean),
            transportBatchCount: frameCounts.count,
            meanFramesPerBatch: frameCounts.isEmpty
                ? nil
                : Double(frameCounts.reduce(0, +)) / Double(frameCounts.count),
            maximumFramesPerBatch: frameCounts.max()
        )
    }

    private struct RollingWindow {
        let capacity: Int
        var values: [Double] = []

        mutating func append(_ value: Double) {
            values.append(value)
            if values.count > capacity {
                values.removeFirst(values.count - capacity)
            }
        }

        mutating func reset() {
            values.removeAll(keepingCapacity: true)
        }
    }

    private let windowSize: Int
    private var startLatencies: RollingWindow
    private var completionLatencies: RollingWindow
    private var firstSampleDelays: RollingWindow
    private var processingLatencies: RollingWindow
    private var renderLatencies: RollingWindow
    private var protocolSampleIntervals: RollingWindow
    private var deliveryIntervals: RollingWindow
    private var sampleCount = 0
    private var gapCount = 0
    private var opticalErrorCount = 0
    private var strokeCount = 0
    private var anomalyCount = 0
    private var latestRecognitionRate: Double?
    private var activeStrokeStartUptimeNanoseconds: UInt64?
    private var completedStrokeSampleCount = 0
    private var totalCompletedStrokeDurationMilliseconds: UInt64 = 0
    private var lastPenTimestamp: UInt64?
    private var lastStrokeID: UInt64?
    private var batchOrder: [UInt64] = []
    private var transportBatchFrameCounts: [UInt64: Int] = [:]

    public init(windowSize: Int = 512) {
        precondition(windowSize > 0, "Performance window must be positive")
        self.windowSize = windowSize
        startLatencies = RollingWindow(capacity: windowSize)
        completionLatencies = RollingWindow(capacity: windowSize)
        firstSampleDelays = RollingWindow(capacity: windowSize)
        processingLatencies = RollingWindow(capacity: windowSize)
        renderLatencies = RollingWindow(capacity: windowSize)
        protocolSampleIntervals = RollingWindow(capacity: windowSize)
        deliveryIntervals = RollingWindow(capacity: windowSize)
    }

    public func record(_ event: NeoInputEvent) {
        switch event {
        case let .strokeStarted(stroke):
            startLatencies.append(Double(stroke.inputLatencyMilliseconds))
            activeStrokeStartUptimeNanoseconds = stroke.receivedUptimeNanoseconds
            lastStrokeID = stroke.strokeID
            lastPenTimestamp = nil
        case let .sample(sample):
            record(sample)
        case .opticalError:
            opticalErrorCount += 1
        case let .strokeCompleted(stroke):
            strokeCount += 1
            latestRecognitionRate = stroke.imageRecognitionRate
            completionLatencies.append(
                Double(stroke.completionLatencyMilliseconds)
            )
            completedStrokeSampleCount += stroke.sampleCount
            totalCompletedStrokeDurationMilliseconds += stroke.durationMilliseconds
            activeStrokeStartUptimeNanoseconds = nil
            lastStrokeID = nil
            lastPenTimestamp = nil
        case .anomaly:
            anomalyCount += 1
        case .pageChanged, .hover:
            break
        }
    }

    public func recordRendered(
        _ sample: RawPenSample,
        atUptimeNanoseconds uptimeNanoseconds: UInt64
    ) {
        guard uptimeNanoseconds >= sample.receivedUptimeNanoseconds else {
            return
        }
        renderLatencies.append(
            Double(uptimeNanoseconds - sample.receivedUptimeNanoseconds) / 1_000_000
        )
    }

    public func recordProcessingLatency(nanoseconds: UInt64) {
        processingLatencies.append(Double(nanoseconds) / 1_000_000)
    }

    public func reset() {
        startLatencies.reset()
        completionLatencies.reset()
        firstSampleDelays.reset()
        processingLatencies.reset()
        renderLatencies.reset()
        protocolSampleIntervals.reset()
        deliveryIntervals.reset()
        sampleCount = 0
        gapCount = 0
        opticalErrorCount = 0
        strokeCount = 0
        anomalyCount = 0
        latestRecognitionRate = nil
        activeStrokeStartUptimeNanoseconds = nil
        completedStrokeSampleCount = 0
        totalCompletedStrokeDurationMilliseconds = 0
        lastPenTimestamp = nil
        lastStrokeID = nil
        batchOrder.removeAll(keepingCapacity: true)
        transportBatchFrameCounts.removeAll(keepingCapacity: true)
    }

    private func record(_ sample: RawPenSample) {
        sampleCount += 1
        if sample.sampleIndex == 0,
           let activeStrokeStartUptimeNanoseconds,
           sample.receivedUptimeNanoseconds >= activeStrokeStartUptimeNanoseconds
        {
            firstSampleDelays.append(
                Double(
                    sample.receivedUptimeNanoseconds
                        - activeStrokeStartUptimeNanoseconds
                ) / 1_000_000
            )
        }
        if case .gap = sample.continuity {
            gapCount += 1
        }
        if let interArrival = sample.interArrivalMilliseconds {
            deliveryIntervals.append(interArrival)
        }
        if let batchID = sample.transportBatchID,
           let frameCount = sample.transportBatchFrameCount,
           transportBatchFrameCounts[batchID] == nil
        {
            batchOrder.append(batchID)
            transportBatchFrameCounts[batchID] = frameCount
            if batchOrder.count > windowSize {
                let removed = batchOrder.removeFirst()
                transportBatchFrameCounts.removeValue(forKey: removed)
            }
        }

        if lastStrokeID != sample.strokeID {
            lastStrokeID = sample.strokeID
            lastPenTimestamp = nil
        }
        if let lastPenTimestamp,
           sample.penTimestampMilliseconds >= lastPenTimestamp
        {
            protocolSampleIntervals.append(
                Double(sample.penTimestampMilliseconds - lastPenTimestamp)
            )
        }
        lastPenTimestamp = sample.penTimestampMilliseconds
    }

    private func distribution(for values: [Double]) -> MetricDistribution {
        guard !values.isEmpty else {
            return .empty
        }
        let sorted = values.sorted()
        return MetricDistribution(
            count: sorted.count,
            minimum: sorted.first,
            mean: sorted.reduce(0, +) / Double(sorted.count),
            p50: percentile(0.50, in: sorted),
            p95: percentile(0.95, in: sorted),
            maximum: sorted.last
        )
    }

    private func corrected(
        _ values: [Double],
        by clockOffset: Double?
    ) -> [Double] {
        guard let clockOffset else {
            return []
        }
        return values.map { max(0, $0 - clockOffset) }
    }

    private func percentile(_ percentile: Double, in sorted: [Double]) -> Double {
        let rank = max(1, Int(ceil(percentile * Double(sorted.count))))
        return sorted[min(sorted.count - 1, rank - 1)]
    }

    private func rate(from intervalMilliseconds: Double?) -> Double? {
        guard let intervalMilliseconds, intervalMilliseconds > 0 else {
            return nil
        }
        return 1_000 / intervalMilliseconds
    }
}
