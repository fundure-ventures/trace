import Darwin
import Foundation

enum TraceCLIInstallationState: Equatable {
    case notInstalled
    case installed
    case pointsElsewhere
    case broken
}

enum TraceCLIInstallation {
    static var directory: URL {
        #if DEBUG
            if let path = ProcessInfo.processInfo.environment["TRACE_CLI_INSTALL_DIRECTORY"] {
                return URL(fileURLWithPath: path)
            }
        #endif
        return URL(fileURLWithPath: "/usr/local/bin", isDirectory: true)
    }

    static func helperURL(for bundleURL: URL) -> URL {
        bundleURL.appendingPathComponent("Contents/Helpers/traceapp")
    }

    static func linkURL(in directory: URL) -> URL {
        directory.appendingPathComponent("traceapp")
    }

    static func state(directory: URL, helper: URL) -> TraceCLIInstallationState {
        let link = linkURL(in: directory)
        var metadata = stat()
        guard lstat(link.path, &metadata) == 0,
            (metadata.st_mode & S_IFMT) == S_IFLNK
        else {
            return FileManager.default.fileExists(atPath: link.path)
                ? .pointsElsewhere
                : .notInstalled
        }
        guard
            let destination = try? FileManager.default.destinationOfSymbolicLink(atPath: link.path)
        else {
            return .broken
        }
        let target = URL(fileURLWithPath: destination, relativeTo: directory)
            .standardizedFileURL
        guard FileManager.default.isExecutableFile(atPath: target.path) else {
            return .broken
        }
        return target == helper.standardizedFileURL ? .installed : .pointsElsewhere
    }

    #if DEBUG
        static func runProbe() throws {
            let root = FileManager.default.temporaryDirectory
                .appendingPathComponent("trace-cli-install-probe-\(UUID().uuidString)")
            let directory = root.appendingPathComponent("bin")
            let helper = root.appendingPathComponent("Trace Debug.app/Contents/Helpers/traceapp")
            defer { try? FileManager.default.removeItem(at: root) }
            try FileManager.default.createDirectory(
                at: helper.deletingLastPathComponent(),
                withIntermediateDirectories: true
            )
            try FileManager.default.createDirectory(
                at: directory,
                withIntermediateDirectories: true
            )
            try Data("#!/bin/sh\nexit 0\n".utf8).write(to: helper)
            try FileManager.default.setAttributes(
                [.posixPermissions: 0o755],
                ofItemAtPath: helper.path
            )
            try perform(
                install: true,
                directory: directory,
                helper: helper,
                requiresAuthorization: false
            )
            guard state(directory: directory, helper: helper) == .installed else {
                throw CocoaError(.fileWriteUnknown)
            }
            try perform(
                install: false,
                directory: directory,
                helper: helper,
                requiresAuthorization: false
            )
            guard state(directory: directory, helper: helper) == .notInstalled else {
                throw CocoaError(.fileWriteUnknown)
            }
        }
    #endif

    static func perform(
        install: Bool,
        directory: URL,
        helper: URL,
        requiresAuthorization: Bool = true
    ) throws {
        if !install {
            guard state(directory: directory, helper: helper) == .installed else {
                throw CocoaError(.fileWriteNoPermission)
            }
        }
        let destination = linkURL(in: directory)
        let command: String
        if install {
            command =
                "mkdir -p \(shellQuote(directory.path)) && ln -sfn \(shellQuote(helper.path)) \(shellQuote(destination.path))"
        } else {
            command = "rm \(shellQuote(destination.path))"
        }
        if requiresAuthorization {
            let escaped =
                command
                .replacingOccurrences(of: "\\", with: "\\\\")
                .replacingOccurrences(of: "\"", with: "\\\"")
            try run(
                executable: "/usr/bin/osascript",
                arguments: ["-e", "do shell script \"\(escaped)\" with administrator privileges"]
            )
        } else {
            try run(executable: "/bin/sh", arguments: ["-c", command])
        }
    }

    private static func shellQuote(_ value: String) -> String {
        "'" + value.replacingOccurrences(of: "'", with: "'\\''") + "'"
    }

    private static func run(executable: String, arguments: [String]) throws {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: executable)
        process.arguments = arguments
        let errors = Pipe()
        process.standardError = errors
        try process.run()
        process.waitUntilExit()
        guard process.terminationStatus == 0 else {
            throw NSError(
                domain: "TraceCLIInstallation",
                code: Int(process.terminationStatus),
                userInfo: [NSLocalizedDescriptionKey: "The command-line tool could not be updated."]
            )
        }
    }
}
