import AppKit
import Darwin
import Foundation
import TraceCLICore

private let cliExchangeTimeout: TimeInterval = 125

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
    let optionArgs = Array(args.prefix(while: { $0 != "--" }))
    if optionArgs.contains("--help") || optionArgs.contains("-h") || optionArgs == ["help"] {
        print(usage)
        print(helpFooter)
        return TraceCLIExitCode.success.rawValue
    }
    var missingDeviceValue = false
    let command: TraceCLICommand
    do {
        command = try TraceCLIArguments.parse(args)
    } catch TraceCLIParseError.incompleteOption(let option) {
        if option == "--device" {
            missingDeviceValue = true
            do {
                command = try TraceCLIArguments.parse(["capture", "devices"])
            } catch {
                fputs("Could not list capture devices\n", stderr)
                return TraceCLIExitCode.actionFailed.rawValue
            }
        } else {
            fputs("\(option) requires a value\n", stderr)
            if option == "--format" { printFormats() }
            return TraceCLIExitCode.usage.rawValue
        }
    } catch TraceCLIParseError.invalidFormat(let format) {
        fputs("Unknown format: \(format)\n", stderr)
        printFormats()
        return TraceCLIExitCode.usage.rawValue
    } catch TraceCLIParseError.invalidOption(let option) {
        fputs("Unknown option: \(option)\n\(usage)", stderr)
        return TraceCLIExitCode.usage.rawValue
    } catch {
        fputs("\(error)\n\(usage)", stderr)
        return TraceCLIExitCode.usage.rawValue
    }

    let bundle: URL
    do {
        bundle = try traceBundle(for: currentExecutableURL())
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
            descriptor = try connect(to: socketURL)
        } catch {
            let deadline = DispatchTime.now().uptimeNanoseconds + 25_000_000_000
            try launch(bundle, deadline: deadline)
            descriptor = try connectWithRetry(to: socketURL, deadline: deadline)
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

private func currentExecutableURL() throws -> URL {
    var capacity: UInt32 = 0
    _ = _NSGetExecutablePath(nil, &capacity)
    guard capacity > 0 else { throw CocoaError(.executableLoad) }
    var buffer = [CChar](repeating: 0, count: Int(capacity))
    let result = buffer.withUnsafeMutableBufferPointer {
        _NSGetExecutablePath($0.baseAddress, &capacity)
    }
    guard result == 0 else { throw CocoaError(.executableLoad) }
    return URL(fileURLWithPath: String(cString: buffer))
}

private func launch(_ bundle: URL, deadline: UInt64) throws {
    let semaphore = DispatchSemaphore(value: 0)
    var launchError: Error?
    NSWorkspace.shared.openApplication(at: bundle, configuration: NSWorkspace.OpenConfiguration()) {
        _, error in
        launchError = error
        semaphore.signal()
    }
    let now = DispatchTime.now().uptimeNanoseconds
    guard now < deadline,
          semaphore.wait(timeout: .now() + .nanoseconds(Int(deadline - now))) == .success,
          launchError == nil
    else {
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
    var noSignal: Int32 = 1
    guard setsockopt(
        descriptor,
        SOL_SOCKET,
        SO_NOSIGPIPE,
        &noSignal,
        socklen_t(MemoryLayout<Int32>.size)
    ) == 0 else {
        let code = errno
        Darwin.close(descriptor)
        throw POSIXError(.init(rawValue: code) ?? .EIO)
    }
    var socketTimeout = timeval(tv_sec: 15, tv_usec: 0)
    for option in [SO_RCVTIMEO, SO_SNDTIMEO] {
        guard setsockopt(
            descriptor,
            SOL_SOCKET,
            option,
            &socketTimeout,
            socklen_t(MemoryLayout<timeval>.size)
        ) == 0 else {
            let code = errno
            Darwin.close(descriptor)
            throw POSIXError(.init(rawValue: code) ?? .EIO)
        }
    }
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

private func connectWithRetry(to socketURL: URL, deadline: UInt64) throws -> Int32 {
    var lastError: Error = CocoaError(.executableLoad)
    while DispatchTime.now().uptimeNanoseconds < deadline {
        do { return try connect(to: socketURL) } catch {
            lastError = error
            Thread.sleep(forTimeInterval: 0.1)
        }
    }
    throw lastError
}

private func exchange(_ request: TraceCLIRequest, over descriptor: Int32) throws -> TraceCLIReply {
    var data = try JSONEncoder().encode(request)
    guard data.count <= TraceCLIStream.maximumRequestBytes else {
        throw TraceCLIStreamError.lineTooLong
    }
    data.append(0x0A)
    let deadline = DispatchTime.now().uptimeNanoseconds
        + UInt64(cliExchangeTimeout * 1_000_000_000)
    var writeInterrupted = false
    var writeReadinessError: Error?
    do {
        try TraceCLIStream.writeAll(
            data,
            write: { buffer in
                do {
                    try waitForSocket(
                        descriptor,
                        events: Int16(POLLOUT),
                        deadline: deadline
                    )
                } catch {
                    writeReadinessError = error
                    return -1
                }
                let count = Darwin.write(descriptor, buffer.baseAddress, buffer.count)
                writeInterrupted = count < 0 && errno == EINTR
                return count
            },
            isInterrupted: { writeInterrupted }
        )
    } catch {
        throw writeReadinessError ?? error
    }

    var readInterrupted = false
    var readReadinessError: Error?
    let response: Data
    do {
        response = try TraceCLIStream.readLine(
            maximumBytes: TraceCLIStream.maximumReplyBytes,
            read: { buffer in
                do {
                    try waitForSocket(
                        descriptor,
                        events: Int16(POLLIN),
                        deadline: deadline
                    )
                } catch {
                    readReadinessError = error
                    return -1
                }
                let count = Darwin.read(descriptor, buffer.baseAddress, buffer.count)
                readInterrupted = count < 0 && errno == EINTR
                return count
            },
            isInterrupted: { readInterrupted }
        )
    } catch {
        throw readReadinessError ?? error
    }
    guard let reply = try? JSONDecoder().decode(TraceCLIReply.self, from: response), reply.v == 1
    else {
        throw CocoaError(.fileReadCorruptFile)
    }
    return reply
}

private func waitForSocket(_ descriptor: Int32, events: Int16, deadline: UInt64) throws {
    while true {
        let now = DispatchTime.now().uptimeNanoseconds
        guard now < deadline else { throw POSIXError(.ETIMEDOUT) }
        let remaining = deadline - now
        let milliseconds = Int32(
            min(UInt64(Int32.max), max(1, (remaining + 999_999) / 1_000_000))
        )
        var pollDescriptor = pollfd(fd: descriptor, events: events, revents: 0)
        let result = Darwin.poll(&pollDescriptor, 1, milliseconds)
        if result > 0 {
            if pollDescriptor.revents & events != 0 { return }
            throw POSIXError(.ECONNRESET)
        }
        if result == 0 { throw POSIXError(.ETIMEDOUT) }
        if errno != EINTR {
            throw POSIXError(.init(rawValue: errno) ?? .EIO)
        }
    }
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
