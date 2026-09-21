import Foundation

public struct PenDeviceInfo: Equatable, Sendable {
    public let modelName: String
    public let firmwareVersion: String
    public let protocolVersion: String
    public let subName: String
    public let deviceType: UInt16
    public let macAddress: String
    public let pressureSensorType: UInt8?
    public let colorTypeID: Data?

    public init(
        modelName: String,
        firmwareVersion: String,
        protocolVersion: String,
        subName: String,
        deviceType: UInt16,
        macAddress: String,
        pressureSensorType: UInt8?,
        colorTypeID: Data?
    ) {
        self.modelName = modelName
        self.firmwareVersion = firmwareVersion
        self.protocolVersion = protocolVersion
        self.subName = subName
        self.deviceType = deviceType
        self.macAddress = macAddress
        self.pressureSensorType = pressureSensorType
        self.colorTypeID = colorTypeID
    }
}

public struct PenDeviceStatus: Equatable, Sendable {
    public let isLocked: Bool
    public let passwordMaxRetryCount: UInt8
    public let passwordRetryCount: UInt8
    public let timestampMilliseconds: UInt64
    public let autoPowerOffMinutes: UInt16
    public let maxForce: UInt16
    public let usedStoragePercent: UInt8
    public let penCapPowerOffEnabled: Bool
    public let autoPowerOnEnabled: Bool
    public let beepEnabled: Bool
    public let hoverEnabled: Bool
    public let batteryPercent: UInt8
    public let isCharging: Bool
    public let offlineDataEnabled: Bool
    public let pressureSensitivityStep: UInt8?

    public init(
        isLocked: Bool,
        passwordMaxRetryCount: UInt8,
        passwordRetryCount: UInt8,
        timestampMilliseconds: UInt64,
        autoPowerOffMinutes: UInt16,
        maxForce: UInt16,
        usedStoragePercent: UInt8,
        penCapPowerOffEnabled: Bool,
        autoPowerOnEnabled: Bool,
        beepEnabled: Bool,
        hoverEnabled: Bool,
        batteryPercent: UInt8,
        isCharging: Bool,
        offlineDataEnabled: Bool,
        pressureSensitivityStep: UInt8?
    ) {
        self.isLocked = isLocked
        self.passwordMaxRetryCount = passwordMaxRetryCount
        self.passwordRetryCount = passwordRetryCount
        self.timestampMilliseconds = timestampMilliseconds
        self.autoPowerOffMinutes = autoPowerOffMinutes
        self.maxForce = maxForce
        self.usedStoragePercent = usedStoragePercent
        self.penCapPowerOffEnabled = penCapPowerOffEnabled
        self.autoPowerOnEnabled = autoPowerOnEnabled
        self.beepEnabled = beepEnabled
        self.hoverEnabled = hoverEnabled
        self.batteryPercent = batteryPercent
        self.isCharging = isCharging
        self.offlineDataEnabled = offlineDataEnabled
        self.pressureSensitivityStep = pressureSensitivityStep
    }
}

public enum PenShutdownReason: Equatable, Sendable, CustomStringConvertible {
    case firmwareUpdate
    case manualPowerOff
    case capAttached
    case unknown(UInt8)

    public init(rawCode: UInt8) {
        switch rawCode {
        case 2:
            self = .firmwareUpdate
        case 3:
            self = .manualPowerOff
        case 4:
            self = .capAttached
        default:
            self = .unknown(rawCode)
        }
    }

    public var rawCode: UInt8 {
        switch self {
        case .firmwareUpdate:
            return 2
        case .manualPowerOff:
            return 3
        case .capAttached:
            return 4
        case let .unknown(rawCode):
            return rawCode
        }
    }

    public var description: String {
        switch self {
        case .firmwareUpdate:
            return "firmwareUpdate(2)"
        case .manualPowerOff:
            return "manualPowerOff(3)"
        case .capAttached:
            return "capAttached(4)"
        case let .unknown(rawCode):
            return "unknown(\(rawCode))"
        }
    }
}

public enum NeoProtocolMessage: Equatable, Sendable {
    case deviceInfo(PenDeviceInfo)
    case status(PenDeviceStatus)
    case onlineDataEnabled
    case settingChanged(PenSetting)
    case penDown(PenDownEvent)
    case penUp(PenUpEvent)
    case pageChanged(PenPageInfo)
    case dot(PenDotEvent)
    case imageProcessingError(PenImageProcessingError)
    case hover(PenHoverEvent)
    case lowBattery(percent: UInt8)
    case shutdown(reason: PenShutdownReason)
    case unhandled(command: UInt8, result: UInt8?, payload: Data)
}

public enum NeoProtocolError: Error, Equatable, CustomStringConvertible {
    case invalidFrameBoundary
    case frameTooShort(actual: Int)
    case payloadLengthMismatch(command: UInt8, expected: Int, actual: Int)
    case payloadTooShort(command: UInt8, expected: Int, actual: Int)
    case commandFailed(command: UInt8, result: UInt8, payload: Data)

    public var description: String {
        switch self {
        case .invalidFrameBoundary:
            return "Neo packet has invalid frame boundaries"
        case let .frameTooShort(actual):
            return "Neo packet is too short (\(actual) bytes)"
        case let .payloadLengthMismatch(command, expected, actual):
            return String(
                format: "Neo command 0x%02X declared %d payload bytes but contained %d",
                command,
                expected,
                actual
            )
        case let .payloadTooShort(command, expected, actual):
            return String(
                format: "Neo command 0x%02X needs at least %d payload bytes but contained %d",
                command,
                expected,
                actual
            )
        case let .commandFailed(command, result, _):
            return String(
                format: "Neo command 0x%02X failed with result 0x%02X",
                command,
                result
            )
        }
    }
}

public enum NeoProtocol {
    public static let supportedVersion = "2.12"

    public static func makeVersionRequest(
        appVersion: String,
        supportedProtocolVersion: String = supportedVersion
    ) -> Data {
        var payload = Data(repeating: 0, count: 16)
        payload.append(contentsOf: [0x12, 0x01])
        payload.append(fixedWidthUTF8(appVersion, count: 16))
        payload.append(fixedWidthUTF8(supportedProtocolVersion, count: 8))
        return NeoPacketCodec.encodeRequest(command: 0x01, payload: payload)
    }

    public static func makeStatusRequest() -> Data {
        NeoPacketCodec.encodeRequest(command: 0x04)
    }

    public static func makeEnableOnlineDataRequest() -> Data {
        NeoPacketCodec.encodeRequest(
            command: 0x11,
            payload: Data([0xFF, 0xFF])
        )
    }

    public static func makeSetHoverRequest(enabled: Bool) -> Data {
        makeSetBooleanRequest(
            setting: .hover,
            enabled: enabled
        )
    }

    public static func makeSetBeepRequest(enabled: Bool) -> Data {
        makeSetBooleanRequest(setting: .beep, enabled: enabled)
    }

    public static func makeSetOfflineDataRequest(enabled: Bool) -> Data {
        makeSetBooleanRequest(
            setting: .offlineData,
            enabled: enabled
        )
    }

    public static func makeSetAutoPowerOnRequest(enabled: Bool) -> Data {
        makeSetBooleanRequest(
            setting: .autoPowerOn,
            enabled: enabled
        )
    }

    public static func makeSetPenCapPowerOffRequest(
        enabled: Bool
    ) -> Data {
        makeSetBooleanRequest(
            setting: .penCapPowerOff,
            enabled: enabled
        )
    }

    public static func makeSetAutoPowerOffRequest(
        minutes: UInt16
    ) -> Data {
        NeoPacketCodec.encodeRequest(
            command: 0x05,
            payload: Data([
                PenSetting.autoPowerOff.rawValue,
                UInt8(minutes & 0xFF),
                UInt8((minutes >> 8) & 0xFF),
            ])
        )
    }

    public static func makeSetSensitivityRequest(step: UInt8) -> Data {
        NeoPacketCodec.encodeRequest(
            command: 0x05,
            payload: Data([
                PenSetting.sensitivity.rawValue,
                step,
            ])
        )
    }

    public static func makeSetTimeRequest(milliseconds: UInt64) -> Data {
        var payload = Data([PenSetting.timestamp.rawValue])
        for index in 0..<8 {
            payload.append(UInt8((milliseconds >> UInt64(index * 8)) & 0xFF))
        }
        return NeoPacketCodec.encodeRequest(command: 0x05, payload: payload)
    }

    private static func makeSetBooleanRequest(
        setting: PenSetting,
        enabled: Bool
    ) -> Data {
        NeoPacketCodec.encodeRequest(
            command: 0x05,
            payload: Data([
                setting.rawValue,
                enabled ? 1 : 0,
            ])
        )
    }

    private static func fixedWidthUTF8(_ value: String, count: Int) -> Data {
        var result = Data(value.utf8.prefix(count))
        if result.count < count {
            result.append(Data(repeating: 0, count: count - result.count))
        }
        return result
    }
}

public enum NeoProtocolDecoder {
    public static func decode(frame: Data) throws -> NeoProtocolMessage {
        let bytes = [UInt8](frame)
        guard bytes.first == NeoPacketCodec.startByte,
              bytes.last == NeoPacketCodec.endByte
        else {
            throw NeoProtocolError.invalidFrameBoundary
        }
        guard bytes.count >= 5 else {
            throw NeoProtocolError.frameTooShort(actual: bytes.count)
        }

        let command = bytes[1]
        let isEvent = isEventCommand(command)
        let result: UInt8?
        let payloadLength: Int
        let payloadStart: Int

        if isEvent {
            result = nil
            payloadLength = littleEndianUInt16(bytes, at: 2)
            payloadStart = 4
        } else {
            guard bytes.count >= 6 else {
                throw NeoProtocolError.frameTooShort(actual: bytes.count)
            }
            result = bytes[2]
            payloadLength = littleEndianUInt16(bytes, at: 3)
            payloadStart = 5
        }

        let payloadEnd = bytes.count - 1
        let actualPayloadLength = payloadEnd - payloadStart
        guard actualPayloadLength == payloadLength else {
            throw NeoProtocolError.payloadLengthMismatch(
                command: command,
                expected: payloadLength,
                actual: actualPayloadLength
            )
        }

        let payload = Data(bytes[payloadStart..<payloadEnd])
        if let result, result != 0 {
            throw NeoProtocolError.commandFailed(
                command: command,
                result: result,
                payload: payload
            )
        }

        switch command {
        case 0x81:
            return .deviceInfo(try decodeDeviceInfo(payload, command: command))
        case 0x84:
            return .status(try decodeStatus(payload, command: command))
        case 0x85:
            try requirePayload(payload, command: command, minimumCount: 1)
            if let setting = PenSetting(rawValue: payload[0]) {
                return .settingChanged(setting)
            }
            return .unhandled(command: command, result: result, payload: payload)
        case 0x91:
            return .onlineDataEnabled
        case 0x69:
            return .penDown(try decodePenDown(payload, command: command))
        case 0x6A:
            return .penUp(try decodePenUp(payload, command: command))
        case 0x6B:
            return .pageChanged(try decodePageInfo(payload, command: command))
        case 0x6C:
            return .dot(try decodeDot(payload, command: command))
        case 0x6D:
            return .imageProcessingError(
                try decodeImageProcessingError(payload, command: command)
            )
        case 0x6F:
            return .hover(try decodeHover(payload, command: command))
        case 0x61:
            try requirePayload(payload, command: command, minimumCount: 1)
            return .lowBattery(percent: payload[0])
        case 0x62:
            try requirePayload(payload, command: command, minimumCount: 1)
            return .shutdown(reason: PenShutdownReason(rawCode: payload[0]))
        default:
            return .unhandled(command: command, result: result, payload: payload)
        }
    }

    private static func decodeDeviceInfo(
        _ payload: Data,
        command: UInt8
    ) throws -> PenDeviceInfo {
        try requirePayload(payload, command: command, minimumCount: 64)
        let bytes = [UInt8](payload)

        return PenDeviceInfo(
            modelName: fixedWidthString(bytes, range: 0..<16),
            firmwareVersion: fixedWidthString(bytes, range: 16..<32),
            protocolVersion: fixedWidthString(bytes, range: 32..<40),
            subName: fixedWidthString(bytes, range: 40..<56),
            deviceType: UInt16(littleEndianUInt16(bytes, at: 56)),
            macAddress: bytes[58..<64]
                .map { String(format: "%02X", $0) }
                .joined(separator: ":"),
            pressureSensorType: bytes.count > 64 ? bytes[64] : nil,
            colorTypeID: bytes.count >= 69 ? Data(bytes[65..<69]) : nil
        )
    }

    private static func decodeStatus(
        _ payload: Data,
        command: UInt8
    ) throws -> PenDeviceStatus {
        try requirePayload(payload, command: command, minimumCount: 23)
        let bytes = [UInt8](payload)
        let battery = bytes[20]
        let sensitivity = bytes[22] == 0xFF ? nil : bytes[22]

        return PenDeviceStatus(
            isLocked: bytes[0] == 1,
            passwordMaxRetryCount: bytes[1],
            passwordRetryCount: bytes[2],
            timestampMilliseconds: littleEndianUInt64(bytes, at: 3),
            autoPowerOffMinutes: UInt16(littleEndianUInt16(bytes, at: 11)),
            maxForce: UInt16(littleEndianUInt16(bytes, at: 13)),
            usedStoragePercent: bytes[15],
            penCapPowerOffEnabled: bytes[16] == 1,
            autoPowerOnEnabled: bytes[17] == 1,
            beepEnabled: bytes[18] == 1,
            hoverEnabled: bytes[19] == 1,
            batteryPercent: battery & 0x7F,
            isCharging: battery & 0x80 != 0,
            offlineDataEnabled: bytes[21] == 1,
            pressureSensitivityStep: sensitivity
        )
    }

    private static func decodePenDown(
        _ payload: Data,
        command: UInt8
    ) throws -> PenDownEvent {
        try requirePayload(payload, command: command, minimumCount: 14)
        let bytes = [UInt8](payload)
        return PenDownEvent(
            eventCount: bytes[0],
            timestampMilliseconds: littleEndianUInt64(bytes, at: 1),
            tipType: PenTipType(rawCode: bytes[9]),
            color: littleEndianUInt32(bytes, at: 10)
        )
    }

    private static func decodePenUp(
        _ payload: Data,
        command: UInt8
    ) throws -> PenUpEvent {
        try requirePayload(payload, command: command, minimumCount: 19)
        let bytes = [UInt8](payload)
        return PenUpEvent(
            eventCount: bytes[0],
            timestampMilliseconds: littleEndianUInt64(bytes, at: 1),
            dotCount: littleEndianUInt16Value(bytes, at: 9),
            totalImageCount: littleEndianUInt16Value(bytes, at: 11),
            processedImageCount: littleEndianUInt16Value(bytes, at: 13),
            successfulImageCount: littleEndianUInt16Value(bytes, at: 15),
            sentImageCount: littleEndianUInt16Value(bytes, at: 17)
        )
    }

    private static func decodePageInfo(
        _ payload: Data,
        command: UInt8
    ) throws -> PenPageInfo {
        try requirePayload(payload, command: command, minimumCount: 13)
        let bytes = [UInt8](payload)
        let owner = UInt32(bytes[1])
            | UInt32(bytes[2]) << 8
            | UInt32(bytes[3]) << 16
        return PenPageInfo(
            eventCount: bytes[0],
            section: bytes[4],
            owner: owner,
            note: littleEndianUInt32(bytes, at: 5),
            page: littleEndianUInt32(bytes, at: 9)
        )
    }

    private static func decodeDot(
        _ payload: Data,
        command: UInt8
    ) throws -> PenDotEvent {
        try requirePayload(payload, command: command, minimumCount: 14)
        let bytes = [UInt8](payload)
        return PenDotEvent(
            eventCount: bytes[0],
            timeDeltaMilliseconds: bytes[1],
            force: littleEndianUInt16Value(bytes, at: 2),
            x: littleEndianUInt16Value(bytes, at: 4),
            y: littleEndianUInt16Value(bytes, at: 6),
            fractionX: bytes[8],
            fractionY: bytes[9],
            tiltX: bytes[10],
            tiltY: bytes[11],
            twist: littleEndianUInt16Value(bytes, at: 12)
        )
    }

    private static func decodeImageProcessingError(
        _ payload: Data,
        command: UInt8
    ) throws -> PenImageProcessingError {
        try requirePayload(payload, command: command, minimumCount: 12)
        let bytes = [UInt8](payload)
        return PenImageProcessingError(
            eventCount: bytes[0],
            timeDeltaMilliseconds: bytes[1],
            force: littleEndianUInt16Value(bytes, at: 2),
            imageBrightness: bytes[4],
            exposureTime: bytes[5],
            processingTime: bytes[6],
            labelCount: littleEndianUInt16Value(bytes, at: 7),
            errorCode: bytes[9],
            classType: bytes[10],
            errorCount: bytes[11]
        )
    }

    private static func decodeHover(
        _ payload: Data,
        command: UInt8
    ) throws -> PenHoverEvent {
        try requirePayload(payload, command: command, minimumCount: 7)
        let bytes = [UInt8](payload)
        return PenHoverEvent(
            timeDeltaMilliseconds: bytes[0],
            x: littleEndianUInt16Value(bytes, at: 1),
            y: littleEndianUInt16Value(bytes, at: 3),
            fractionX: bytes[5],
            fractionY: bytes[6]
        )
    }

    private static func isEventCommand(_ command: UInt8) -> Bool {
        (0x60...0x6F).contains(command)
            || command == 0x24
            || command == 0x32
            || command == 0x73
            || (0x78...0x7F).contains(command)
    }

    private static func requirePayload(
        _ payload: Data,
        command: UInt8,
        minimumCount: Int
    ) throws {
        guard payload.count >= minimumCount else {
            throw NeoProtocolError.payloadTooShort(
                command: command,
                expected: minimumCount,
                actual: payload.count
            )
        }
    }

    private static func fixedWidthString(
        _ bytes: [UInt8],
        range: Range<Int>
    ) -> String {
        let field = bytes[range].prefix { $0 != 0 }
        return String(decoding: field, as: UTF8.self)
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private static func littleEndianUInt16(_ bytes: [UInt8], at offset: Int) -> Int {
        Int(bytes[offset]) | (Int(bytes[offset + 1]) << 8)
    }

    private static func littleEndianUInt16Value(
        _ bytes: [UInt8],
        at offset: Int
    ) -> UInt16 {
        UInt16(bytes[offset]) | UInt16(bytes[offset + 1]) << 8
    }

    private static func littleEndianUInt32(_ bytes: [UInt8], at offset: Int) -> UInt32 {
        var value: UInt32 = 0
        for index in 0..<4 {
            value |= UInt32(bytes[offset + index]) << UInt32(index * 8)
        }
        return value
    }

    private static func littleEndianUInt64(_ bytes: [UInt8], at offset: Int) -> UInt64 {
        var value: UInt64 = 0
        for index in 0..<8 {
            value |= UInt64(bytes[offset + index]) << UInt64(index * 8)
        }
        return value
    }
}
