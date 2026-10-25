#if DEBUG
import AppKit

struct PencilIPadConfiguration {
    let udid: String
    let host: String
    let name: String

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
        defaults.set(udid, forKey: "TracePencilIPadUDID")
        defaults.set(host, forKey: "TracePencilIPadHost")
        defaults.set(name, forKey: "TracePencilIPadName")
    }

    static var enabled: Bool {
        get {
            UserDefaults.standard.object(forKey: "TracePencilSidecarEnabled") as? Bool ?? true
        }
        set { UserDefaults.standard.set(newValue, forKey: "TracePencilSidecarEnabled") }
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
        let message: String?
        let devices: [PencilNearbyIPad]?
        let udid: String?
        let host: String?
        let unavailable: Int?
    }

    var onReady: ((String) -> Void)?
    var onState: ((Bool, Bool) -> Void)?
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
        let candidates = [
            "/opt/homebrew/bin/uv",
            FileManager.default.homeDirectoryForCurrentUser
                .appendingPathComponent(".local/bin/uv").path,
            "/usr/local/bin/uv",
        ]
        guard let uv = candidates.first(where: {
            FileManager.default.isExecutableFile(atPath: $0)
        }),
        let helper = Bundle.main.url(
            forResource: "pencil-telemetry", withExtension: "py"
        ) else {
            throw SidecarCaptureProbeError.failed(
                "Pencil automation needs uv and the bundled debug telemetry helper."
            )
        }
        let process = Process()
        let pipe = Pipe()
        process.executableURL = URL(fileURLWithPath: uv)
        process.arguments = [
            "tool", "run", "--offline", "--from", "pymobiledevice3==11.44.0",
            "python", "-u", helper.path,
        ] + arguments
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
                    : "iPad setup helper stopped. Check that uv and cached pymobiledevice3 11.44.0 are available (see Development).")
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
                case "devices", "trustNeeded", "trusted", "prepared":
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
                    onState?(charging, baseline)
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
#endif
