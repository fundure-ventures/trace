import Darwin
import Foundation
import TraceLogging

private struct TestFailure: Error {
    let message: String
}

private func expect(_ condition: @autoclosure () throws -> Bool, _ message: String) throws {
    if try condition() == false { throw TestFailure(message: message) }
}

private func withDirectory(_ body: (URL) throws -> Void) throws {
    let directory = FileManager.default.temporaryDirectory
        .appendingPathComponent("trace-logging-tests-\(UUID().uuidString)")
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    defer {
        do { try FileManager.default.removeItem(at: directory) }
        catch { fputs("test cleanup failed: \(error)\n", stderr) }
    }
    try body(directory)
}

private func logFiles(_ directory: URL) throws -> [URL] {
    try FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil)
        .filter { $0.pathExtension == "jsonl" }
}

private func rows(_ directory: URL) throws -> [[String: Any]] {
    try logFiles(directory).flatMap { file in
        try String(contentsOf: file, encoding: .utf8).split(separator: "\n").map {
            guard let row = try JSONSerialization.jsonObject(with: Data($0.utf8)) as? [String: Any]
            else { throw TestFailure(message: "log entry must be a JSON object") }
            return row
        }
    }
}

do {
    try expect(
        TraceLogger.debugPersistence(environment: [:], savedPreference: true),
        "saved debug persistence must survive relaunch"
    )
    try expect(
        !TraceLogger.debugPersistence(
            environment: ["TRACE_PERSIST_DEBUG_LOGS": "0"], savedPreference: true
        ),
        "environment must override the saved preference"
    )
    try expect(
        TraceLogger.debugPersistence(
            environment: ["TRACE_PERSIST_DEBUG_LOGS": "1"], savedPreference: false
        ),
        "the flag must enable debug persistence"
    )
    try expect(
        !TraceLogger.debugPersistence(environment: [:], savedPreference: false),
        "debug persistence must be opt-in"
    )

    try withDirectory { directory in
        let logger = TraceLogger(directory: directory, isDebugBuild: true)
        logger.record(.debug, category: .capture, "Debug omitted")
        logger.record(.notice, category: .lifecycle, "App started")
        let error = NSError(
            domain: NSURLErrorDomain, code: -1009,
            userInfo: [
                NSLocalizedDescriptionKey: "secret API key sk-test /Users/private drawing transcript",
                NSUnderlyingErrorKey: NSError(domain: "secret-domain", code: 123),
            ]
        )
        logger.record(.error, category: .capture, "Capture failed", error: error)
        try logger.flush()
        let entries = try rows(directory)
        try expect(entries.count == 2, "Debug builds must retain notices/errors, not debug by default")
        let failure = entries.first { $0["level"] as? String == "error" }
        try expect(failure?["message"] as? String == "Capture failed", "error operation must be retained")
        let diagnostic = failure?["error"] as? [String: Any]
        try expect(diagnostic?["code"] as? Int == -1009, "NSError code must be retained")
        try expect(diagnostic?["domain"] as? String == NSURLErrorDomain, "known error domain must be retained")
        try expect(failure?["session"] as? String != nil, "entries need a session ID")
        try expect(failure?["version"] as? String != nil, "entries need app version")
        try expect(
            failure?["file"] as? String == "TraceLoggingTests/main.swift",
            "source must identify the file without exposing an absolute path"
        )
        let timestampFormatter = ISO8601DateFormatter()
        timestampFormatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        try expect(
            (failure?["timestamp"] as? String).flatMap { timestampFormatter.date(from: $0) } != nil,
            "timestamps must be valid ISO 8601 with fractional seconds"
        )
        try expect(failure?["function"] as? String != nil, "entries need their source operation")
        let text = try logFiles(directory).map { try String(contentsOf: $0) }.joined()
        try expect(!text.contains("secret") && !text.contains("/Users/private"), "error payload must not leak")
        let attributes = try FileManager.default.attributesOfItem(atPath: logFiles(directory)[0].path)
        try expect(attributes[.posixPermissions] as? Int == 0o600, "logs must be owner-only")
        let directoryAttributes = try FileManager.default.attributesOfItem(atPath: directory.path)
        try expect(directoryAttributes[.posixPermissions] as? Int == 0o700, "log directory must be owner-only")
        try expect(
            try directory.resourceValues(forKeys: [.isExcludedFromBackupKey]).isExcludedFromBackup == true,
            "logs must be excluded from backups"
        )

        logger.setPersistDebugLogs(true)
        logger.record(.debug, category: .canvas, "Canvas snapshot requested")
        try logger.flush()
        try expect(try rows(directory).contains { $0["level"] as? String == "debug" }, "toggle must persist debug")
        logger.setPersistDebugLogs(false)
        logger.record(.debug, category: .canvas, "Debug disabled")
        logger.record(.error, category: .storage, "Custom failure", error: NSError(domain: "secret-domain", code: 7))
        try logger.flush()
        let finalEntries = try rows(directory)
        try expect(!finalEntries.contains { $0["message"] as? String == "Debug disabled" }, "toggle must stop debug")
        let custom = finalEntries.first { $0["message"] as? String == "Custom failure" }
        try expect(
            (custom?["error"] as? [String: Any])?["domain"] as? String == "custom",
            "untrusted domains must be redacted"
        )
    }

    try withDirectory { directory in
        let logger = TraceLogger(directory: directory, isDebugBuild: false)
        logger.record(.error, category: .storage, "Release error")
        try logger.flush()
        try expect(try logFiles(directory).isEmpty, "Release must not create files without opt-in")
        logger.setPersistDebugLogs(true)
        logger.record(.debug, category: .capture, "Release diagnostic")
        try logger.flush()
        try expect(try rows(directory).count == 1, "opt-in must work in Release too")
    }

    try withDirectory { directory in
        let stale = directory.appendingPathComponent("trace.2.jsonl")
        try Data("stale\n".utf8).write(to: stale)
        try FileManager.default.setAttributes(
            [.modificationDate: Date(timeIntervalSinceNow: -8 * 24 * 60 * 60)], ofItemAtPath: stale.path
        )
        let unrelated = directory.appendingPathComponent("keep.txt")
        try Data("keep".utf8).write(to: unrelated)
        let logger = TraceLogger(
            directory: directory, isDebugBuild: true, persistDebugLogs: true,
            maximumFileBytes: 1_024, maximumFiles: 5
        )
        logger.record(.notice, category: .lifecycle, "Retention check")
        try logger.flush()
        try expect(!FileManager.default.fileExists(atPath: stale.path), "age retention must work without rotation")
        for _ in 0..<60 {
            logger.record(.debug, category: .canvas, "Canvas synchronization completed")
        }
        try logger.flush()
        let files = try logFiles(directory)
        try expect(files.count == 5, "rotation must retain exactly five files when full")
        for file in files {
            let size = try file.resourceValues(forKeys: [.fileSizeKey]).fileSize ?? 0
            try expect(size <= 1_024, "every file must remain within the byte limit")
            try expect(!(try String(contentsOf: file)).contains("stale"), "expired logs must be removed")
        }
        try expect(FileManager.default.fileExists(atPath: unrelated.path), "cleanup must preserve unrelated files")
        try expect(!(try rows(directory)).isEmpty, "rotated files must contain valid JSON entries")
    }

    try withDirectory { directory in
        let logger = TraceLogger(directory: directory, isDebugBuild: true, persistDebugLogs: true)
        DispatchQueue.concurrentPerform(iterations: 100) { _ in
            logger.record(.debug, category: .canvas, "Concurrent event")
        }
        try logger.flush()
        try expect(try rows(directory).count == 100, "concurrent writes must not corrupt or lose entries")
    }

    try withDirectory { directory in
        let first = TraceLogger(
            directory: directory, isDebugBuild: true,
            maximumFileBytes: 1_024, maximumFiles: 5
        )
        let second = TraceLogger(
            directory: directory, isDebugBuild: true,
            maximumFileBytes: 1_024, maximumFiles: 5
        )
        DispatchQueue.concurrentPerform(iterations: 100) { index in
            (index % 2 == 0 ? first : second).record(.error, category: .storage, "Shared directory event")
        }
        let firstResult = Result { try first.flush() }
        let secondResult = Result { try second.flush() }
        try firstResult.get()
        try secondResult.get()
        let entries = try rows(directory)
        try expect(!entries.isEmpty, "multiple writers must preserve valid JSON during rotation")
        try expect(try logFiles(directory).count == 5, "multiple writers must honor retention")
    }

    try withDirectory { directory in
        let file = directory.appendingPathComponent("not-a-directory")
        try Data().write(to: file)
        let logger = TraceLogger(directory: file, isDebugBuild: true)
        logger.record(.error, category: .storage, "Failure still reaches system logging")
        do {
            try logger.flush()
            throw TestFailure(message: "disk write failures must be surfaced")
        } catch is TestFailure {
            throw TestFailure(message: "disk write failures must be surfaced")
        } catch {}
    }
    print("TraceLoggingTests passed")
} catch {
    fputs("TraceLoggingTests failed: \(error)\n", stderr)
    exit(1)
}
