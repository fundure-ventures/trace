import Darwin
import Foundation
import TraceCLICore

final class TraceCLIServer {
    typealias Handler = (
        TraceCLIRequest,
        @escaping (TraceCLIReply) -> Void
    ) -> Void

    private let socketURL: URL
    private let queue = DispatchQueue(label: "com.traceproject.cli-ipc", qos: .userInitiated)
    private var listener: Int32 = -1

    init(bundleIdentifier: String) {
        socketURL = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Application Support/Trace")
            .appendingPathComponent("\(bundleIdentifier).cli.sock")
    }

    func start(handler: @escaping Handler) {
        queue.async { [weak self] in
            guard let self, self.openListener() else { return }
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

    private func openListener() -> Bool {
        let directory = socketURL.deletingLastPathComponent()
        do {
            try FileManager.default.createDirectory(
                at: directory,
                withIntermediateDirectories: true,
                attributes: [.posixPermissions: 0o700]
            )
        } catch {
            return false
        }
        guard chmod(directory.path, 0o700) == 0 else { return false }
        var existing = stat()
        if lstat(socketURL.path, &existing) == 0 {
            guard (existing.st_mode & S_IFMT) == S_IFSOCK else { return false }
            guard unlink(socketURL.path) == 0 else { return false }
        }
        var address = sockaddr_un()
        address.sun_family = sa_family_t(AF_UNIX)
        let bytes = Array(socketURL.path.utf8)
        guard bytes.count < MemoryLayout.size(ofValue: address.sun_path) else { return false }
        withUnsafeMutableBytes(of: &address.sun_path) { buffer in
            buffer.initializeMemory(as: CChar.self, repeating: 0)
            for (index, byte) in bytes.enumerated() { buffer[index] = byte }
        }
        let descriptor = Darwin.socket(AF_UNIX, SOCK_STREAM, 0)
        guard descriptor >= 0 else { return false }
        let result = withUnsafePointer(to: &address) {
            $0.withMemoryRebound(to: sockaddr.self, capacity: 1) {
                Darwin.bind(descriptor, $0, socklen_t(MemoryLayout<sockaddr_un>.size))
            }
        }
        guard result == 0, chmod(socketURL.path, 0o600) == 0,
            Darwin.listen(descriptor, 8) == 0
        else {
            Darwin.close(descriptor)
            _ = unlink(socketURL.path)
            return false
        }
        listener = descriptor
        return true
    }

    private func serve(_ descriptor: Int32, handler: @escaping Handler) {
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
        DispatchQueue.main.async {
            handler(request) { reply in
                self.writeReply(reply, to: descriptor)
                Darwin.close(descriptor)
            }
        }
    }

    private func readRequest(_ descriptor: Int32) -> Data? {
        var data = Data()
        var buffer = [UInt8](repeating: 0, count: 4096)
        while data.count < 4 * 1024 * 1024 {
            let count = Darwin.read(descriptor, &buffer, buffer.count)
            guard count > 0 else { return nil }
            if let newline = buffer[..<count].firstIndex(of: 0x0A) {
                data.append(contentsOf: buffer[..<newline])
                return data
            }
            data.append(contentsOf: buffer[..<count])
        }
        return nil
    }

    private func writeReply(_ reply: TraceCLIReply, to descriptor: Int32) {
        var data = (try? JSONEncoder().encode(reply)) ?? Data()
        data.append(0x0A)
        data.withUnsafeBytes { bytes in
            guard let base = bytes.baseAddress else { return }
            var offset = 0
            while offset < bytes.count {
                let count = Darwin.write(
                    descriptor, base.advanced(by: offset), bytes.count - offset)
                guard count > 0 else { break }
                offset += count
            }
        }
    }
}
