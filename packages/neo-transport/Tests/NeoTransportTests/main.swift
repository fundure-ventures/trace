import Foundation
import Darwin
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

private func require<T>(
    _ value: T?,
    _ message: String,
    file: StaticString = #filePath,
    line: UInt = #line
) throws -> T {
    guard let value else {
        throw TestFailure(description: "\(message) (\(file):\(line))")
    }
    return value
}

test("physical pen identity survives CoreBluetooth UUID rotation") {
    let manufacturer = Data([0x9C, 0x7B, 0xD2, 0x51, 0xF4, 0x1F])
    let first = NeoDevice(
        id: UUID(),
        name: "Neosmartpen_M1",
        rssi: -60,
        advertisedServiceUUIDs: ["19F1"],
        manufacturerData: manufacturer,
        isConnectable: true
    )
    let returning = NeoDevice(
        id: UUID(),
        name: "Neosmartpen_M1",
        rssi: -65,
        advertisedServiceUUIDs: ["19F1"],
        manufacturerData: manufacturer,
        isConnectable: true
    )
    let other = NeoDevice(
        id: UUID(),
        name: "Neosmartpen_M1",
        rssi: -65,
        advertisedServiceUUIDs: ["19F1"],
        manufacturerData: Data([1, 2, 3, 4, 5, 6]),
        isConnectable: true
    )

    try expect(
        first.hasSamePhysicalIdentity(as: returning),
        "stable manufacturer identity did not survive UUID rotation"
    )
    try expect(
        !first.hasSamePhysicalIdentity(as: other),
        "different physical pens were treated as the same device"
    )
}

test("request framing escapes reserved bytes") {
    let encoded = NeoPacketCodec.encodeRequest(
        command: 0x04,
        payload: Data([0xC0, 0xC1, 0x7D, 0x20])
    )

    try expect(
        encoded == Data([
            0xC0,
            0x04,
            0x04, 0x00,
            0x7D, 0xE0,
            0x7D, 0xE1,
            0x7D, 0x5D,
            0x20,
            0xC1,
        ]),
        "encoded frame did not match the Neo v2 escaping contract"
    )
}

test("version request uses the published protocol two handshake shape") {
    let request = NeoProtocol.makeVersionRequest(
        appVersion: "0.1.0",
        supportedProtocolVersion: "2.12"
    )
    var parser = NeoPacketStreamParser()

    let frame = try require(parser.append(request).only, "expected one version frame")
    try expect(frame[frame.startIndex] == 0xC0, "version frame must start with STX")
    try expect(
        frame[frame.index(frame.startIndex, offsetBy: 1)] == 0x01,
        "version request command must be 0x01"
    )
    try expect(readUInt16LE(frame, at: 2) == 42, "version payload must be 42 bytes")

    let payload = frame.subdata(in: 4..<(frame.count - 1))
    try expect(payload.count == 42, "version payload length changed")
    try expect(
        payload.prefix(16) == Data(repeating: 0, count: 16),
        "version request prefix must be zero-filled"
    )
    try expect(payload[16] == 0x12, "application type byte changed")
    try expect(payload[17] == 0x01, "application version marker changed")
    try expect(fixedString(payload, range: 18..<34) == "0.1.0", "app version missing")
    try expect(
        fixedString(payload, range: 34..<42) == "2.12",
        "supported protocol version missing"
    )
}

test("online input request enables all available Ncode notes") {
    var parser = NeoPacketStreamParser()
    let frame = try require(
        parser.append(NeoProtocol.makeEnableOnlineDataRequest()).only,
        "expected one online data request"
    )

    try expect(
        frame == Data([0xC0, 0x11, 0x02, 0x00, 0xFF, 0xFF, 0xC1]),
        "online data request did not match AddAvailableNote()"
    )
}

test("hover setting request uses Neo setting type six") {
    var parser = NeoPacketStreamParser()
    let frame = try require(
        parser.append(NeoProtocol.makeSetHoverRequest(enabled: true)).only,
        "expected one hover setting request"
    )

    try expect(
        frame == Data([0xC0, 0x05, 0x02, 0x00, 0x06, 0x01, 0xC1]),
        "hover setting request had the wrong command or payload"
    )
}

test("writable pen settings use confirmed protocol two payloads") {
    var parser = NeoPacketStreamParser()
    let beep = try require(
        parser.append(
            NeoProtocol.makeSetBeepRequest(enabled: false)
        ).only,
        "missing beep frame"
    )
    try expect(
        beep == Data([0xC0, 0x05, 0x02, 0x00, 0x05, 0x00, 0xC1]),
        "beep setting payload changed"
    )
    let offline = try require(
        parser.append(
            NeoProtocol.makeSetOfflineDataRequest(enabled: true)
        ).only,
        "missing offline frame"
    )
    try expect(
        offline == Data([0xC0, 0x05, 0x02, 0x00, 0x07, 0x01, 0xC1]),
        "offline storage payload changed"
    )
    let autoOn = try require(
        parser.append(
            NeoProtocol.makeSetAutoPowerOnRequest(enabled: true)
        ).only,
        "missing auto-on frame"
    )
    try expect(
        autoOn == Data([0xC0, 0x05, 0x02, 0x00, 0x04, 0x01, 0xC1]),
        "auto power-on payload changed"
    )
    let capOff = try require(
        parser.append(
            NeoProtocol.makeSetPenCapPowerOffRequest(enabled: false)
        ).only,
        "missing cap shutdown frame"
    )
    try expect(
        capOff == Data([0xC0, 0x05, 0x02, 0x00, 0x03, 0x00, 0xC1]),
        "cap shutdown payload changed"
    )
    let autoOff = try require(
        parser.append(
            NeoProtocol.makeSetAutoPowerOffRequest(minutes: 30)
        ).only,
        "missing auto-off frame"
    )
    try expect(
        autoOff == Data([
            0xC0, 0x05, 0x03, 0x00, 0x02, 0x1E, 0x00, 0xC1,
        ]),
        "auto power-off payload changed"
    )
    let sensitivity = try require(
        parser.append(
            NeoProtocol.makeSetSensitivityRequest(step: 3)
        ).only,
        "missing sensitivity frame"
    )
    try expect(
        sensitivity
            == Data([0xC0, 0x05, 0x02, 0x00, 0x09, 0x03, 0xC1]),
        "sensitivity payload changed"
    )
}

test("time setting request writes the host clock in little-endian order") {
    var parser = NeoPacketStreamParser()
    let frame = try require(
        parser.append(
            NeoProtocol.makeSetTimeRequest(
                milliseconds: 0x0102_0304_0506_0708
            )
        ).only,
        "expected one time setting request"
    )

    try expect(
        frame == Data([
            0xC0,
            0x05,
            0x09, 0x00,
            0x01,
            0x08, 0x07, 0x06, 0x05, 0x04, 0x03, 0x02, 0x01,
            0xC1,
        ]),
        "time setting request had the wrong command or byte order"
    )
}

test("stream parser reassembles a split escaped frame") {
    var parser = NeoPacketStreamParser()

    try expect(parser.append(Data([0x00, 0xC0, 0x61])).isEmpty, "frame ended early")
    try expect(parser.append(Data([0x02, 0x00, 0x7D])).isEmpty, "escape ended early")
    try expect(parser.append(Data([0xE0, 0x2A])).isEmpty, "frame ended early")
    try expect(
        parser.append(Data([0xC1]))
            == [Data([0xC0, 0x61, 0x02, 0x00, 0xC0, 0x2A, 0xC1])],
        "split frame was not reassembled and unescaped"
    )
}

test("stream parser returns multiple frames from one Bluetooth read") {
    var parser = NeoPacketStreamParser()
    let first = Data([0xC0, 0x61, 0x01, 0x00, 0x53, 0xC1])
    let second = Data([0xC0, 0x62, 0x01, 0x00, 0x01, 0xC1])

    try expect(
        parser.append(first + second) == [first, second],
        "coalesced BLE frames were not separated"
    )
}

test("decoder reads version response metadata") {
    var payload = Data()
    payload.append(fixedBytes("NWP-F50", count: 16))
    payload.append(fixedBytes("1.03.0052", count: 16))
    payload.append(fixedBytes("2.12", count: 8))
    payload.append(fixedBytes("M1", count: 16))
    payload.append(contentsOf: [0x32, 0x00])
    payload.append(contentsOf: [0xAA, 0xBB, 0xCC, 0xDD, 0xEE, 0xFF])
    payload.append(0x02)
    payload.append(contentsOf: [0x01, 0x02, 0x03, 0x04])

    let message = try NeoProtocolDecoder.decode(
        frame: responseFrame(command: 0x81, payload: payload)
    )

    try expect(
        message == .deviceInfo(
            PenDeviceInfo(
                modelName: "NWP-F50",
                firmwareVersion: "1.03.0052",
                protocolVersion: "2.12",
                subName: "M1",
                deviceType: 50,
                macAddress: "AA:BB:CC:DD:EE:FF",
                pressureSensorType: 2,
                colorTypeID: Data([0x01, 0x02, 0x03, 0x04])
            )
        ),
        "version response metadata was decoded incorrectly"
    )
}

test("decoder reads pen status response") {
    var payload = Data([0x00, 0x05, 0x00])
    payload.appendLittleEndian(UInt64(123_456_789))
    payload.appendLittleEndian(UInt16(20))
    payload.appendLittleEndian(UInt16(1_023))
    payload.append(contentsOf: [
        0x07,
        0x01,
        0x01,
        0x00,
        0x01,
        0x53,
        0x01,
        0x03,
    ])

    let message = try NeoProtocolDecoder.decode(
        frame: responseFrame(command: 0x84, payload: payload)
    )

    try expect(
        message == .status(
            PenDeviceStatus(
                isLocked: false,
                passwordMaxRetryCount: 5,
                passwordRetryCount: 0,
                timestampMilliseconds: 123_456_789,
                autoPowerOffMinutes: 20,
                maxForce: 1_023,
                usedStoragePercent: 7,
                penCapPowerOffEnabled: true,
                autoPowerOnEnabled: true,
                beepEnabled: false,
                hoverEnabled: true,
                batteryPercent: 83,
                isCharging: false,
                offlineDataEnabled: true,
                pressureSensitivityStep: 3
            )
        ),
        "pen status fields were decoded incorrectly"
    )
}

test("decoder separates charging bit from battery percentage") {
    var payload = Data([0x00, 0x05, 0x00])
    payload.appendLittleEndian(UInt64(123_456_789))
    payload.appendLittleEndian(UInt16(20))
    payload.appendLittleEndian(UInt16(1_023))
    payload.append(contentsOf: [
        0x07,
        0x01,
        0x01,
        0x00,
        0x01,
        0xD3,
        0x01,
        0x03,
    ])

    let message = try NeoProtocolDecoder.decode(
        frame: responseFrame(command: 0x84, payload: payload)
    )
    guard case let .status(status) = message else {
        throw TestFailure(description: "expected a pen status response")
    }

    try expect(status.batteryPercent == 83, "charging bit leaked into percentage")
    try expect(status.isCharging, "charging bit was not decoded")
}

test("decoder reads low-battery event") {
    let battery = try NeoProtocolDecoder.decode(
        frame: eventFrame(command: 0x61, payload: Data([15]))
    )

    try expect(
        battery == .lowBattery(percent: 15),
        "low-battery event was not decoded"
    )
}

test("decoder recognizes successful online input registration") {
    let message = try NeoProtocolDecoder.decode(
        frame: responseFrame(command: 0x91, payload: Data())
    )

    try expect(
        message == .onlineDataEnabled,
        "online data response was not recognized"
    )
}

test("decoder reads live M1 pen-down event") {
    let message = try NeoProtocolDecoder.decode(
        frame: eventFrame(
            command: 0x69,
            payload: Data([
                0x00,
                0xEF, 0x4D, 0xAA, 0x8C, 0xA0, 0x01, 0x00, 0x00,
                0x00,
                0x00, 0x00, 0x00, 0xFF,
            ])
        )
    )

    try expect(
        message == .penDown(
            PenDownEvent(
                eventCount: 0,
                timestampMilliseconds: 1_789_066_366_447,
                tipType: .normal,
                color: 0xFF00_0000
            )
        ),
        "pen-down event was decoded incorrectly"
    )
}

test("decoder reads live M1 page identity event") {
    let message = try NeoProtocolDecoder.decode(
        frame: eventFrame(
            command: 0x6B,
            payload: Data([
                0x01,
                0x1B, 0x00, 0x00, 0x03,
                0x02, 0x01, 0x00, 0x00,
                0x01, 0x00, 0x00, 0x00,
            ])
        )
    )

    try expect(
        message == .pageChanged(
            PenPageInfo(
                eventCount: 1,
                section: 3,
                owner: 27,
                note: 258,
                page: 1
            )
        ),
        "page identity event was decoded incorrectly"
    )
}

test("decoder reads live M1 coordinate and pressure dot") {
    let message = try NeoProtocolDecoder.decode(
        frame: eventFrame(
            command: 0x6C,
            payload: Data([
                0x02, 0x00,
                0x94, 0x00,
                0x2E, 0x00,
                0x5B, 0x00,
                0x1B, 0x22,
                0x5F, 0x32,
                0x85, 0x00,
            ])
        )
    )

    try expect(
        message == .dot(
            PenDotEvent(
                eventCount: 2,
                timeDeltaMilliseconds: 0,
                force: 148,
                x: 46,
                y: 91,
                fractionX: 27,
                fractionY: 34,
                tiltX: 95,
                tiltY: 50,
                twist: 133
            )
        ),
        "coordinate dot was decoded incorrectly"
    )
}

test("decoder reads live M1 optical processing error") {
    let message = try NeoProtocolDecoder.decode(
        frame: eventFrame(
            command: 0x6D,
            payload: Data([
                0x05, 0x08,
                0x4E, 0x01,
                0x8E, 0x76, 0x1A,
                0xA6, 0x00,
                0x14, 0x01, 0x0B,
            ])
        )
    )

    try expect(
        message == .imageProcessingError(
            PenImageProcessingError(
                eventCount: 5,
                timeDeltaMilliseconds: 8,
                force: 334,
                imageBrightness: 142,
                exposureTime: 118,
                processingTime: 26,
                labelCount: 166,
                errorCode: 20,
                classType: 1,
                errorCount: 11
            )
        ),
        "image-processing error was decoded incorrectly"
    )
}

test("decoder reads live M1 pen-up metrics") {
    let message = try NeoProtocolDecoder.decode(
        frame: eventFrame(
            command: 0x6A,
            payload: Data([
                0x15,
                0x3C, 0x62, 0xAA, 0x8C, 0xA0, 0x01, 0x00, 0x00,
                0x56, 0x00,
                0x31, 0x01,
                0x31, 0x01,
                0x69, 0x00,
                0x56, 0x00,
            ])
        )
    )

    try expect(
        message == .penUp(
            PenUpEvent(
                eventCount: 21,
                timestampMilliseconds: 1_789_066_371_644,
                dotCount: 86,
                totalImageCount: 305,
                processedImageCount: 305,
                successfulImageCount: 105,
                sentImageCount: 86
            )
        ),
        "pen-up metrics were decoded incorrectly"
    )
}

test("decoder reads hover coordinates") {
    let message = try NeoProtocolDecoder.decode(
        frame: eventFrame(
            command: 0x6F,
            payload: Data([
                0x07,
                0x2E, 0x00,
                0x5B, 0x00,
                0x1B, 0x22,
            ])
        )
    )

    try expect(
        message == .hover(
            PenHoverEvent(
                timeDeltaMilliseconds: 7,
                x: 46,
                y: 91,
                fractionX: 27,
                fractionY: 34
            )
        ),
        "hover coordinates were decoded incorrectly"
    )
}

test("decoder recognizes hover setting response") {
    let message = try NeoProtocolDecoder.decode(
        frame: responseFrame(command: 0x85, payload: Data([0x06]))
    )

    try expect(
        message == .settingChanged(.hover),
        "hover setting response was not recognized"
    )
}

test("decoder recognizes time setting response") {
    let message = try NeoProtocolDecoder.decode(
        frame: responseFrame(command: 0x85, payload: Data([0x01]))
    )

    try expect(
        message == .settingChanged(.timestamp),
        "time setting response was not recognized"
    )
}

test("decoder normalizes firmware-update shutdown") {
    let message = try NeoProtocolDecoder.decode(
        frame: eventFrame(command: 0x62, payload: Data([2]))
    )

    try expect(
        message == .shutdown(reason: .firmwareUpdate),
        "firmware-update shutdown reason was not normalized"
    )
}

test("decoder normalizes manual power-off shutdown") {
    let message = try NeoProtocolDecoder.decode(
        frame: eventFrame(command: 0x62, payload: Data([3]))
    )

    try expect(
        message == .shutdown(reason: .manualPowerOff),
        "manual power-off reason was not normalized"
    )
}

test("decoder normalizes cap-attached shutdown") {
    let message = try NeoProtocolDecoder.decode(
        frame: eventFrame(command: 0x62, payload: Data([4]))
    )

    try expect(
        message == .shutdown(reason: .capAttached),
        "cap-attached reason was not normalized"
    )
}

test("decoder preserves unknown shutdown reason") {
    let message = try NeoProtocolDecoder.decode(
        frame: eventFrame(command: 0x62, payload: Data([0xFE]))
    )

    try expect(
        message == .shutdown(reason: .unknown(0xFE)),
        "unknown shutdown reason was not preserved"
    )
}

test("decoder retains unknown event payloads") {
    let message = try NeoProtocolDecoder.decode(
        frame: eventFrame(command: 0x73, payload: Data([1, 2, 3]))
    )

    try expect(
        message == .unhandled(command: 0x73, result: nil, payload: Data([1, 2, 3])),
        "unknown event payload was discarded"
    )
}

if failureCount > 0 {
    fputs("\(failureCount) test(s) failed\n", stderr)
    exit(1)
}

print("All Neo transport protocol tests passed.")

private extension Array {
    var only: Element? {
        count == 1 ? first : nil
    }
}

private extension Data {
    mutating func appendLittleEndian<T: FixedWidthInteger>(_ value: T) {
        var littleEndian = value.littleEndian
        Swift.withUnsafeBytes(of: &littleEndian) { append(contentsOf: $0) }
    }
}

private func responseFrame(command: UInt8, result: UInt8 = 0, payload: Data) -> Data {
    var frame = Data([0xC0, command, result])
    frame.appendLittleEndian(UInt16(payload.count))
    frame.append(payload)
    frame.append(0xC1)
    return frame
}

private func eventFrame(command: UInt8, payload: Data) -> Data {
    var frame = Data([0xC0, command])
    frame.appendLittleEndian(UInt16(payload.count))
    frame.append(payload)
    frame.append(0xC1)
    return frame
}

private func fixedBytes(_ value: String, count: Int) -> Data {
    var bytes = Data(value.utf8.prefix(count))
    if bytes.count < count {
        bytes.append(Data(repeating: 0, count: count - bytes.count))
    }
    return bytes
}

private func fixedString(_ data: Data, range: Range<Int>) -> String {
    String(decoding: data.subdata(in: range).prefix { $0 != 0 }, as: UTF8.self)
}

private func readUInt16LE(_ data: Data, at offset: Int) -> UInt16 {
    UInt16(data[offset]) | (UInt16(data[offset + 1]) << 8)
}
