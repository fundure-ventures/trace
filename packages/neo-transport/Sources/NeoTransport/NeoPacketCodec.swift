import Foundation

public enum NeoPacketCodec {
    public static let startByte: UInt8 = 0xC0
    public static let endByte: UInt8 = 0xC1
    public static let escapeByte: UInt8 = 0x7D
    public static let escapeMask: UInt8 = 0x20

    public static func encodeRequest(command: UInt8, payload: Data = Data()) -> Data {
        precondition(payload.count <= Int(UInt16.max), "Neo packet payload is too large")

        let payloadLength = UInt16(payload.count)
        var frame = Data([
            startByte,
            command,
            UInt8(payloadLength & 0x00FF),
            UInt8(payloadLength >> 8),
        ])
        frame.append(payload)
        frame.append(endByte)

        var escaped = Data([startByte])
        for byte in frame.dropFirst().dropLast() {
            if byte == startByte || byte == endByte || byte == escapeByte {
                escaped.append(escapeByte)
                escaped.append(byte ^ escapeMask)
            } else {
                escaped.append(byte)
            }
        }
        escaped.append(endByte)
        return escaped
    }
}

public struct NeoPacketStreamParser {
    private var frame = Data()
    private var isInsideFrame = false
    private var isEscaping = false

    public init() {}

    public mutating func append(_ data: Data) -> [Data] {
        var completedFrames: [Data] = []

        for byte in data {
            guard isInsideFrame else {
                if byte == NeoPacketCodec.startByte {
                    frame = Data([byte])
                    isInsideFrame = true
                    isEscaping = false
                }
                continue
            }

            if isEscaping {
                frame.append(byte ^ NeoPacketCodec.escapeMask)
                isEscaping = false
                continue
            }

            switch byte {
            case NeoPacketCodec.escapeByte:
                isEscaping = true
            case NeoPacketCodec.endByte:
                frame.append(byte)
                completedFrames.append(frame)
                reset()
            case NeoPacketCodec.startByte:
                frame = Data([byte])
                isEscaping = false
            default:
                frame.append(byte)
            }
        }

        return completedFrames
    }

    public mutating func reset() {
        frame.removeAll(keepingCapacity: true)
        isInsideFrame = false
        isEscaping = false
    }
}
