import AppKit
import TraceLogging

struct PencilIPadConfiguration {
    let udid: String
    let host: String
    let name: String

    static func loadAll() -> [Self] {
        if let saved = UserDefaults.standard.array(forKey: "TracePencilIPads") as? [[String: String]] {
            return saved.compactMap {
                guard let udid = $0["udid"], let host = $0["host"], let name = $0["name"] else {
                    TraceLogger.shared.record(.error, category: .capture, "Saved iPad configuration is incomplete")
                    return nil
                }
                return Self(udid: udid, host: host, name: name)
            }
        }
        return load().map { [$0] } ?? []
    }

    var isEnabled: Bool {
        get {
            let defaults = UserDefaults.standard
            if let enabled = defaults.object(forKey: "TracePencilEnabled.\(udid)") as? Bool {
                return enabled
            }
            return defaults.string(forKey: "TracePencilIPadUDID") == udid
                ? (defaults.object(forKey: "TracePencilSidecarEnabled") as? Bool ?? true)
                : true
        }
        nonmutating set {
            UserDefaults.standard.set(newValue, forKey: "TracePencilEnabled.\(udid)")
        }
    }

    static func load() -> Self? {
        let defaults = UserDefaults.standard
        guard let udid = defaults.string(forKey: "TracePencilIPadUDID"),
              let host = defaults.string(forKey: "TracePencilIPadHost"),
              let name = defaults.string(forKey: "TracePencilIPadName")
        else { return nil }
        return Self(udid: udid, host: host, name: name)
    }

    func save() {
        let defaults = UserDefaults.standard
        var configurations = Self.loadAll()
        // Preserve the legacy opt-out before changing the last-configured iPad.
        for config in configurations {
            defaults.set(config.isEnabled, forKey: "TracePencilEnabled.\(config.udid)")
        }
        defaults.set(isEnabled, forKey: "TracePencilEnabled.\(udid)")
        if let index = configurations.firstIndex(where: { $0.udid == udid }) {
            configurations[index] = self
        } else {
            configurations.append(self)
        }
        defaults.set(configurations.map {
            ["udid": $0.udid, "host": $0.host, "name": $0.name]
        }, forKey: "TracePencilIPads")
        defaults.set(udid, forKey: "TracePencilIPadUDID")
        defaults.set(host, forKey: "TracePencilIPadHost")
        defaults.set(name, forKey: "TracePencilIPadName")
    }
}

struct PencilNearbyIPad: Decodable {
    let name: String
    let host: String
}

final class PencilTelemetryMonitor {
    struct Event: Decodable {
        let event: String
        let name: String?
        let charging: Bool?
        let baseline: Bool?
        let appOpen: Bool?
        let message: String?
        let devices: [PencilNearbyIPad]?
        let udid: String?
        let host: String?
        let unavailable: Int?
    }

    var onReady: ((String) -> Void)?
    /// charging, baseline, appOpen (nil when the iPad foreground is unknown).
    var onState: ((Bool, Bool, Bool?) -> Void)?
    var onError: ((String) -> Void)?
    var onSetupEvent: ((Event) -> Void)?
    private var process: Process?
    private var output: Pipe?
    private var buffer = Data()

    func start(udid: String, host: String) throws {
        try start(arguments: [udid, host])
    }

    func start(arguments: [String]) throws {
        stop()
        let helper = Bundle.main.bundleURL.appendingPathComponent(
            "Contents/Helpers/PencilTelemetry.app/Contents/MacOS/trace-pencil-telemetry"
        )
        guard FileManager.default.isExecutableFile(atPath: helper.path) else {
            throw SidecarCaptureProbeError.failed(
                "The bundled Pencil helper is missing. Rebuild or reinstall Trace."
            )
        }
        let process = Process()
        let pipe = Pipe()
        process.executableURL = helper
        process.arguments = arguments
        process.standardOutput = pipe
        process.standardError = FileHandle.standardError
        pipe.fileHandleForReading.readabilityHandler = { [weak self] handle in
            let data = handle.availableData
            DispatchQueue.main.async {
                guard let self, self.process === process, !data.isEmpty else { return }
                self.buffer.append(data)
                self.consumeEvents()
            }
        }
        process.terminationHandler = { [weak self] process in
            DispatchQueue.main.async {
                guard let self, self.process === process, process.terminationStatus != 0 else { return }
                self.onError?(self.onSetupEvent == nil
                    ? "Pencil monitoring stopped. Toggle the setting or rerun iPad setup to retry."
                    : "iPad setup helper stopped. Reopen Setup and retry.")
            }
        }
        self.process = process
        output = pipe
        do { try process.run() }
        catch {
            stop()
            throw error
        }
    }

    func stop() {
        output?.fileHandleForReading.readabilityHandler = nil
        process?.terminationHandler = nil
        if process?.isRunning == true { process?.terminate() }
        process = nil
        output = nil
        buffer.removeAll()
    }

    private func consumeEvents() {
        while let end = buffer.firstIndex(of: 10) {
            let line = Data(buffer[..<end])
            buffer.removeSubrange(...end)
            do {
                let event = try JSONDecoder().decode(Event.self, from: line)
                switch event.event {
                case "devices", "trustNeeded", "trusted", "prepared", "waiting", "checkingWireless":
                    onSetupEvent?(event)
                case "ready":
                    guard let name = event.name else {
                        throw SidecarCaptureProbeError.failed("Pencil helper omitted the iPad name.")
                    }
                    onReady?(name)
                case "state":
                    guard let charging = event.charging, let baseline = event.baseline else {
                        throw SidecarCaptureProbeError.failed("Pencil helper returned an invalid state.")
                    }
                    onState?(charging, baseline, event.appOpen)
                case "error":
                    onError?(event.message ?? "Pencil telemetry failed.")
                default:
                    throw SidecarCaptureProbeError.failed("Unknown Pencil helper event.")
                }
            } catch {
                onError?(error.localizedDescription)
            }
        }
    }

    deinit { stop() }
}
