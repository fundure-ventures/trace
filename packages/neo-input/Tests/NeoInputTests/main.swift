import Darwin
import Foundation
import NeoInput
import NeoTransport

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

test("normalizer reconstructs raw sample timing pressure and continuity") {
    let normalizer = NeoInputNormalizer()
    var output: [NeoInputEvent] = []
    normalizer.eventHandler = { output.append($0) }

    normalizer.receive(
        .status(
            PenDeviceStatus(
                isLocked: false,
                passwordMaxRetryCount: 5,
                passwordRetryCount: 0,
                timestampMilliseconds: 900,
                autoPowerOffMinutes: 20,
                maxForce: 852,
                usedStoragePercent: 0,
                penCapPowerOffEnabled: true,
                autoPowerOnEnabled: true,
                beepEnabled: true,
                hoverEnabled: false,
                batteryPercent: 90,
                isCharging: false,
                offlineDataEnabled: true,
                pressureSensitivityStep: 2
            )
        ),
        at: InputArrivalTime(wallClockMilliseconds: 900, uptimeNanoseconds: 900_000_000)
    )
    normalizer.receive(
        .penDown(
            PenDownEvent(
                eventCount: 0,
                timestampMilliseconds: 1_000,
                tipType: .normal,
                color: 0xFF00_0000
            )
        ),
        at: InputArrivalTime(
            wallClockMilliseconds: 1_010,
            uptimeNanoseconds: 1_000_000_000
        )
    )
    normalizer.receive(
        .pageChanged(
            PenPageInfo(eventCount: 1, section: 3, owner: 27, note: 258, page: 1)
        ),
        at: InputArrivalTime(
            wallClockMilliseconds: 1_011,
            uptimeNanoseconds: 1_001_000_000
        )
    )
    normalizer.receive(
        .dot(
            PenDotEvent(
                eventCount: 2,
                timeDeltaMilliseconds: 5,
                force: 426,
                x: 10,
                y: 20,
                fractionX: 25,
                fractionY: 50,
                tiltX: 90,
                tiltY: 45,
                twist: 120
            )
        ),
        at: InputArrivalTime(
            wallClockMilliseconds: 1_017,
            uptimeNanoseconds: 1_007_000_000,
            transportBatchID: 7,
            transportBatchFrameCount: 4,
            transportBatchByteCount: 80
        )
    )
    normalizer.receive(
        .dot(
            PenDotEvent(
                eventCount: 3,
                timeDeltaMilliseconds: 10,
                force: 852,
                x: 11,
                y: 20,
                fractionX: 0,
                fractionY: 50,
                tiltX: 91,
                tiltY: 46,
                twist: 121
            )
        ),
        at: InputArrivalTime(
            wallClockMilliseconds: 1_024,
            uptimeNanoseconds: 1_014_000_000
        )
    )
    normalizer.receive(
        .imageProcessingError(
            PenImageProcessingError(
                eventCount: 4,
                timeDeltaMilliseconds: 8,
                force: 700,
                imageBrightness: 140,
                exposureTime: 110,
                processingTime: 25,
                labelCount: 100,
                errorCode: 20,
                classType: 1,
                errorCount: 1
            )
        ),
        at: InputArrivalTime(
            wallClockMilliseconds: 1_032,
            uptimeNanoseconds: 1_022_000_000
        )
    )
    normalizer.receive(
        .dot(
            PenDotEvent(
                eventCount: 5,
                timeDeltaMilliseconds: 7,
                force: 639,
                x: 12,
                y: 21,
                fractionX: 50,
                fractionY: 0,
                tiltX: 92,
                tiltY: 47,
                twist: 122
            )
        ),
        at: InputArrivalTime(
            wallClockMilliseconds: 1_040,
            uptimeNanoseconds: 1_030_000_000
        )
    )
    normalizer.receive(
        .penUp(
            PenUpEvent(
                eventCount: 6,
                timestampMilliseconds: 1_045,
                dotCount: 3,
                totalImageCount: 10,
                processedImageCount: 10,
                successfulImageCount: 3,
                sentImageCount: 3
            )
        ),
        at: InputArrivalTime(
            wallClockMilliseconds: 1_050,
            uptimeNanoseconds: 1_040_000_000
        )
    )

    guard output.count == 7 else {
        throw TestFailure(description: "expected seven normalized events, got \(output.count)")
    }
    guard case let .strokeStarted(started) = output[0],
          case let .pageChanged(page) = output[1],
          case let .sample(first) = output[2],
          case let .sample(second) = output[3],
          case let .opticalError(error) = output[4],
          case let .sample(third) = output[5],
          case let .strokeCompleted(completed) = output[6]
    else {
        throw TestFailure(description: "normalized events arrived in the wrong shape")
    }

    try expect(started.strokeID == 1, "first stroke ID changed")
    try expect(page == PenPageID(section: 3, owner: 27, note: 258, page: 1), "page changed")

    try expect(first.penTimestampMilliseconds == 1_005, "first pen timestamp changed")
    try expect(
        first.protocolClockDeltaMilliseconds == 12,
        "first protocol clock delta changed"
    )
    try expect(first.pressure == 0.5, "pressure was not normalized")
    try expect(first.x == 10.25 && first.y == 20.5, "coordinates changed")
    try expect(first.continuity == .first, "first sample continuity changed")
    try expect(first.interArrivalMilliseconds == nil, "first sample has an arrival interval")
    try expect(first.transportBatchID == 7, "transport batch ID was lost")
    try expect(first.transportBatchFrameCount == 4, "transport batch size was lost")
    try expect(first.transportBatchByteCount == 80, "transport byte count was lost")

    try expect(second.penTimestampMilliseconds == 1_015, "second pen timestamp changed")
    try expect(
        second.protocolClockDeltaMilliseconds == 9,
        "second protocol clock delta changed"
    )
    try expect(second.pressure == 1, "maximum pressure did not normalize to one")
    try expect(second.continuity == .continuous, "consecutive sample was marked as a gap")
    try expect(second.interArrivalMilliseconds == 7, "inter-arrival timing changed")

    try expect(error.penTimestampMilliseconds == 1_023, "error timestamp changed")
    try expect(
        error.protocolClockDeltaMilliseconds == 9,
        "error protocol clock delta changed"
    )

    try expect(third.penTimestampMilliseconds == 1_030, "third pen timestamp changed")
    try expect(
        third.protocolClockDeltaMilliseconds == 10,
        "third protocol clock delta changed"
    )
    try expect(
        third.continuity == .gap(opticalErrors: 1, eventCountDelta: 2),
        "optical gap was hidden"
    )

    try expect(completed.strokeID == 1, "completed stroke ID changed")
    try expect(completed.durationMilliseconds == 45, "stroke duration changed")
    try expect(completed.sampleCount == 3, "stroke sample count changed")
    try expect(completed.opticalErrorCount == 1, "stroke error count changed")
    try expect(completed.imageRecognitionRate == 0.3, "recognition rate changed")
    try expect(
        completed.receivedWallClockMilliseconds == 1_050,
        "pen-up receipt time changed"
    )
    try expect(
        completed.receivedUptimeNanoseconds == 1_040_000_000,
        "pen-up monotonic receipt time changed"
    )
    try expect(completed.completionLatencyMilliseconds == 5, "completion latency changed")
}

test("normalizer routes out-of-stroke dots to hover regardless of force") {
    let normalizer = NeoInputNormalizer()
    var output: [NeoInputEvent] = []
    normalizer.eventHandler = { output.append($0) }

    normalizer.receive(
        .status(
            PenDeviceStatus(
                isLocked: false,
                passwordMaxRetryCount: 5,
                passwordRetryCount: 0,
                timestampMilliseconds: 90,
                autoPowerOffMinutes: 20,
                maxForce: 852,
                usedStoragePercent: 0,
                penCapPowerOffEnabled: true,
                autoPowerOnEnabled: true,
                beepEnabled: true,
                hoverEnabled: true,
                batteryPercent: 90,
                isCharging: false,
                offlineDataEnabled: true,
                pressureSensitivityStep: 2
            )
        ),
        at: InputArrivalTime(
            wallClockMilliseconds: 90,
            uptimeNanoseconds: 90_000_000
        )
    )
    normalizer.receive(
        .dot(
            PenDotEvent(
                eventCount: 10,
                timeDeltaMilliseconds: 5,
                force: 0,
                x: 1,
                y: 2,
                fractionX: 0,
                fractionY: 0,
                tiltX: 0,
                tiltY: 0,
                twist: 0
            )
        ),
        at: InputArrivalTime(
            wallClockMilliseconds: 100,
            uptimeNanoseconds: 100_000_000,
            transportBatchID: 7,
            transportBatchFrameCount: 1,
            transportBatchByteCount: 19
        )
    )
    normalizer.receive(
        .penDown(
            PenDownEvent(
                eventCount: 11,
                timestampMilliseconds: 110,
                tipType: .normal,
                color: 0
            )
        ),
        at: InputArrivalTime(
            wallClockMilliseconds: 110,
            uptimeNanoseconds: 110_000_000
        )
    )
    normalizer.receive(
        .pageChanged(
            PenPageInfo(
                eventCount: 12,
                section: 3,
                owner: 27,
                note: 258,
                page: 1
            )
        ),
        at: InputArrivalTime(
            wallClockMilliseconds: 111,
            uptimeNanoseconds: 111_000_000
        )
    )
    normalizer.receive(
        .penUp(
            PenUpEvent(
                eventCount: 13,
                timestampMilliseconds: 120,
                dotCount: 0,
                totalImageCount: 0,
                processedImageCount: 0,
                successfulImageCount: 0,
                sentImageCount: 0
            )
        ),
        at: InputArrivalTime(
            wallClockMilliseconds: 120,
            uptimeNanoseconds: 120_000_000
        )
    )
    normalizer.receive(
        .dot(
            PenDotEvent(
                eventCount: 14,
                timeDeltaMilliseconds: 5,
                force: 3,
                x: 4,
                y: 5,
                fractionX: 25,
                fractionY: 50,
                tiltX: 90,
                tiltY: 45,
                twist: 120
            )
        ),
        at: InputArrivalTime(
            wallClockMilliseconds: 130,
            uptimeNanoseconds: 130_000_000
        )
    )

    let hoverSamples = output.compactMap { event -> RawHoverSample? in
        guard case let .hover(sample) = event else {
            return nil
        }
        return sample
    }
    try expect(hoverSamples.count == 2, "outside-stroke dots were not hover")
    try expect(
        hoverSamples[0].source == .outOfStrokeDot
            && hoverSamples[0].page == nil
            && hoverSamples[0].force == 0
            && hoverSamples[0].pressure == 0,
        "pre-page zero-force hover changed"
    )
    try expect(
        hoverSamples[0].transportBatchID == 7
            && hoverSamples[0].transportBatchFrameCount == 1
            && hoverSamples[0].transportBatchByteCount == 19,
        "hover transport batch metadata was lost"
    )
    try expect(
        hoverSamples[1].source == .outOfStrokeDot
            && hoverSamples[1].page
                == PenPageID(section: 3, owner: 27, note: 258, page: 1)
            && hoverSamples[1].force == 3
            && hoverSamples[1].pressure == Double(3) / 852,
        "nonzero post-release hover was misclassified as ink"
    )
    try expect(
        !output.contains {
            if case .sample = $0 {
                return true
            }
            return false
        },
        "outside-stroke hover entered the ink stream"
    )
}

test("normalizer preserves explicit hover events in the hover stream") {
    let normalizer = NeoInputNormalizer()
    var output: [NeoInputEvent] = []
    normalizer.eventHandler = { output.append($0) }
    let page = PenPageID(section: 3, owner: 27, note: 258, page: 1)

    normalizer.receive(
        .pageChanged(
            PenPageInfo(
                eventCount: 1,
                section: page.section,
                owner: page.owner,
                note: page.note,
                page: page.page
            )
        ),
        at: InputArrivalTime(
            wallClockMilliseconds: 100,
            uptimeNanoseconds: 100_000_000
        )
    )
    normalizer.receive(
        .hover(
            PenHoverEvent(
                timeDeltaMilliseconds: 7,
                x: 46,
                y: 91,
                fractionX: 27,
                fractionY: 34
            )
        ),
        at: InputArrivalTime(
            wallClockMilliseconds: 107,
            uptimeNanoseconds: 107_000_000
        )
    )

    guard case let .hover(sample) = output.last else {
        throw TestFailure(description: "explicit hover was not normalized")
    }
    try expect(
        sample.source == .explicitProtocolEvent,
        "explicit hover source was lost"
    )
    try expect(sample.page == page, "explicit hover lost page context")
    try expect(sample.x == 46.27 && sample.y == 91.34, "hover coordinates changed")
    try expect(
        sample.force == nil && sample.pressure == nil,
        "explicit hover invented pressure"
    )
}

test("connection reset clears the previous Ncode page") {
    let normalizer = NeoInputNormalizer()
    var output: [NeoInputEvent] = []
    normalizer.eventHandler = { output.append($0) }

    normalizer.receive(
        .penDown(
            PenDownEvent(
                eventCount: 0,
                timestampMilliseconds: 100,
                tipType: .normal,
                color: 0
            )
        ),
        at: InputArrivalTime(wallClockMilliseconds: 100, uptimeNanoseconds: 100)
    )
    normalizer.receive(
        .pageChanged(
            PenPageInfo(eventCount: 1, section: 3, owner: 27, note: 258, page: 1)
        ),
        at: InputArrivalTime(wallClockMilliseconds: 101, uptimeNanoseconds: 101)
    )
    normalizer.resetConnectionState()
    output.removeAll()
    normalizer.receive(
        .dot(
            PenDotEvent(
                eventCount: 2,
                timeDeltaMilliseconds: 1,
                force: 0,
                x: 1,
                y: 2,
                fractionX: 0,
                fractionY: 0,
                tiltX: 0,
                tiltY: 0,
                twist: 0
            )
        ),
        at: InputArrivalTime(
            wallClockMilliseconds: 199,
            uptimeNanoseconds: 199
        )
    )
    guard case let .hover(hover) = output.last else {
        throw TestFailure(
            description: "post-reconnect motion did not remain hover"
        )
    }
    try expect(
        hover.page == nil,
        "previous page leaked into hover after connection reset"
    )
    output.removeAll()
    normalizer.receive(
        .penDown(
            PenDownEvent(
                eventCount: 3,
                timestampMilliseconds: 200,
                tipType: .normal,
                color: 0
            )
        ),
        at: InputArrivalTime(wallClockMilliseconds: 200, uptimeNanoseconds: 200)
    )
    normalizer.receive(
        .dot(
            PenDotEvent(
                eventCount: 4,
                timeDeltaMilliseconds: 1,
                force: 100,
                x: 1,
                y: 2,
                fractionX: 0,
                fractionY: 0,
                tiltX: 0,
                tiltY: 0,
                twist: 0
            )
        ),
        at: InputArrivalTime(wallClockMilliseconds: 201, uptimeNanoseconds: 201)
    )

    guard case let .sample(sample) = output.last else {
        throw TestFailure(description: "second connection did not emit a sample")
    }
    try expect(sample.page == nil, "previous page leaked across connection reset")
}

if failureCount > 0 {
    fputs("\(failureCount) test(s) failed\n", stderr)
    exit(1)
}

print("All Neo input tests passed.")
