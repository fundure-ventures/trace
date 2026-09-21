import Darwin
import Foundation
import NeoInput
import NeoTransport
import TraceCalibration
import TraceGeometry

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

private func started(_ strokeID: UInt64) -> NeoInputEvent {
    .strokeStarted(
        InputStrokeStarted(
            strokeID: strokeID,
            penTimestampMilliseconds: strokeID * 100,
            receivedWallClockMilliseconds: strokeID * 100,
            receivedUptimeNanoseconds: strokeID * 100_000_000,
            inputLatencyMilliseconds: 0,
            tipType: .normal,
            color: 0xFF00_0000
        )
    )
}

private func sample(
    id: UInt64,
    strokeID: UInt64,
    x: Double,
    y: Double,
    page samplePage: PenPageID = page
) -> NeoInputEvent {
    .sample(
        RawPenSample(
            id: id,
            strokeID: strokeID,
            sampleIndex: Int(id),
            eventCount: UInt8(id),
            page: samplePage,
            penTimestampMilliseconds: strokeID * 100 + id,
            receivedWallClockMilliseconds: strokeID * 100 + id,
            receivedUptimeNanoseconds: id * 1_000_000,
            protocolClockDeltaMilliseconds: 0,
            interArrivalMilliseconds: nil,
            x: x,
            y: y,
            force: 400,
            pressure: 0.5,
            tiltX: 90,
            tiltY: 45,
            twist: 120,
            continuity: id == 1 ? .first : .continuous
        )
    )
}

private func completed(_ strokeID: UInt64) -> NeoInputEvent {
    .strokeCompleted(
        InputStrokeCompleted(
            strokeID: strokeID,
            page: page,
            startedAtPenMilliseconds: strokeID * 100,
            endedAtPenMilliseconds: strokeID * 100 + 10,
            durationMilliseconds: 10,
            sampleCount: 2,
            opticalErrorCount: 0,
            reportedDotCount: 2,
            totalImageCount: 2,
            processedImageCount: 2,
            successfulImageCount: 2,
            sentImageCount: 2,
            imageRecognitionRate: 1
        )
    )
}

test("calibration registers the page before capturing TL TR BR BL") {
    let session = SurfaceCalibrationSession()
    let corners = [
        NcodePoint(x: 10, y: 20),
        NcodePoint(x: 90, y: 20),
        NcodePoint(x: 90, y: 130),
        NcodePoint(x: 10, y: 130),
    ]
    var updates: [CalibrationUpdate] = []

    try expect(session.isAwaitingPageRegistration, "session skipped page registration")
    try expect(session.currentCorner == nil, "corner started before page registration")
    _ = session.receive(started(1))
    _ = session.receive(.pageChanged(page))
    if let update = session.receive(completed(1)) {
        updates.append(update)
    }

    for (index, corner) in corners.enumerated() {
        let strokeID = UInt64(index + 2)
        _ = session.receive(started(strokeID))
        _ = session.receive(
            sample(
                id: 1,
                strokeID: strokeID,
                x: corner.x - 0.1,
                y: corner.y - 0.2
            )
        )
        _ = session.receive(
            sample(
                id: 2,
                strokeID: strokeID,
                x: corner.x + 0.1,
                y: corner.y + 0.2
            )
        )
        if let update = session.receive(completed(strokeID)) {
            updates.append(update)
        }
    }

    try expect(
        updates.first == .pageRegistered(page: page, next: .topLeft),
        "page registration was not surfaced"
    )
    try expect(updates.count == 5, "calibration did not report every stage")
    guard case let .completed(surface) = updates[4] else {
        throw TestFailure(description: "fourth corner did not complete calibration")
    }
    try expect(surface.page == page, "calibration page changed")
    for (captured, expected) in zip(surface.calibration.corners, corners) {
        try expect(abs(captured.x - expected.x) < 0.000_001, "median X changed")
        try expect(abs(captured.y - expected.y) < 0.000_001, "median Y changed")
    }
    try expect(session.currentCorner == nil, "completed session still expects a corner")
}

test("calibration retries a corner with no recognized samples") {
    let session = SurfaceCalibrationSession()
    _ = session.receive(started(1))
    _ = session.receive(.pageChanged(page))
    _ = session.receive(completed(1))
    _ = session.receive(started(2))
    let update = session.receive(completed(2))

    try expect(
        update == .retry(corner: .topLeft, reason: .noRecognizedSamples),
        "empty calibration tap advanced"
    )
    try expect(session.currentCorner == .topLeft, "retry changed the current corner")
}

test("calibration retries page registration when no page is recognized") {
    let session = SurfaceCalibrationSession()
    _ = session.receive(started(1))
    let update = session.receive(completed(1))

    try expect(update == .retryPageRegistration, "missing page identity advanced")
    try expect(session.isAwaitingPageRegistration, "page retry changed stage")
}

test("calibration applies across pages in the same notebook family") {
    let surface = CalibratedSurface(
        page: page,
        calibration: try NcodeSurfaceCalibration(
            corners: [
                NcodePoint(x: 10, y: 20),
                NcodePoint(x: 90, y: 20),
                NcodePoint(x: 90, y: 130),
                NcodePoint(x: 10, y: 130),
            ]
        )
    )
    let nextPage = PenPageID(
        section: page.section,
        owner: page.owner,
        note: page.note,
        page: page.page + 1
    )

    try expect(
        surface.isCalibrationCompatible(with: nextPage),
        "same notebook family rejected a different page"
    )
    try expect(
        !surface.isCalibrationCompatible(
            with: PenPageID(
                section: page.section + 1,
                owner: page.owner,
                note: page.note,
                page: page.page
            )
        ),
        "changed section reused calibration"
    )
    try expect(
        !surface.isCalibrationCompatible(
            with: PenPageID(
                section: page.section,
                owner: page.owner + 1,
                note: page.note,
                page: page.page
            )
        ),
        "changed owner reused calibration"
    )
    try expect(
        !surface.isCalibrationCompatible(
            with: PenPageID(
                section: page.section,
                owner: page.owner,
                note: page.note + 1,
                page: page.page
            )
        ),
        "changed note reused calibration"
    )
}

test("calibration rejects a page turn while capturing corners") {
    let session = SurfaceCalibrationSession()
    _ = session.receive(started(1))
    _ = session.receive(.pageChanged(page))
    _ = session.receive(completed(1))
    _ = session.receive(started(2))
    _ = session.receive(sample(id: 1, strokeID: 2, x: 10, y: 20))
    _ = session.receive(completed(2))

    let nextPage = PenPageID(
        section: page.section,
        owner: page.owner,
        note: page.note,
        page: page.page + 1
    )
    _ = session.receive(started(3))
    _ = session.receive(
        sample(
            id: 2,
            strokeID: 3,
            x: 90,
            y: 20,
            page: nextPage
        )
    )
    let update = session.receive(completed(3))

    try expect(
        update == .retry(corner: .topRight, reason: .differentPage),
        "page turn combined corners from different physical pages"
    )
    try expect(
        session.currentCorner == .topRight,
        "page-turn retry advanced calibration"
    )
}

test("calibration store round-trips the completed surface") {
    let directory = FileManager.default.temporaryDirectory
        .appendingPathComponent(UUID().uuidString, isDirectory: true)
    defer {
        try? FileManager.default.removeItem(at: directory)
    }
    let store = LocalCalibrationStore(
        fileURL: directory.appendingPathComponent("calibration.json")
    )
    let surface = CalibratedSurface(
        page: page,
        calibration: try NcodeSurfaceCalibration(
            corners: [
                NcodePoint(x: 10, y: 20),
                NcodePoint(x: 90, y: 20),
                NcodePoint(x: 90, y: 130),
                NcodePoint(x: 10, y: 130),
            ]
        )
    )

    try store.save(surface)
    let loaded = try store.load()
    try expect(loaded == surface, "saved calibration did not round-trip")
    try expect(
        loaded?.isCalibrationCompatible(
            with: PenPageID(
                section: page.section,
                owner: page.owner,
                note: page.note,
                page: page.page + 1
            )
        ) == true,
        "loaded calibration lost notebook-family compatibility"
    )
}

if failureCount > 0 {
    fputs("\(failureCount) test(s) failed\n", stderr)
    exit(1)
}

print("All Trace calibration tests passed.")
