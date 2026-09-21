import Darwin
import Foundation
import NeoInput
import NeoTransport
import TraceMetrics

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

private func sample(
    id: UInt64,
    penTime: UInt64,
    inputLatency: Int64,
    arrivalUptime: UInt64,
    interArrival: Double?,
    continuity: SampleContinuity,
    batchID: UInt64? = nil,
    batchFrameCount: Int? = nil
) -> RawPenSample {
    RawPenSample(
        id: id,
        strokeID: 1,
        sampleIndex: Int(id - 1),
        eventCount: UInt8(id),
        page: PenPageID(section: 3, owner: 27, note: 258, page: 1),
        penTimestampMilliseconds: penTime,
        receivedWallClockMilliseconds: penTime + UInt64(inputLatency),
        receivedUptimeNanoseconds: arrivalUptime,
        protocolClockDeltaMilliseconds: inputLatency,
        interArrivalMilliseconds: interArrival,
        x: Double(id),
        y: Double(id),
        force: 426,
        pressure: 0.5,
        tiltX: 90,
        tiltY: 45,
        twist: 120,
        continuity: continuity,
        transportBatchID: batchID,
        transportBatchFrameCount: batchFrameCount
    )
}

test("performance monitor reports latency cadence gaps and recognition") {
    let monitor = TracePerformanceMonitor(windowSize: 16)
    let first = sample(
        id: 1,
        penTime: 100,
        inputLatency: 8,
        arrivalUptime: 100_000_000,
        interArrival: nil,
        continuity: .first,
        batchID: 1,
        batchFrameCount: 3
    )
    let second = sample(
        id: 2,
        penTime: 110,
        inputLatency: 10,
        arrivalUptime: 110_000_000,
        interArrival: 10,
        continuity: .continuous,
        batchID: 1,
        batchFrameCount: 3
    )
    let third = sample(
        id: 3,
        penTime: 130,
        inputLatency: 15,
        arrivalUptime: 135_000_000,
        interArrival: 25,
        continuity: .gap(opticalErrors: 1, eventCountDelta: 2),
        batchID: 2,
        batchFrameCount: 1
    )

    monitor.record(
        .strokeStarted(
            InputStrokeStarted(
                strokeID: 1,
                penTimestampMilliseconds: 90,
                receivedWallClockMilliseconds: 98,
                receivedUptimeNanoseconds: 90_000_000,
                inputLatencyMilliseconds: 8,
                tipType: .normal,
                color: 0xFF00_0000
            )
        )
    )
    monitor.record(.sample(first))
    monitor.record(.sample(second))
    monitor.record(
        .opticalError(
            InputOpticalError(
                strokeID: 1,
                page: first.page,
                penTimestampMilliseconds: 120,
                receivedWallClockMilliseconds: 129,
                receivedUptimeNanoseconds: 120_000_000,
                protocolClockDeltaMilliseconds: 9,
                event: PenImageProcessingError(
                    eventCount: 3,
                    timeDeltaMilliseconds: 10,
                    force: 400,
                    imageBrightness: 140,
                    exposureTime: 110,
                    processingTime: 25,
                    labelCount: 100,
                    errorCode: 20,
                    classType: 1,
                    errorCount: 1
                )
            )
        )
    )
    monitor.record(.sample(third))
    monitor.record(
        .strokeCompleted(
            InputStrokeCompleted(
                strokeID: 1,
                page: first.page,
                startedAtPenMilliseconds: 90,
                endedAtPenMilliseconds: 140,
                durationMilliseconds: 50,
                sampleCount: 3,
                opticalErrorCount: 1,
                reportedDotCount: 3,
                totalImageCount: 12,
                processedImageCount: 12,
                successfulImageCount: 3,
                sentImageCount: 3,
                imageRecognitionRate: 0.25,
                receivedWallClockMilliseconds: 152,
                receivedUptimeNanoseconds: 145_000_000,
                completionLatencyMilliseconds: 12
            )
        )
    )

    monitor.recordRendered(first, atUptimeNanoseconds: 106_000_000)
    monitor.recordRendered(second, atUptimeNanoseconds: 115_000_000)
    monitor.recordRendered(third, atUptimeNanoseconds: 145_000_000)
    monitor.recordProcessingLatency(nanoseconds: 500)
    monitor.recordProcessingLatency(nanoseconds: 1_000)

    let snapshot = monitor.snapshot
    try expect(snapshot.sampleCount == 3, "sample count changed")
    try expect(snapshot.gapCount == 1, "gap count changed")
    try expect(snapshot.opticalErrorCount == 1, "optical error count changed")
    try expect(snapshot.strokeCount == 1, "stroke count changed")
    try expect(snapshot.latestRecognitionRate == 0.25, "recognition changed")
    try expect(snapshot.clockOffsetEstimateMilliseconds == 8, "clock offset changed")
    try expect(snapshot.rawStartLatency.p50 == 8, "raw start p50 changed")
    try expect(snapshot.startLatency.p50 == 0, "corrected start p50 changed")
    try expect(snapshot.rawCompletionLatency.p50 == 12, "raw completion p50 changed")
    try expect(snapshot.completionLatency.p50 == 4, "corrected completion p50 changed")
    try expect(snapshot.firstSampleDelay.p50 == 10, "first sample delay changed")
    try expect(snapshot.renderLatency.p50 == 6, "render latency p50 changed")
    try expect(snapshot.renderLatency.p95 == 10, "render latency p95 changed")
    try expect(snapshot.processingLatency.p50 == 0.000_5, "processing p50 changed")
    try expect(snapshot.processingLatency.p95 == 0.001, "processing p95 changed")
    try expect(snapshot.effectiveSampleRateHz == 60, "sample rate changed")
    try expect(snapshot.deliveryRateHz == 1000 / 17.5, "delivery rate changed")
    try expect(snapshot.transportBatchCount == 2, "transport batch count changed")
    try expect(snapshot.meanFramesPerBatch == 2, "mean batch size changed")
    try expect(snapshot.maximumFramesPerBatch == 3, "maximum batch size changed")
}

test("performance monitor reset clears session state") {
    let monitor = TracePerformanceMonitor(windowSize: 4)
    monitor.record(
        .sample(
            sample(
                id: 1,
                penTime: 100,
                inputLatency: 8,
                arrivalUptime: 100,
                interArrival: nil,
                continuity: .first
            )
        )
    )
    monitor.reset()

    try expect(monitor.snapshot == .empty, "reset retained performance state")
}

test("performance monitor excludes hover from ink measurements") {
    let monitor = TracePerformanceMonitor(windowSize: 4)
    monitor.record(
        .hover(
            RawHoverSample(
                id: 1,
                source: .outOfStrokeDot,
                eventCount: 7,
                timeDeltaMilliseconds: 4,
                page: PenPageID(
                    section: 3,
                    owner: 27,
                    note: 258,
                    page: 1
                ),
                receivedWallClockMilliseconds: 100,
                receivedUptimeNanoseconds: 100_000_000,
                interArrivalMilliseconds: nil,
                x: 12.25,
                y: 34.5,
                force: 3,
                pressure: Double(3) / 852,
                tiltX: 90,
                tiltY: 45,
                twist: 120
            )
        )
    )

    try expect(
        monitor.snapshot == .empty,
        "hover changed stroke, sample, anomaly, or latency metrics"
    )
}

if failureCount > 0 {
    fputs("\(failureCount) test(s) failed\n", stderr)
    exit(1)
}

print("All Trace metrics tests passed.")
