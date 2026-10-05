import Darwin
import Foundation
import TraceLogging
import TraceCLICore

final class TraceCLIServer {
    typealias Handler = (
        TraceCLIRequest,
        @escaping (TraceCLIReply) -> Void
    ) -> Void

    private let socketURL: URL
    private let queue = DispatchQueue(label: "com.traceproject.cli-ipc", qos: .userInitiated)
    private var listener: Int32 = -1
    private let requestTimeout: TimeInterval = 30
    private let actionTimeout: TimeInterval = 120
    private let writeTimeout: TimeInterval = 30

    init(bundleIdentifier: String) {
        socketURL = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Application Support/Trace")
            .appendingPathComponent("\(bundleIdentifier).cli.sock")
    }

    func start(handler: @escaping Handler) {
        queue.async { [weak self] in
            guard let self else { return }
            do {
                try self.openListener()
            } catch {
                TraceLogger.shared.record(
                    .error,
                    category: .lifecycle,
                    "CLI listener setup failed",
                    error: error
                )
                return
            }
            while true {
                let client = Darwin.accept(self.listener, nil, nil)
                guard client >= 0 else { continue }
                DispatchQueue.global(qos: .userInitiated).async {
                    self.serve(client, handler: handler)
                }
            }
        }
    }

    func runProbe(completion: @escaping (Bool) -> Void) {
        probeConnect(attempt: 0, completion: completion)
    }

    private func probeConnect(
        attempt: Int,
        completion: @escaping (Bool) -> Void
    ) {
        DispatchQueue.global(qos: .utility).async { [weak self] in
            guard let self else {
                DispatchQueue.main.async { completion(false) }
                return
            }
            var address = sockaddr_un()
            address.sun_family = sa_family_t(AF_UNIX)
            let bytes = Array(self.socketURL.path.utf8)
            guard bytes.count < MemoryLayout.size(ofValue: address.sun_path) else {
                DispatchQueue.main.async { completion(false) }
                return
            }
            withUnsafeMutableBytes(of: &address.sun_path) { buffer in
                buffer.initializeMemory(as: CChar.self, repeating: 0)
                for (index, byte) in bytes.enumerated() { buffer[index] = byte }
            }
            let descriptor = Darwin.socket(AF_UNIX, SOCK_STREAM, 0)
            let connected: Int32
            if descriptor >= 0 {
                connected = withUnsafePointer(to: &address) {
                    $0.withMemoryRebound(to: sockaddr.self, capacity: 1) {
                        Darwin.connect(
                            descriptor,
                            $0,
                            socklen_t(MemoryLayout<sockaddr_un>.size)
                        )
                    }
                }
            } else {
                connected = -1
            }
            if connected != 0 {
                if descriptor >= 0 { Darwin.close(descriptor) }
                if attempt < 50 {
                    DispatchQueue.global().asyncAfter(deadline: .now() + 0.1) {
                        self.probeConnect(attempt: attempt + 1, completion: completion)
                    }
                } else {
                    DispatchQueue.main.async { completion(false) }
                }
                return
            }
            defer { Darwin.close(descriptor) }
            let request = TraceCLIRequest(action: .devices)
            var bytesToWrite = (try? JSONEncoder().encode(request)) ?? Data()
            bytesToWrite.append(0x0A)
            let count = bytesToWrite.withUnsafeBytes {
                Darwin.write(descriptor, $0.baseAddress, $0.count)
            }
            guard count == bytesToWrite.count else {
                DispatchQueue.main.async { completion(false) }
                return
            }
            var response = Data()
            var byte: UInt8 = 0
            while response.count < 1024 * 1024,
                Darwin.read(descriptor, &byte, 1) == 1,
                byte != 0x0A
            {
                response.append(byte)
            }
            let reply = try? JSONDecoder().decode(TraceCLIReply.self, from: response)
            DispatchQueue.main.async {
                completion(reply?.v == 1 && reply?.ok == true)
            }
        }
    }

    private func openListener() throws {
        let directory = socketURL.deletingLastPathComponent()
        try FileManager.default.createDirectory(
            at: directory,
            withIntermediateDirectories: true,
            attributes: [.posixPermissions: 0o700]
        )
        guard chmod(directory.path, 0o700) == 0 else { throw posixError() }
        var existing = stat()
        if lstat(socketURL.path, &existing) == 0 {
            guard (existing.st_mode & S_IFMT) == S_IFSOCK else {
                throw POSIXError(.EADDRINUSE)
            }
            guard unlink(socketURL.path) == 0 else { throw posixError() }
        } else if errno != ENOENT {
            throw posixError()
        }
        var address = sockaddr_un()
        address.sun_family = sa_family_t(AF_UNIX)
        let bytes = Array(socketURL.path.utf8)
        guard bytes.count < MemoryLayout.size(ofValue: address.sun_path) else {
            throw POSIXError(.ENAMETOOLONG)
        }
        withUnsafeMutableBytes(of: &address.sun_path) { buffer in
            buffer.initializeMemory(as: CChar.self, repeating: 0)
            for (index, byte) in bytes.enumerated() { buffer[index] = byte }
        }
        let descriptor = Darwin.socket(AF_UNIX, SOCK_STREAM, 0)
        guard descriptor >= 0 else { throw posixError() }
        do {
            try configureSocket(descriptor)
        } catch {
            Darwin.close(descriptor)
            throw error
        }
        let result = withUnsafePointer(to: &address) {
            $0.withMemoryRebound(to: sockaddr.self, capacity: 1) {
                Darwin.bind(descriptor, $0, socklen_t(MemoryLayout<sockaddr_un>.size))
            }
        }
        guard result == 0 else {
            let error = posixError()
            Darwin.close(descriptor)
            throw error
        }
        guard chmod(socketURL.path, 0o600) == 0, Darwin.listen(descriptor, 8) == 0 else {
            let error = posixError()
            Darwin.close(descriptor)
            _ = unlink(socketURL.path)
            throw error
        }
        listener = descriptor
    }

    private func serve(_ descriptor: Int32, handler: @escaping Handler) {
        do {
            try configureSocket(descriptor)
        } catch {
            Darwin.close(descriptor)
            return
        }
        var peerUID: uid_t = 0
        var peerGID: gid_t = 0
        guard getpeereid(descriptor, &peerUID, &peerGID) == 0,
            peerUID == getuid(),
            let data = readRequest(descriptor),
            let request = try? JSONDecoder().decode(TraceCLIRequest.self, from: data),
            request.v == 1,
            request.action != nil
        else {
            writeReply(
                TraceCLIReply(ok: false, code: "invalidRequest", message: "Invalid CLI request."),
                to: descriptor
            )
            Darwin.close(descriptor)
            return
        }
        DispatchQueue.main.async { [self] in
            let replyOnce = TraceCLIReplyGate { [self] reply in
                DispatchQueue.global(qos: .userInitiated).async {
                    self.writeReply(reply, to: descriptor)
                    Darwin.close(descriptor)
                }
            }
            DispatchQueue.global(qos: .userInitiated).asyncAfter(
                deadline: .now() + self.actionTimeout
            ) {
                replyOnce.send(
                    TraceCLIReply(
                        ok: false,
                        code: "timeout",
                        message: "Trace action timed out."
                    )
                )
            }
            handler(request, replyOnce.send)
        }
    }

    private func readRequest(_ descriptor: Int32) -> Data? {
        let deadline = monotonicDeadline(after: requestTimeout)
        var interrupted = false
        do {
            return try TraceCLIStream.readLine(
                maximumBytes: TraceCLIStream.maximumRequestBytes,
                read: { buffer in
                    do {
                        try waitForSocket(
                            descriptor,
                            events: Int16(POLLIN),
                            deadline: deadline
                        )
                    } catch {
                        interrupted = false
                        return -1
                    }
                    let count = Darwin.read(descriptor, buffer.baseAddress, buffer.count)
                    interrupted = count < 0 && errno == EINTR
                    return count
                },
                isInterrupted: { interrupted }
            )
        } catch {
            return nil
        }
    }

    private func writeReply(_ reply: TraceCLIReply, to descriptor: Int32) {
        var data = (try? JSONEncoder().encode(reply)) ?? Data()
        if data.count > TraceCLIStream.maximumReplyBytes {
            data = (try? JSONEncoder().encode(
                TraceCLIReply(ok: false, code: "actionFailed", message: "CLI response was too large.")
            )) ?? Data()
        }
        data.append(0x0A)
        let deadline = monotonicDeadline(after: writeTimeout)
        var interrupted = false
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
                        interrupted = false
                        return -1
                    }
                    let count = Darwin.write(descriptor, buffer.baseAddress, buffer.count)
                    interrupted = count < 0 && errno == EINTR
                    return count
                },
                isInterrupted: { interrupted }
            )
        } catch {
            TraceLogger.shared.record(
                .error,
                category: .lifecycle,
                "CLI response write failed",
                error: error
            )
        }
    }

    private func configureSocket(_ descriptor: Int32) throws {
        var noSignal: Int32 = 1
        guard setsockopt(
            descriptor,
            SOL_SOCKET,
            SO_NOSIGPIPE,
            &noSignal,
            socklen_t(MemoryLayout<Int32>.size)
        ) == 0 else {
            throw posixError()
        }
        var timeout = timeval(tv_sec: 15, tv_usec: 0)
        for option in [SO_RCVTIMEO, SO_SNDTIMEO] {
            guard setsockopt(
                descriptor,
                SOL_SOCKET,
                option,
                &timeout,
                socklen_t(MemoryLayout<timeval>.size)
            ) == 0 else {
                throw posixError()
            }
        }
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
            if errno != EINTR { throw posixError() }
        }
    }

    private func monotonicDeadline(after seconds: TimeInterval) -> UInt64 {
        DispatchTime.now().uptimeNanoseconds + UInt64(seconds * 1_000_000_000)
    }

    private func posixError() -> POSIXError {
        POSIXError(.init(rawValue: errno) ?? .EIO)
    }
}
