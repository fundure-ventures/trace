import AppKit
import TraceLogging
import Darwin

struct TraceScreenshotDevice: Equatable {
    enum Platform: String {
        case android
        case ios
    }

    let platform: Platform
    let identifier: String
    let name: String
    let unavailableReason: String?

    var menuTitle: String {
        "from \(name)"
    }
}

enum TraceDeviceScreenshotError: LocalizedError {
    case failed(String)

    var errorDescription: String? {
        switch self {
        case let .failed(message): return message
        }
    }
}

enum TraceDeviceScreenshotDiscovery {
    static func androidDevices(_ output: String) -> [TraceScreenshotDevice] {
        output.split(whereSeparator: \.isNewline).compactMap { line in
            let fields = line.split(whereSeparator: \.isWhitespace)
            guard fields.count >= 2,
                  !line.hasPrefix("List of devices"),
                  ["device", "unauthorized", "offline", "no"].contains(String(fields[1]))
            else {
                return nil
            }
            let model = fields.first(where: { $0.hasPrefix("model:") })
                .map { String($0.dropFirst(6)).replacingOccurrences(of: "_", with: " ") }
            let reason: String?
            switch fields[1] {
            case "device": reason = nil
            case "unauthorized": reason = "Allow USB debugging on this device."
            case "offline": reason = "Reconnect this device."
            default: reason = "ADB cannot access this device."
            }
            return TraceScreenshotDevice(
                platform: .android,
                identifier: String(fields[0]),
                name: model ?? String(fields[0]),
                unavailableReason: reason
            )
        }
    }

    static func iosDevices(_ data: Data) throws -> [TraceScreenshotDevice] {
        let inventory = try JSONDecoder().decode(Inventory.self, from: data)
        return inventory.result.devices.compactMap { device in
            let hardware = device.properties?.hardware ?? device.hardwareProperties
            let connection = device.properties?.connection ?? device.connectionProperties
            let name = device.properties?.state?.name ?? device.deviceProperties?.name
            guard hardware?.reality == "physical",
                  hardware?.platform == "iOS",
                  connection?.pairingState == "paired"
            else {
                return nil
            }
            return TraceScreenshotDevice(
                platform: .ios,
                identifier: device.identifier,
                name: name ?? hardware?.marketingName ?? "iOS device",
                unavailableReason: nil
            )
        }
    }

    private struct Inventory: Decodable {
        let result: Result
        struct Result: Decodable {
            let devices: [Device]
        }
        struct Device: Decodable {
            let identifier: String
            let properties: Properties?
            let hardwareProperties: Hardware?
            let connectionProperties: Connection?
            let deviceProperties: State?
        }
        struct Properties: Decodable {
            let hardware: Hardware?
            let connection: Connection?
            let state: State?
        }
        struct Hardware: Decodable {
            let reality: String?
            let platform: String?
            let marketingName: String?
        }
        struct Connection: Decodable {
            let pairingState: String?
        }
        struct State: Decodable {
            let name: String?
        }
    }
}

@MainActor
enum TraceDeviceScreenshotMenu {
    static func configure(
        _ item: NSMenuItem,
        devices: [TraceScreenshotDevice],
        applicationName: String,
        target: AnyObject,
        desktopAction: Selector,
        deviceAction: Selector,
        capturing: Bool
    ) {
        item.target = target
        item.action = desktopAction
        guard !devices.isEmpty else {
            item.submenu = nil
            return
        }
        let menu = NSMenu(title: item.title)
        menu.delegate = target as? NSMenuDelegate
        let desktop = NSMenuItem(
            title: "from \(applicationName)",
            action: desktopAction,
            keyEquivalent: ""
        )
        desktop.target = target
        desktop.keyEquivalent = item.keyEquivalent
        desktop.keyEquivalentModifierMask = item.keyEquivalentModifierMask
        menu.addItem(desktop)
        menu.addItem(.separator())
        for device in devices {
            let source = NSMenuItem(
                title: device.menuTitle,
                action: deviceAction,
                keyEquivalent: ""
            )
            source.target = target
            source.representedObject = device
            source.isEnabled = !capturing && device.unavailableReason == nil
            source.toolTip = device.unavailableReason
            menu.addItem(source)
        }
        menu.autoenablesItems = false
        item.submenu = menu
    }

    static func insert(
        hasDocument: Bool,
        createDocument: () -> Bool,
        insertImage: () -> Bool
    ) -> Bool {
        guard hasDocument || createDocument() else {
            return false
        }
        return insertImage()
    }
}

struct TraceDeviceWarmupPolicy {
    private var pending = Set<String>()
    private var finishedAt: [String: TimeInterval] = [:]

    mutating func begin(_ device: TraceScreenshotDevice, now: TimeInterval) -> Bool {
        guard device.platform == .ios,
              device.unavailableReason == nil,
              !pending.contains(device.identifier),
              finishedAt[device.identifier].map({ now - $0 >= 10 }) ?? true
        else {
            return false
        }
        pending.insert(device.identifier)
        return true
    }

    mutating func finish(_ device: TraceScreenshotDevice, now: TimeInterval) {
        pending.remove(device.identifier)
        finishedAt[device.identifier] = now
    }
}

final class TraceDeviceCommandRunner {
    func run(
        executable: URL,
        arguments: [String],
        environment: [String: String]? = nil,
        timeout: TimeInterval = 20
    ) throws -> Data {
        let files = FileManager.default
        let directory = files.temporaryDirectory
            .appendingPathComponent("trace-device-command-\(UUID().uuidString)")
        try files.createDirectory(
            at: directory,
            withIntermediateDirectories: false,
            attributes: [.posixPermissions: 0o700]
        )
        defer {
            do { try files.removeItem(at: directory) }
            catch {
                TraceLogger.shared.record(.error, category: .capture, "Device command cleanup failed", error: error)
            }
        }
        let outputURL = directory.appendingPathComponent("stdout")
        let errorURL = directory.appendingPathComponent("stderr")
        try Data().write(to: outputURL)
        try Data().write(to: errorURL)
        let output = try FileHandle(forWritingTo: outputURL)
        let errors = try FileHandle(forWritingTo: errorURL)
        defer {
            output.closeFile()
            errors.closeFile()
        }
        let process = Process()
        process.executableURL = executable
        process.arguments = arguments
        process.environment = environment
        process.standardOutput = output
        process.standardError = errors
        let finished = DispatchSemaphore(value: 0)
        process.terminationHandler = { _ in finished.signal() }
        try process.run()
        if finished.wait(timeout: .now() + timeout) == .timedOut {
            if process.isRunning { process.terminate() }
            if finished.wait(timeout: .now() + 1) == .timedOut {
                kill(process.processIdentifier, SIGKILL)
                process.waitUntilExit()
            }
            throw TraceDeviceScreenshotError.failed("Device communication timed out. Check the connection and try again.")
        }
        guard process.terminationStatus == 0 else {
            let detail = String(decoding: try Data(contentsOf: errorURL), as: UTF8.self)
                .trimmingCharacters(in: .whitespacesAndNewlines)
            throw TraceDeviceScreenshotError.failed(
                detail.isEmpty ? "The device command failed." : String(detail.prefix(2000))
            )
        }
        let attributes = try files.attributesOfItem(atPath: outputURL.path)
        guard let size = attributes[.size] as? NSNumber,
              size.intValue <= 64 * 1024 * 1024
        else {
            throw TraceDeviceScreenshotError.failed("The device returned an oversized screenshot.")
        }
        return try Data(contentsOf: outputURL)
    }
}

@MainActor
final class DeviceScreenshotService {
    private(set) var devices: [TraceScreenshotDevice] = []
    private(set) var isCapturing = false
    var onDevicesChange: (() -> Void)?

    private let discoveryQueue = DispatchQueue(label: "com.traceproject.device-discovery", qos: .utility)
    private let captureQueue = DispatchQueue(label: "com.traceproject.device-capture", qos: .userInitiated)
    private let warmupQueue = DispatchQueue(label: "com.traceproject.device-warmup", qos: .utility)
    private var warmupPolicy = TraceDeviceWarmupPolicy()
    private var timer: Timer?
    private var refreshing = false
    private var refreshCompletions: [() -> Void] = []
    private var lastDiscoveryError: String?
    private var tools: (adb: URL?, ios: URL?)?

    func start() {
        refresh()
        let timer = Timer(timeInterval: 10, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.refresh() }
        }
        RunLoop.main.add(timer, forMode: .common)
        self.timer = timer
    }

    func stop() {
        timer?.invalidate()
        timer = nil
    }

    func warmAvailableIOSDevices() {
        guard !isCapturing, let tool = tools?.ios else { return }
        for device in devices {
            guard warmupPolicy.begin(
                device,
                now: ProcessInfo.processInfo.systemUptime
            ) else { continue }
            warmupQueue.async {
                do {
                    _ = try TraceDeviceCommandRunner().run(
                        executable: tool,
                        arguments: [
                            "device", "info", "displays", "--device", device.identifier,
                            "--timeout", "5",
                        ],
                        timeout: 6
                    )
                } catch {
                    TraceLogger.shared.record(.error, category: .capture, "iOS connection warm-up failed", error: error)
                }
                DispatchQueue.main.async {
                    self.warmupPolicy.finish(
                        device,
                        now: ProcessInfo.processInfo.systemUptime
                    )
                }
            }
        }
    }

    func refresh(completion: (() -> Void)? = nil) {
        if refreshing {
            if let completion { refreshCompletions.append(completion) }
            return
        }
        TraceLogger.shared.record(.debug, category: .capture, "Device discovery started")
        refreshing = true
        if let completion { refreshCompletions.append(completion) }
        let cachedTools = tools
        discoveryQueue.async {
            let runner = TraceDeviceCommandRunner()
            var devices: [TraceScreenshotDevice] = []
            var failures: [String] = []
            let resolvedTools: (adb: URL?, ios: URL?)
            if let cachedTools {
                resolvedTools = cachedTools
            } else {
                resolvedTools = (Self.adbURL, Self.iosTool(runner))
            }
            if let adb = resolvedTools.adb {
                do {
                    let data = try runner.run(executable: adb, arguments: ["devices", "-l"])
                    devices += TraceDeviceScreenshotDiscovery.androidDevices(String(decoding: data, as: UTF8.self))
                } catch {
                    TraceLogger.shared.record(.error, category: .capture, "Android discovery failed", error: error)
                    failures.append("Android discovery: \(error.localizedDescription)")
                }
            }
            do {
                if let tool = resolvedTools.ios {
                    let data = try runner.run(
                        executable: tool,
                        arguments: [
                            "list", "devices", "--timeout", "15",
                            "--filter", "State BEGINSWITH 'available' OR State BEGINSWITH 'connected'",
                            "--json-output", "-",
                        ]
                    )
                    devices += try TraceDeviceScreenshotDiscovery.iosDevices(data)
                }
            } catch {
                TraceLogger.shared.record(.error, category: .capture, "iOS discovery failed", error: error)
                failures.append("iOS discovery: \(error.localizedDescription)")
            }
            let found = devices
            let error = failures.isEmpty ? nil : failures.joined(separator: "\n")
            DispatchQueue.main.async {
                self.refreshing = false
                self.tools = resolvedTools
                TraceLogger.shared.record(.debug, category: .capture, "Device discovery completed")
                self.lastDiscoveryError = error
                if self.devices != found {
                    self.devices = found
                    self.onDevicesChange?()
                }
                let completions = self.refreshCompletions
                self.refreshCompletions.removeAll()
                completions.forEach { $0() }
            }
        }
    }

    func capture(
        _ device: TraceScreenshotDevice,
        completion: @escaping (Result<NSImage, Error>) -> Void
    ) {
        TraceLogger.shared.record(.debug, category: .capture, "Device screenshot requested")
        guard !isCapturing else {
            completion(.failure(TraceDeviceScreenshotError.failed("A device screenshot is already being captured.")))
            return
        }
        isCapturing = true
        onDevicesChange?()
        let tools = tools
        captureQueue.async {
            let result: Result<NSImage, Error>
            do {
                let runner = TraceDeviceCommandRunner()
                let data: Data
                switch device.platform {
                case .android:
                    guard let adb = tools?.adb else {
                        throw TraceDeviceScreenshotError.failed("Install Android SDK Platform Tools to capture this device.")
                    }
                    data = try runner.run(
                        executable: adb,
                        arguments: ["-s", device.identifier, "exec-out", "screencap", "-p"],
                        timeout: 30
                    )
                case .ios:
                    guard let tool = tools?.ios else {
                        throw TraceDeviceScreenshotError.failed("Install a compatible full Xcode to capture this iOS device.")
                    }
                    let directory = FileManager.default.temporaryDirectory
                        .appendingPathComponent("trace-device-screenshot-\(UUID().uuidString)")
                    try FileManager.default.createDirectory(
                        at: directory,
                        withIntermediateDirectories: false,
                        attributes: [.posixPermissions: 0o700]
                    )
                    defer {
                        do { try FileManager.default.removeItem(at: directory) }
                        catch {
                            TraceLogger.shared.record(.error, category: .capture, "Device screenshot cleanup failed", error: error)
                        }
                    }
                    let destination = directory.appendingPathComponent("screenshot.png")
                    _ = try runner.run(
                        executable: tool,
                        arguments: [
                            "device", "capture", "screenshot", "--device", device.identifier,
                            "--destination", destination.path, "--timeout", "25",
                        ],
                        timeout: 30
                    )
                    let attributes = try FileManager.default.attributesOfItem(atPath: destination.path)
                    guard let size = attributes[.size] as? NSNumber,
                          size.intValue <= 64 * 1024 * 1024
                    else {
                        throw TraceDeviceScreenshotError.failed("The device returned an oversized screenshot.")
                    }
                    data = try Data(contentsOf: destination)
                }
                guard data.starts(with: [137, 80, 78, 71, 13, 10, 26, 10]),
                      let bitmap = NSBitmapImageRep(data: data),
                      bitmap.pixelsWide > 0, bitmap.pixelsHigh > 0
                else {
                    throw TraceDeviceScreenshotError.failed("The device did not return a valid PNG screenshot.")
                }
                let image = NSImage(size: NSSize(width: bitmap.pixelsWide, height: bitmap.pixelsHigh))
                image.addRepresentation(bitmap)
                TraceLogger.shared.record(.debug, category: .capture, "Device screenshot completed")
                result = .success(image)
            } catch {
                result = .failure(error)
            }
            DispatchQueue.main.async {
                self.isCapturing = false
                self.onDevicesChange?()
                completion(result)
                self.refresh()
            }
        }
    }

    nonisolated private static var adbURL: URL? {
        let environment = ProcessInfo.processInfo.environment
        let directories = (environment["PATH"] ?? "").split(separator: ":").map(String.init)
            + ["/opt/homebrew/bin", "/usr/local/bin"]
            + [FileManager.default.homeDirectoryForCurrentUser
                .appendingPathComponent("Library/Android/sdk/platform-tools").path]
            + [environment["ANDROID_HOME"], environment["ANDROID_SDK_ROOT"]]
                .compactMap { $0.map { "\($0)/platform-tools" } }
        return directories.map { URL(fileURLWithPath: $0).appendingPathComponent("adb") }
            .first { FileManager.default.isExecutableFile(atPath: $0.path) }
    }

    nonisolated private static func iosTool(_ runner: TraceDeviceCommandRunner) -> URL? {
        let xcrun = URL(fileURLWithPath: "/usr/bin/xcrun")
        let defaultEnvironment = ProcessInfo.processInfo.environment
        var environments = [defaultEnvironment]
        let xcode = "/Applications/Xcode.app/Contents/Developer"
        if FileManager.default.fileExists(atPath: xcode) {
            var fallback = defaultEnvironment
            fallback["DEVELOPER_DIR"] = xcode
            environments.append(fallback)
        }
        for environment in environments {
            do {
                let output = try runner.run(
                    executable: xcrun, arguments: ["--find", "devicectl"], environment: environment
                )
                let path = String(decoding: output, as: UTF8.self)
                    .trimmingCharacters(in: .whitespacesAndNewlines)
                let tool = URL(fileURLWithPath: path)
                guard FileManager.default.isExecutableFile(atPath: path) else { continue }
                _ = try runner.run(
                    executable: tool,
                    arguments: ["help", "device", "capture", "screenshot"]
                )
                return tool
            } catch {
                TraceLogger.shared.record(.error, category: .capture, "iOS screenshot tool unavailable", error: error)
            }
        }
        return nil
    }
}
