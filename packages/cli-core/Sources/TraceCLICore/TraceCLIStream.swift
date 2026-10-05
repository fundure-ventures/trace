import Foundation

public enum TraceCLIStreamError: Error, Equatable {
    case endOfStream
    case lineTooLong
    case readFailed
    case writeFailed
}

public enum TraceCLIStream {
    public static let maximumRequestBytes = 4 * 1024 * 1024
    public static let maximumReplyBytes = 128 * 1024 * 1024

    public static func readLine(
        maximumBytes: Int,
        read: (UnsafeMutableRawBufferPointer) -> Int,
        isInterrupted: () -> Bool
    ) throws -> Data {
        precondition(maximumBytes >= 0)
        let chunkSize = max(1, min(16 * 1024, maximumBytes + 1))
        var chunk = [UInt8](repeating: 0, count: chunkSize)
        var line = Data()
        while true {
            let count = chunk.withUnsafeMutableBytes(read)
            guard count >= 0 else {
                if isInterrupted() { continue }
                throw TraceCLIStreamError.readFailed
            }
            guard count > 0 else {
                throw TraceCLIStreamError.endOfStream
            }
            let bytes = chunk.prefix(count)
            if let newline = bytes.firstIndex(of: 0x0A) {
                guard line.count + newline <= maximumBytes else {
                    throw TraceCLIStreamError.lineTooLong
                }
                line.append(contentsOf: bytes[..<newline])
                return line
            }
            guard line.count + count <= maximumBytes else {
                throw TraceCLIStreamError.lineTooLong
            }
            line.append(contentsOf: bytes)
        }
    }

    public static func writeAll(
        _ data: Data,
        write: (UnsafeRawBufferPointer) -> Int,
        isInterrupted: () -> Bool
    ) throws {
        try data.withUnsafeBytes { bytes in
            guard let baseAddress = bytes.baseAddress else { return }
            var offset = 0
            while offset < bytes.count {
                let remaining = UnsafeRawBufferPointer(
                    start: baseAddress.advanced(by: offset),
                    count: bytes.count - offset
                )
                let count = write(remaining)
                guard count >= 0 else {
                    if isInterrupted() { continue }
                    throw TraceCLIStreamError.writeFailed
                }
                guard count > 0 else {
                    throw TraceCLIStreamError.writeFailed
                }
                offset += count
            }
        }
    }
}
