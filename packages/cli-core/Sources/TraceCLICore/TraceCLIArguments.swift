import Foundation

public enum TraceCLIFormat: String, Codable, CaseIterable {
    case imageDictation = "image-dictation"
    case image
    case dictation
    case pdf
}

public enum TraceCLIAction: Equatable {
    case newTrace
    case capture
    case devices
    case captureDevice(String)
    case copy
    case export(String)
    case openDocument(String)
    case openImages([String])
}

public struct TraceCLICommand: Equatable {
    public let action: TraceCLIAction
    public let format: TraceCLIFormat
    public let noRecording: Bool

    public init(
        action: TraceCLIAction,
        format: TraceCLIFormat = .imageDictation,
        noRecording: Bool = false
    ) {
        self.action = action
        self.format = format
        self.noRecording = noRecording
    }
}

public enum TraceCLIParseError: Error, Equatable {
    case incompleteOption(String)
    case invalidOption(String)
    case invalidArguments(String)
    case invalidFormat(String)
}

public enum TraceCLIArguments {
    private static let imageExtensions: Set<String> = [
        "png", "jpg", "jpeg", "tif", "tiff", "gif", "heic", "webp", "bmp",
    ]

    public static func parse(_ arguments: [String]) throws -> TraceCLICommand {
        var args = arguments
        var noRecording = false
        args.removeAll { argument in
            if argument == "--no-recording" {
                noRecording = true
                return true
            }
            return false
        }
        guard let first = args.first else {
            return TraceCLICommand(action: .newTrace, noRecording: noRecording)
        }
        switch first {
        case "capture":
            return try parseCapture(Array(args.dropFirst()), noRecording: noRecording)
        case "copy":
            return try parseFormatCommand(
                Array(args.dropFirst()), action: .copy, noRecording: noRecording
            )
        case "export":
            guard args.count >= 2 else {
                throw TraceCLIParseError.invalidArguments("export requires a destination")
            }
            return try parseFormatCommand(
                Array(args.dropFirst(2)),
                action: .export(args[1]),
                noRecording: noRecording
            )
        case "--help", "-h", "help":
            throw TraceCLIParseError.invalidArguments("help")
        default:
            return try parseFiles(args, noRecording: noRecording)
        }
    }

    private static func parseCapture(
        _ arguments: [String],
        noRecording: Bool
    ) throws -> TraceCLICommand {
        if arguments.isEmpty {
            return TraceCLICommand(action: .capture, noRecording: noRecording)
        }
        if arguments == ["devices"] {
            return TraceCLICommand(action: .devices, noRecording: noRecording)
        }
        guard arguments.count == 2, arguments[0] == "--device" else {
            if arguments.contains("--device") {
                throw TraceCLIParseError.incompleteOption("--device")
            }
            throw TraceCLIParseError.invalidArguments("capture accepts --device NAME or devices")
        }
        guard !arguments[1].hasPrefix("-") else {
            throw TraceCLIParseError.incompleteOption("--device")
        }
        return TraceCLICommand(action: .captureDevice(arguments[1]), noRecording: noRecording)
    }

    private static func parseFormatCommand(
        _ arguments: [String],
        action: TraceCLIAction,
        noRecording: Bool
    ) throws -> TraceCLICommand {
        guard !arguments.isEmpty else {
            return TraceCLICommand(action: action, noRecording: noRecording)
        }
        guard arguments.count == 2, arguments[0] == "--format" else {
            if arguments.contains("--format") {
                throw TraceCLIParseError.incompleteOption("--format")
            }
            throw TraceCLIParseError.invalidArguments("unexpected argument")
        }
        guard let format = TraceCLIFormat(rawValue: arguments[1]) else {
            throw TraceCLIParseError.invalidFormat(arguments[1])
        }
        return TraceCLICommand(action: action, format: format, noRecording: noRecording)
    }

    private static func parseFiles(
        _ arguments: [String],
        noRecording: Bool
    ) throws -> TraceCLICommand {
        let paths: [String]
        if arguments.first == "--" {
            paths = Array(arguments.dropFirst())
        } else {
            paths = arguments
        }
        guard !paths.isEmpty, !paths.contains(where: { $0.hasPrefix("-") }) else {
            throw TraceCLIParseError.invalidArguments("expected image or .traceboard file paths")
        }
        let boards = paths.filter {
            URL(fileURLWithPath: $0).pathExtension.lowercased() == "traceboard"
        }
        if boards.count == 1 && paths.count == 1 {
            return TraceCLICommand(action: .openDocument(paths[0]), noRecording: noRecording)
        }
        guard boards.isEmpty,
            paths.allSatisfy({
                let ext = URL(fileURLWithPath: $0).pathExtension.lowercased()
                return ext.isEmpty || imageExtensions.contains(ext)
            })
        else {
            throw TraceCLIParseError.invalidArguments("use one .traceboard or image files only")
        }
        return TraceCLICommand(action: .openImages(paths), noRecording: noRecording)
    }
}
