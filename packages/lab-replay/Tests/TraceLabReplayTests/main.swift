import Darwin
import Foundation
import NeoInput
import TraceLabReplay

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

private let page = PenPageID(section: 3, owner: 27, note: 258, page: 1)

private func loadReplay(_ rows: [[String: Any]]) throws -> LabReplay {
    let data = try rows.map { row -> String in
        let encoded = try JSONSerialization.data(
            withJSONObject: row,
            options: [.sortedKeys]
        )
        return String(decoding: encoded, as: UTF8.self)
    }.joined(separator: "\n") + "\n"
    let url = FileManager.default.temporaryDirectory
        .appendingPathComponent("trace-replay-\(UUID().uuidString).jsonl")
    try data.write(to: url, atomically: true, encoding: .utf8)
    defer {
        try? FileManager.default.removeItem(at: url)
    }
    return try LabReplay.load(from: url)
}

private func startRow(
    strokeID: Int,
    uptime: Int,
    latencyKey: String = "raw_start_clock_delta_ms",
    latency: Int = 0
) -> [String: Any] {
    [
        "type": "stroke-start",
        "stroke_id": strokeID,
        "pen_ms": 1_000 + strokeID,
        "received_ms": 2_000 + strokeID,
        "received_uptime_ns": uptime,
        latencyKey: latency,
    ]
}

private func sampleRow(
    id: Int,
    strokeID: Int,
    uptime: Int,
    eligible: Bool? = true,
    latencyKey: String = "protocol_reconstructed_latency_ms",
    latency: Int = 0
) -> [String: Any] {
    var row: [String: Any] = [
        "type": "sample",
        "id": id,
        "stroke_id": strokeID,
        "sample_index": 0,
        "event_count": 1,
        "page_section": 3,
        "page_owner": 27,
        "page_note": 258,
        "page_number": 1,
        "pen_ms": 1_100 + id,
        "received_ms": 2_100 + id,
        "received_uptime_ns": uptime,
        "inter_arrival_ms": 4.5,
        "x": 12.25,
        "y": 34.5,
        "force": 426,
        "pressure": 0.5,
        "tilt_x": 90,
        "tilt_y": 45,
        "twist": 120,
        "continuity": "first",
        "transport_batch_id": 7,
        "transport_batch_frame_count": 4,
        "transport_batch_byte_count": 80,
        latencyKey: latency,
    ]
    if let eligible {
        row["measurement_eligible"] = eligible
    }
    return row
}

private func completionRow(
    strokeID: Int,
    uptime: Int,
    latencyKey: String = "raw_completion_clock_delta_ms",
    latency: Int = 0
) -> [String: Any] {
    [
        "type": "stroke-complete",
        "stroke_id": strokeID,
        "page_section": 3,
        "page_owner": 27,
        "page_note": 258,
        "page_number": 1,
        "duration_ms": 20,
        "sample_count": 1,
        "optical_error_count": 0,
        "reported_dot_count": 1,
        "total_image_count": 1,
        "processed_image_count": 1,
        "successful_image_count": 1,
        "sent_image_count": 1,
        "image_recognition_rate": 1.0,
        "received_ms": 2_200 + strokeID,
        "received_uptime_ns": uptime,
        latencyKey: latency,
    ]
}

private func hoverRow(uptime: Int) -> [String: Any] {
    [
        "type": "hover",
        "id": 9,
        "source": "out-of-stroke-dot",
        "event_count": 17,
        "time_delta_ms": 4,
        "page_section": 3,
        "page_owner": 27,
        "page_note": 258,
        "page_number": 1,
        "received_ms": 2_500,
        "received_uptime_ns": uptime,
        "inter_arrival_ms": 8.5,
        "x": 12.25,
        "y": 34.5,
        "force": 3,
        "pressure": Double(3) / 852,
        "tilt_x": 90,
        "tilt_y": 45,
        "twist": 120,
        "measurement_eligible": false,
        "transport_batch_id": 8,
        "transport_batch_frame_count": 1,
        "transport_batch_byte_count": 19,
    ]
}

private func strokeIDs(in replay: LabReplay) -> [UInt64] {
    replay.events.compactMap { entry in
        switch entry.event {
        case let .strokeStarted(stroke):
            return stroke.strokeID
        case let .sample(sample):
            return sample.strokeID
        case let .strokeCompleted(stroke):
            return stroke.strokeID
        case .pageChanged, .hover, .opticalError, .anomaly:
            return nil
        }
    }
}

test("replay excludes calibration priming and explicitly rejected strokes") {
    let replay = try loadReplay([
        ["type": "measurement-paused", "reason": "calibration"],
        startRow(strokeID: 1, uptime: 100),
        sampleRow(id: 1, strokeID: 1, uptime: 110, eligible: false),
        completionRow(strokeID: 1, uptime: 120),
        ["type": "page-primed"],
        startRow(strokeID: 2, uptime: 200),
        sampleRow(id: 2, strokeID: 2, uptime: 210, eligible: true),
        completionRow(strokeID: 2, uptime: 220),
        startRow(strokeID: 3, uptime: 300),
        sampleRow(id: 3, strokeID: 3, uptime: 310, eligible: false),
        completionRow(strokeID: 3, uptime: 320),
    ])

    try expect(
        Set(strokeIDs(in: replay)) == [2],
        "non-measurement strokes entered replay"
    )
}

test("replay orders start page sample and completion deterministically") {
    let replay = try loadReplay([
        startRow(strokeID: 4, uptime: 400),
        sampleRow(id: 4, strokeID: 4, uptime: 400, eligible: nil),
        completionRow(strokeID: 4, uptime: 410),
    ])

    try expect(replay.events.count == 4, "unexpected event count")
    guard case .strokeStarted = replay.events[0].event else {
        throw TestFailure(description: "stroke did not start first")
    }
    guard case .pageChanged = replay.events[1].event else {
        throw TestFailure(description: "page did not precede first sample")
    }
    guard case .sample = replay.events[2].event else {
        throw TestFailure(description: "sample ordering changed")
    }
    guard case .strokeCompleted = replay.events[3].event else {
        throw TestFailure(description: "stroke did not complete last")
    }
}

test("replay preserves hover separately from measured ink") {
    let replay = try loadReplay([
        startRow(strokeID: 7, uptime: 700),
        sampleRow(id: 7, strokeID: 7, uptime: 710, eligible: true),
        completionRow(strokeID: 7, uptime: 720),
        hoverRow(uptime: 730),
    ])

    let hoverSamples = replay.events.compactMap { entry -> RawHoverSample? in
        guard case let .hover(sample) = entry.event else {
            return nil
        }
        return sample
    }
    try expect(hoverSamples.count == 1, "hover was dropped or duplicated")
    guard let hover = hoverSamples.first else {
        throw TestFailure(description: "hover replay was empty")
    }
    try expect(
        hover.source == .outOfStrokeDot
            && hover.page == page
            && hover.force == 3
            && hover.x == 12.25
            && hover.y == 34.5,
        "hover replay changed its source, page, force, or coordinates"
    )
    try expect(
        strokeIDs(in: replay).allSatisfy { $0 == 7 },
        "hover was assigned to an ink stroke"
    )
}

test("replay accepts legacy and current latency field names") {
    let replay = try loadReplay([
        startRow(
            strokeID: 5,
            uptime: 500,
            latencyKey: "input_latency_ms",
            latency: 17
        ),
        sampleRow(
            id: 5,
            strokeID: 5,
            uptime: 510,
            eligible: nil,
            latencyKey: "input_latency_ms",
            latency: 19
        ),
        completionRow(
            strokeID: 5,
            uptime: 520,
            latencyKey: "completion_latency_ms",
            latency: 23
        ),
        startRow(strokeID: 6, uptime: 600, latency: 29),
        sampleRow(
            id: 6,
            strokeID: 6,
            uptime: 610,
            eligible: nil,
            latency: 31
        ),
        completionRow(strokeID: 6, uptime: 620, latency: 37),
    ])

    let starts = replay.events.compactMap { entry -> InputStrokeStarted? in
        guard case let .strokeStarted(stroke) = entry.event else {
            return nil
        }
        return stroke
    }
    let samples = replay.events.compactMap { entry -> RawPenSample? in
        guard case let .sample(sample) = entry.event else {
            return nil
        }
        return sample
    }
    let completions = replay.events.compactMap {
        entry -> InputStrokeCompleted? in
        guard case let .strokeCompleted(stroke) = entry.event else {
            return nil
        }
        return stroke
    }

    try expect(
        starts.map(\.inputLatencyMilliseconds) == [17, 29],
        "start latency schema compatibility changed"
    )
    try expect(
        samples.map(\.protocolClockDeltaMilliseconds) == [19, 31],
        "sample latency schema compatibility changed"
    )
    try expect(
        completions.map(\.completionLatencyMilliseconds) == [23, 37],
        "completion latency schema compatibility changed"
    )
}

test("replay rebases timed events while preserving drawing payload") {
    let replay = try loadReplay([
        startRow(strokeID: 7, uptime: 700, latency: 41),
        sampleRow(
            id: 7,
            strokeID: 7,
            uptime: 710,
            eligible: nil,
            latency: 43
        ),
        completionRow(strokeID: 7, uptime: 720, latency: 47),
        hoverRow(uptime: 730),
    ])
    let arrival = InputArrivalTime(
        wallClockMilliseconds: 9_000,
        uptimeNanoseconds: 12_000
    )
    let rebased = replay.events.map {
        $0.event.replayed(at: arrival)
    }

    guard case let .strokeStarted(started) = rebased[0],
          case let .sample(sample) = rebased[2],
          case let .strokeCompleted(completed) = rebased[3],
          case let .hover(hover) = rebased[4]
    else {
        throw TestFailure(description: "replayed event shapes changed")
    }
    try expect(
        started.penTimestampMilliseconds == 9_000
            && started.receivedUptimeNanoseconds == 12_000
            && started.inputLatencyMilliseconds == 0,
        "stroke start was not rebased"
    )
    try expect(
        sample.receivedWallClockMilliseconds == 9_000
            && sample.receivedUptimeNanoseconds == 12_000
            && sample.protocolClockDeltaMilliseconds == 0,
        "sample arrival was not rebased"
    )
    try expect(
        sample.x == 12.25
            && sample.y == 34.5
            && sample.pressure == 0.5
            && sample.transportBatchID == 7,
        "sample drawing payload changed during rebase"
    )
    try expect(
        completed.endedAtPenMilliseconds == 9_000
            && completed.startedAtPenMilliseconds == 8_980
            && completed.receivedUptimeNanoseconds == 12_000
            && completed.completionLatencyMilliseconds == 0,
        "stroke completion was not rebased"
    )
    try expect(
        hover.receivedWallClockMilliseconds == 9_000
            && hover.receivedUptimeNanoseconds == 12_000
            && hover.source == .outOfStrokeDot
            && hover.force == 3,
        "hover timing or payload changed during rebase"
    )
}

test("replay preserves mouse input without a calibrated page") {
    let mouseStrokeID = 1 << 62
    var start = startRow(
        strokeID: mouseStrokeID,
        uptime: 800
    )
    var sample = sampleRow(
        id: mouseStrokeID,
        strokeID: mouseStrokeID,
        uptime: 810
    )
    var completion = completionRow(
        strokeID: mouseStrokeID,
        uptime: 820
    )
    for key in [
        "page_section",
        "page_owner",
        "page_note",
        "page_number",
    ] {
        sample.removeValue(forKey: key)
        completion.removeValue(forKey: key)
    }
    start["input_source"] = "mouse"
    sample["input_source"] = "mouse"
    completion["input_source"] = "mouse"
    sample["x"] = 0.25
    sample["y"] = 0.75

    let replay = try loadReplay([start, sample, completion])
    try expect(
        replay.events.count == 3,
        "mouse replay added a calibrated page event"
    )
    try expect(
        replay.events.allSatisfy { $0.inputSource == .mouse },
        "mouse replay lost its input source"
    )
    guard case let .sample(replayedSample) = replay.events[1].event else {
        throw TestFailure(description: "mouse sample was not replayed")
    }
    try expect(
        replayedSample.page == nil
            && replayedSample.x == 0.25
            && replayedSample.y == 0.75,
        "mouse replay changed its page or normalized coordinates"
    )
}

if failureCount > 0 {
    exit(1)
}
