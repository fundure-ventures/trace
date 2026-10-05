import Foundation
import OSLog
import Darwin

public enum TraceLogLevel: String, Codable {
    case debug, notice, error, fault

    fileprivate var osLogType: OSLogType {
        switch self {
        case .debug: return .debug
        case .notice: return .default
        case .error: return .error
        case .fault: return .fault
        }
    }
}

public enum TraceLogCategory: String, Codable {
    case lifecycle, capture, storage, canvas, dictation, input, clipboard
}

private struct LogError: Codable {
    let domain: String
    let code: Int
    let type: String

    init(_ error: Error) {
        let nsError = error as NSError
        let publicDomains = [
            NSCocoaErrorDomain, NSURLErrorDomain, NSPOSIXErrorDomain,
            NSOSStatusErrorDomain, "WKErrorDomain",
        ]
        domain = publicDomains.contains(nsError.domain) ? nsError.domain : "custom"
        code = nsError.code
        type = String(reflecting: Swift.type(of: error))
    }
}

private struct LogEntry: Codable {
    let timestamp: String
    let session: UUID
    let version: String
    let build: String
    let level: TraceLogLevel
    let category: TraceLogCategory
    let message: String
    let file: String
    let function: String
    let line: UInt
    let error: LogError?
}

/// Messages are static operation labels; runtime content and error descriptions never enter the log.
public final class TraceLogger: @unchecked Sendable {
    public static let debugPreferenceKey = "TracePersistDebugLogs"
    public static let shared = TraceLogger(
        directory: defaultDirectory,
        isDebugBuild: isDebugBuild,
        persistDebugLogs: debugPersistence(
            environment: ProcessInfo.processInfo.environment,
            savedPreference: UserDefaults.standard.bool(forKey: debugPreferenceKey)
        )
    )

    public static var isDebugBuild: Bool {
#if DEBUG
        true
#else
        false
#endif
    }

    public static var defaultDirectory: URL {
        FileManager.default.urls(for: .libraryDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("Logs", isDirectory: true)
            .appendingPathComponent(isDebugBuild ? "Trace Debug" : "Trace", isDirectory: true)
    }

    public static func debugPersistence(
        environment: [String: String], savedPreference: Bool
    ) -> Bool {
        switch environment["TRACE_PERSIST_DEBUG_LOGS"] {
        case "1": return true
        case "0": return false
        default: return savedPreference
        }
    }

    public let directory: URL
    private let queue = DispatchQueue(label: "Trace.local-logs", qos: .utility)
    private let debugBuild: Bool
    private var debugPersistenceEnabled: Bool
    private let maximumFileBytes: Int
    private let maximumFiles: Int
    private let session = UUID()
    private let version: String
    private let build: String
    private let subsystem: String
    private var writeError: Error?
    private let encoder = JSONEncoder()
    private let formatter = ISO8601DateFormatter()

    public init(
        directory: URL,
        isDebugBuild: Bool,
        persistDebugLogs: Bool = false,
        maximumFileBytes: Int = 2 * 1_024 * 1_024,
        maximumFiles: Int = 5
    ) {
        precondition(maximumFileBytes >= 1_024 && maximumFiles >= 1)
        self.directory = directory
        debugBuild = isDebugBuild
        debugPersistenceEnabled = persistDebugLogs
        self.maximumFileBytes = maximumFileBytes
        self.maximumFiles = maximumFiles
        version = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "unknown"
        build = Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "unknown"
        subsystem = Bundle.main.bundleIdentifier ?? "com.trace.app"
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
    }

    public var persistDebugLogs: Bool {
        queue.sync { debugPersistenceEnabled }
    }

    public func setPersistDebugLogs(_ enabled: Bool) {
        queue.sync { debugPersistenceEnabled = enabled }
    }

    public func record(
        _ level: TraceLogLevel,
        category: TraceLogCategory,
        _ message: StaticString,
        error: Error? = nil,
        file: StaticString = #fileID,
        function: StaticString = #function,
        line: UInt = #line
    ) {
        let label = message.description
        let diagnostic = error.map(LogError.init)
        let logger = Logger(subsystem: subsystem, category: category.rawValue)
        if let diagnostic {
            logger.log(
                level: level.osLogType,
                "\(label, privacy: .public) type=\(diagnostic.type, privacy: .public) domain=\(diagnostic.domain, privacy: .public) code=\(diagnostic.code)"
            )
        } else {
            logger.log(level: level.osLogType, "\(label, privacy: .public)")
        }
        let now = Date()
        queue.async { [self] in
            guard debugBuild || debugPersistenceEnabled,
                  level != .debug || debugPersistenceEnabled
            else { return }
            let entry = LogEntry(
                timestamp: formatter.string(from: now),
                session: session, version: version, build: build, level: level,
                category: category, message: label, file: file.description,
                function: function.description,
                line: line, error: diagnostic
            )
            do {
                var data = try encoder.encode(entry)
                data.append(0x0A)
                try append(data, at: now)
            } catch {
                writeError = error
                let failure = LogError(error)
                Logger(subsystem: subsystem, category: "logging").fault(
                    "Local log write failed domain=\(failure.domain, privacy: .public) code=\(failure.code)"
                )
                fputs("Trace local log write failed: \(failure.domain) (\(failure.code))\n", stderr)
            }
        }
    }

    /// Drains queued writes on normal termination; reports any file-writing failure.
    public func flush() throws {
        try queue.sync {
            if let writeError { throw writeError }
        }
    }

    public func prepareDirectory() throws {
        try queue.sync { try createDirectory() }
    }

    private func file(_ index: Int) -> URL {
        directory.appendingPathComponent(index == 0 ? "trace.jsonl" : "trace.\(index).jsonl")
    }

    private func createDirectory() throws {
        try FileManager.default.createDirectory(
            at: directory, withIntermediateDirectories: true,
            attributes: [.posixPermissions: 0o700]
        )
        try FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: directory.path)
        var url = directory
        var values = URLResourceValues()
        values.isExcludedFromBackup = true
        try url.setResourceValues(values)
    }

    private func append(_ data: Data, at now: Date) throws {
        guard data.count <= maximumFileBytes else {
            throw CocoaError(.fileWriteOutOfSpace)
        }
        let manager = FileManager.default
        try createDirectory()
        // A second launch may log before forwarding to the existing app instance.
        let lock = open(directory.appendingPathComponent(".writer.lock").path, O_CREAT | O_WRONLY | O_CLOEXEC, 0o600)
        guard lock >= 0 else { throw POSIXError(POSIXErrorCode(rawValue: errno) ?? .EIO) }
        defer {
            if close(lock) != 0 {
                Logger(subsystem: subsystem, category: "logging").fault("Local log lock close failed")
                fputs("Trace local log lock close failed.\n", stderr)
            }
        }
        guard flock(lock, LOCK_EX) == 0 else {
            throw POSIXError(POSIXErrorCode(rawValue: errno) ?? .EIO)
        }
        for index in 0..<maximumFiles {
            let url = file(index)
            if manager.fileExists(atPath: url.path) {
                let modified = try url.resourceValues(forKeys: [.contentModificationDateKey])
                    .contentModificationDate
                if let modified, now.timeIntervalSince(modified) >= 7 * 24 * 60 * 60 {
                    try manager.removeItem(at: url)
                }
            }
        }
        let current = file(0)
        if manager.fileExists(atPath: current.path) {
            let size = try current.resourceValues(forKeys: [.fileSizeKey]).fileSize ?? 0
            if size + data.count > maximumFileBytes {
                let oldest = file(maximumFiles - 1)
                if manager.fileExists(atPath: oldest.path) { try manager.removeItem(at: oldest) }
                if maximumFiles > 1 {
                    for index in stride(from: maximumFiles - 2, through: 0, by: -1) {
                        let source = file(index)
                        if manager.fileExists(atPath: source.path) {
                            try manager.moveItem(at: source, to: file(index + 1))
                        }
                    }
                }
            }
        }
        if !manager.fileExists(atPath: current.path) {
            guard manager.createFile(
                atPath: current.path, contents: nil, attributes: [.posixPermissions: 0o600]
            ) else { throw CocoaError(.fileWriteUnknown) }
        }
        let handle = try FileHandle(forWritingTo: current)
        do {
            try handle.seekToEnd()
            try handle.write(contentsOf: data)
            try handle.close()
        } catch {
            do { try handle.close() }
            catch {
                Logger(subsystem: subsystem, category: "logging").error("Local log file close failed")
            }
            throw error
        }
    }
}
