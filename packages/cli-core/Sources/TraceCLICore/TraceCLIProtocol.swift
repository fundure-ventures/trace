import Foundation

public struct TraceCLIRequest: Codable, Equatable {
    public let v: Int
    public let cmd: String
    public let format: TraceCLIFormat
    public let paths: [String]
    public let device: String?
    public let noRecording: Bool
    public let excludePIDs: [Int32]

    public init(
        action: TraceCLIAction,
        format: TraceCLIFormat = .imageDictation,
        noRecording: Bool = false,
        excludePIDs: [Int32] = []
    ) {
        v = 1
        self.format = format
        self.noRecording = noRecording
        self.excludePIDs = excludePIDs
        switch action {
        case .newTrace:
            cmd = "new"
            paths = []
            device = nil
        case .capture:
            cmd = "capture"
            paths = []
            device = nil
        case .devices:
            cmd = "devices"
            paths = []
            device = nil
        case .captureDevice(let name):
            cmd = "captureDevice"
            paths = []
            device = name
        case .copy:
            cmd = "copy"
            paths = []
            device = nil
        case .export(let path):
            cmd = "export"
            paths = [path]
            device = nil
        case .openDocument(let path):
            cmd = "openDocument"
            paths = [path]
            device = nil
        case .openImages(let paths):
            cmd = "openImages"
            self.paths = paths
            device = nil
        }
    }

    public var action: TraceCLIAction? {
        switch cmd {
        case "new": .newTrace
        case "capture": .capture
        case "devices": .devices
        case "captureDevice": device.map(TraceCLIAction.captureDevice)
        case "copy": .copy
        case "export": paths.first.map(TraceCLIAction.export)
        case "openDocument": paths.first.map(TraceCLIAction.openDocument)
        case "openImages": .openImages(paths)
        default: nil
        }
    }
}

public struct TraceCLIDevice: Codable, Equatable {
    public let name: String
    public let identifier: String
    public let unavailableReason: String?

    public init(name: String, identifier: String, unavailableReason: String?) {
        self.name = name
        self.identifier = identifier
        self.unavailableReason = unavailableReason
    }
}

public struct TraceCLIExport: Codable, Equatable {
    public let filename: String
    public let data: Data

    public init(filename: String, data: Data) {
        self.filename = filename
        self.data = data
    }
}

public struct TraceCLIReply: Codable, Equatable {
    public let v: Int
    public let ok: Bool
    public let code: String?
    public let message: String?
    public let devices: [TraceCLIDevice]?
    public let exports: [TraceCLIExport]?

    public init(
        ok: Bool,
        code: String? = nil,
        message: String? = nil,
        devices: [TraceCLIDevice]? = nil,
        exports: [TraceCLIExport]? = nil
    ) {
        v = 1
        self.ok = ok
        self.code = code
        self.message = message
        self.devices = devices
        self.exports = exports
    }
}

public final class TraceCLIReplyGate {
    private let lock = NSLock()
    private var hasReplied = false
    private let handleReply: (TraceCLIReply) -> Void

    public init(handleReply: @escaping (TraceCLIReply) -> Void) {
        self.handleReply = handleReply
    }

    public func send(_ reply: TraceCLIReply) {
        lock.lock()
        guard !hasReplied else {
            lock.unlock()
            return
        }
        hasReplied = true
        lock.unlock()
        handleReply(reply)
    }
}

public enum TraceCLIRefreshPolicy {
    public static func resolveAfterRefresh<Anchor, Value>(
        captureOrigin: () -> Anchor,
        refresh: (@escaping () -> Void) -> Void,
        resolve: @escaping () -> Value?,
        completion: @escaping (Anchor, Value?) -> Void
    ) {
        let origin = captureOrigin()
        refresh {
            completion(origin, resolve())
        }
    }
}

public enum TraceCLIExitCode: Int32 {
    case success = 0
    case usage = 64
    case file = 66
    case unavailable = 69
    case actionFailed = 70
    case busy = 75

    public static func forReply(_ reply: TraceCLIReply) -> Self {
        switch reply.code {
        case "invalidRequest", "unknownDevice": .usage
        case "noDocument": .actionFailed
        case "busy": .busy
        case "unavailable": .unavailable
        case "timeout": .actionFailed
        case "fileNotFound", "unreadable": .file
        default: reply.ok ? .success : .actionFailed
        }
    }
}
