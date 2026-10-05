import AppKit
import Darwin
import Foundation
import TraceCLICore

private let helpFooter =
    "Docs: https://github.com/fundure-ventures/trace/blob/main/CLI.md"
private let formats = TraceCLIFormat.allCases.map(\.rawValue)
private let usage = """
    usage: traceapp [--no-recording] [--] IMAGE...
           traceapp [--no-recording]
           traceapp capture [--no-recording]
           traceapp capture devices
           traceapp capture --device NAME
           traceapp copy [--format image-dictation|image|dictation|pdf]
           traceapp export DIR [--format image-dictation|image|dictation|pdf]
    """

private func printFormats() {
    print("Formats: \(formats.joined(separator: ", "))")
}

private func main() -> Int32 {
    let args = Array(CommandLine.arguments.dropFirst())
    if args.contains("--help") || args.contains("-h") || args == ["help"] {
        print(usage)
        print(helpFooter)
        return TraceCLIExitCode.success.rawValue
    }
    if let index = args.firstIndex(of: "--format"),
        index + 1 >= args.count || args[index + 1].hasPrefix("-")
    {
        printFormats()
        return TraceCLIExitCode.usage.rawValue
    }
    let missingDeviceValue: Bool
    if let index = args.firstIndex(of: "--device") {
        missingDeviceValue = index + 1 >= args.count || args[index + 1].hasPrefix("-")
    } else {
        missingDeviceValue = false
    }
    let parseArgs = missingDeviceValue ? ["capture", "devices"] : args
    let command: TraceCLICommand
    do {
        command = try TraceCLIArguments.parse(parseArgs)
    } catch TraceCLIParseError.incompleteOption(let option) {
        fputs("\(option) requires a value\n", stderr)
        if option == "--format" { printFormats() }
        return TraceCLIExitCode.usage.rawValue
    } catch TraceCLIParseError.invalidFormat(let format) {
        fputs("Unknown format: \(format)\n", stderr)
        printFormats()
        return TraceCLIExitCode.usage.rawValue
    } catch {
        fputs("\(error)\n\(usage)", stderr)
        return TraceCLIExitCode.usage.rawValue
    }

    let bundle: URL
    do {
        bundle = try traceBundle(for: URL(fileURLWithPath: CommandLine.arguments[0]))
    } catch {
        fputs("traceapp must be run from a Trace.app bundle\n", stderr)
        return TraceCLIExitCode.unavailable.rawValue
    }
    let bundleID = (Bundle(url: bundle)?.bundleIdentifier) ?? "com.traceproject.app"
    let socketURL = FileManager.default.homeDirectoryForCurrentUser
        .appendingPathComponent("Library/Application Support/Trace")
        .appendingPathComponent("\(bundleID).cli.sock")
    let action: TraceCLIAction
    switch command.action {
    case .openDocument(let path):
        action = .openDocument(absolutePath(path))
    case .openImages(let paths):
        action = .openImages(paths.map(absolutePath))
    case .export(let path):
        action = .export(absolutePath(path))
    default:
        action = command.action
    }
    let request = TraceCLIRequest(
        action: action,
        format: command.format,
        noRecording: command.noRecording,
        excludePIDs: terminalAncestorPIDs()
    )

    do {
        let descriptor: Int32
        do {
            descriptor = try connectWithRetry(to: socketURL, attempts: 1)
        } catch {
            try launch(bundle)
            descriptor = try connectWithRetry(to: socketURL, attempts: 50)
        }
        defer { Darwin.close(descriptor) }
        let response = try exchange(request, over: descriptor)
        if !response.ok {
            fputs((response.message ?? "Trace action failed") + "\n", stderr)
            if let devices = response.devices {
                printDevices(devices, to: .standardError)
            }
            return TraceCLIExitCode.forReply(response).rawValue
        }
        if let devices = response.devices {
            printDevices(devices)
        }
        if missingDeviceValue {
            fputs("capture --device requires a name\n", stderr)
            return TraceCLIExitCode.usage.rawValue
        }
        for item in response.exports ?? [] {
            let destination = URL(
                fileURLWithPath: item.filename,
                relativeTo: URL(fileURLWithPath: FileManager.default.currentDirectoryPath))
            do {
                try FileManager.default.createDirectory(
                    at: destination.deletingLastPathComponent(),
                    withIntermediateDirectories: true
                )
                try item.data.write(to: destination, options: .atomic)
                print(destination.standardizedFileURL.path)
            } catch {
                fputs("Could not write export file\n", stderr)
                return TraceCLIExitCode.actionFailed.rawValue
            }
        }
        if let message = response.message, !message.isEmpty { print(message) }
        return TraceCLIExitCode.success.rawValue
    } catch {
        fputs("Trace is unavailable: \(error.localizedDescription)\n", stderr)
        return TraceCLIExitCode.unavailable.rawValue
    }
}

private func printDevices(_ devices: [TraceCLIDevice], to handle: FileHandle = .standardOutput) {
    for device in devices {
        let state = device.unavailableReason.map { " (\($0))" } ?? ""
        handle.write(Data("\(device.name) [\(device.identifier)]\(state)\n".utf8))
    }
}

private func traceBundle(for executable: URL) throws -> URL {
    var location = executable.resolvingSymlinksInPath()
    while location.path != "/" {
        if location.pathExtension == "app",
            FileManager.default.fileExists(
                atPath: location.appendingPathComponent("Contents/Info.plist").path)
        {
            return location
        }
        location.deleteLastPathComponent()
    }
    throw CocoaError(.fileNoSuchFile)
}

private func launch(_ bundle: URL) throws {
    let semaphore = DispatchSemaphore(value: 0)
    var launchError: Error?
    NSWorkspace.shared.openApplication(at: bundle, configuration: NSWorkspace.OpenConfiguration()) {
        _, error in
        launchError = error
        semaphore.signal()
    }
    guard semaphore.wait(timeout: .now() + 5) == .success, launchError == nil else {
        throw launchError ?? CocoaError(.executableLoad)
    }
}

private func connect(to socketURL: URL) throws -> Int32 {
    var address = sockaddr_un()
    address.sun_family = sa_family_t(AF_UNIX)
    let pathBytes = Array(socketURL.path.utf8)
    guard pathBytes.count < MemoryLayout.size(ofValue: address.sun_path) else {
        throw POSIXError(.ENAMETOOLONG)
    }
    withUnsafeMutableBytes(of: &address.sun_path) { buffer in
        buffer.initializeMemory(as: CChar.self, repeating: 0)
        for (index, byte) in pathBytes.enumerated() { buffer[index] = byte }
    }
    let descriptor = Darwin.socket(AF_UNIX, SOCK_STREAM, 0)
    guard descriptor >= 0 else { throw POSIXError(.init(rawValue: errno) ?? .EIO) }
    let result = withUnsafePointer(to: &address) {
        $0.withMemoryRebound(to: sockaddr.self, capacity: 1) {
            Darwin.connect(descriptor, $0, socklen_t(MemoryLayout<sockaddr_un>.size))
        }
    }
    guard result == 0 else {
        let code = errno
        Darwin.close(descriptor)
        throw POSIXError(.init(rawValue: code) ?? .ECONNREFUSED)
    }
    return descriptor
}

private func connectWithRetry(to socketURL: URL, attempts: Int) throws -> Int32 {
    var lastError: Error = CocoaError(.executableLoad)
    for attempt in 0..<attempts {
        do { return try connect(to: socketURL) } catch {
            lastError = error
            if attempt + 1 < attempts {
                usleep(100_000)
            }
        }
    }
    throw lastError
}

private func exchange(_ request: TraceCLIRequest, over descriptor: Int32) throws -> TraceCLIReply {
    var data = try JSONEncoder().encode(request)
    data.append(0x0A)
    let written = data.withUnsafeBytes { Darwin.write(descriptor, $0.baseAddress, $0.count) }
    guard written == data.count else { throw POSIXError(.init(rawValue: errno) ?? .EIO) }
    var response = Data()
    var byte: UInt8 = 0
    while response.count < 4 * 1024 * 1024 {
        guard Darwin.read(descriptor, &byte, 1) == 1 else { break }
        if byte == 0x0A { break }
        response.append(byte)
    }
    guard let reply = try? JSONDecoder().decode(TraceCLIReply.self, from: response), reply.v == 1
    else {
        throw CocoaError(.fileReadCorruptFile)
    }
    return reply
}

private func terminalAncestorPIDs() -> [Int32] {
    var pid = getppid()
    for _ in 0..<32 {
        guard pid > 1 else { break }
        if let app = NSRunningApplication(processIdentifier: pid),
            app.bundleIdentifier != Bundle.main.bundleIdentifier
        {
            return [pid]
        }
        var info = proc_bsdinfo()
        let size = proc_pidinfo(
            pid,
            PROC_PIDTBSDINFO,
            0,
            &info,
            Int32(MemoryLayout<proc_bsdinfo>.size)
        )
        guard size == MemoryLayout<proc_bsdinfo>.size,
            info.pbi_ppid > 1,
            info.pbi_ppid != pid
        else { break }
        pid = Int32(info.pbi_ppid)
    }
    return []
}

private func absolutePath(_ path: String) -> String {
    URL(
        fileURLWithPath: path,
        relativeTo: URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
    )
    .standardizedFileURL.path
}

exit(main())
