import Darwin
import Foundation
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

private func expectClose(
    _ actual: UnitPoint?,
    _ expected: UnitPoint,
    tolerance: Double = 0.000_001,
    file: StaticString = #filePath,
    line: UInt = #line
) throws {
    guard let actual else {
        throw TestFailure(description: "transform returned no point (\(file):\(line))")
    }
    try expect(
        abs(actual.x - expected.x) <= tolerance
            && abs(actual.y - expected.y) <= tolerance,
        "expected \(expected), got \(actual)",
        file: file,
        line: line
    )
}

test("four paper corners calibrate Ncode into unit canvas space") {
    let calibration = try NcodeSurfaceCalibration(
        corners: [
            NcodePoint(x: 10, y: 20),
            NcodePoint(x: 90, y: 20),
            NcodePoint(x: 90, y: 130),
            NcodePoint(x: 10, y: 130),
        ]
    )

    try expectClose(
        calibration.normalize(NcodePoint(x: 10, y: 20)),
        UnitPoint(x: 0, y: 0)
    )
    try expectClose(
        calibration.normalize(NcodePoint(x: 90, y: 20)),
        UnitPoint(x: 1, y: 0)
    )
    try expectClose(
        calibration.normalize(NcodePoint(x: 90, y: 130)),
        UnitPoint(x: 1, y: 1)
    )
    try expectClose(
        calibration.normalize(NcodePoint(x: 10, y: 130)),
        UnitPoint(x: 0, y: 1)
    )
    try expectClose(
        calibration.normalize(NcodePoint(x: 50, y: 75)),
        UnitPoint(x: 0.5, y: 0.5)
    )
    try expect(
        abs(calibration.estimatedAspectRatio - (80.0 / 110.0)) < 0.000_001,
        "calibrated aspect ratio changed"
    )
}

test("projective calibration handles a skewed four-corner capture") {
    let calibration = try NcodeSurfaceCalibration(
        corners: [
            NcodePoint(x: 12, y: 18),
            NcodePoint(x: 92, y: 23),
            NcodePoint(x: 86, y: 132),
            NcodePoint(x: 8, y: 125),
        ]
    )

    let expectedCorners = [
        UnitPoint(x: 0, y: 0),
        UnitPoint(x: 1, y: 0),
        UnitPoint(x: 1, y: 1),
        UnitPoint(x: 0, y: 1),
    ]
    for (corner, expected) in zip(calibration.corners, expectedCorners) {
        try expectClose(calibration.normalize(corner), expected)
    }
}

test("calibration rejects missing or degenerate corners") {
    do {
        _ = try NcodeSurfaceCalibration(
            corners: [
                NcodePoint(x: 0, y: 0),
                NcodePoint(x: 1, y: 0),
                NcodePoint(x: 1, y: 1),
            ]
        )
        throw TestFailure(description: "three-corner calibration unexpectedly succeeded")
    } catch CalibrationError.requiresFourCorners {
    }

    do {
        _ = try NcodeSurfaceCalibration(
            corners: Array(repeating: NcodePoint(x: 1, y: 1), count: 4)
        )
        throw TestFailure(description: "degenerate calibration unexpectedly succeeded")
    } catch CalibrationError.degenerateGeometry {
    }
}

if failureCount > 0 {
    fputs("\(failureCount) test(s) failed\n", stderr)
    exit(1)
}

print("All Trace geometry tests passed.")
