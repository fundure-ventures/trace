#if DEBUG
import AppKit
import TraceLogging

@MainActor
final class PencilSetupController {
    enum Step {
        case idle, discovering, choose, trust, finderTrust, ipadTrust, enable, unplug, wireless
        case permission, attach, pickup, replace, done
    }

    private(set) var step: Step = .idle
    private(set) var instruction = "Look for an iPad on the same Wi-Fi network."
    private(set) var action: String? = "Find iPad"
    private(set) var devices: [PencilNearbyIPad] = []
    private(set) var busy = false
    var onChange: (() -> Void)?
    var onComplete: ((PencilIPadConfiguration) -> Void)?
    var onRequestScreenAccess: (() -> Void)?
    var onVerificationChange: ((Bool) -> Void)?
    private let helper = PencilTelemetryMonitor()
    private var selected: PencilNearbyIPad?
    private var configuration: PencilIPadConfiguration?
    private var lastCharging: Bool?
    private var retryAction: String?
    private var verifying = false

    init() {
        if let configuration = PencilIPadConfiguration.load() {
            self.configuration = configuration
            step = .done
            instruction = "\(configuration.name) is configured. Pencil automation is in Settings."
            action = "Check again"
        }
        helper.onSetupEvent = { [weak self] event in self?.receive(event) }
        helper.onReady = { [weak self] _ in
            guard let self, self.step == .wireless else { return }
            self.busy = false
            if CGPreflightScreenCaptureAccess() {
                self.beginPencilCheck()
            } else {
                self.show(
                    .permission,
                    "Allow Screen Recording so picking up the Pencil can capture the Mac app.",
                    action: "Allow"
                )
            }
        }
        helper.onState = { [weak self] charging, _ in
            guard let self else { return }
            self.lastCharging = charging
            switch (self.step, charging) {
            case (.attach, true):
                self.show(.pickup, "Pick up the Pencil from the iPad's magnetic edge.", action: nil)
            case (.pickup, false):
                self.show(.replace, "Put the Pencil back on the iPad's magnetic edge.", action: nil)
            case (.replace, true):
                self.finish()
            default: break
            }
        }
        helper.onError = { [weak self] message in
            guard let self else { return }
            self.helper.stop()
            self.endVerification()
            self.busy = false
            self.instruction = message
            self.action = self.step == .wireless ? "Try Wi-Fi again" : self.retryAction ?? "Try again"
            if [.permission, .attach, .pickup, .replace].contains(self.step) {
                self.step = .unplug
                self.action = "Try Wi-Fi again"
            }
            TraceLogger.shared.record(.error, category: .capture, "iPad setup step failed")
            self.onChange?()
        }
    }

    func discoverIfNeeded() {
        if step == .idle { advance() }
    }

    func selectDevice(at index: Int) {
        guard devices.indices.contains(index), step == .choose else { return }
        selected = devices[index]
        instruction = "Set up \(devices[index].name) for Apple Pencil pickup."
        onChange?()
    }

    func advance() {
        guard !busy else { return }
        switch step {
        case .idle, .discovering:
            show(.discovering, "Looking for iPads on your Wi-Fi. Allow Local Network access if asked.", action: nil)
            run(["--discover"])
        case .choose:
            show(.trust, "Connect this iPad by USB and unlock it.", action: "Check trust")
        case .trust:
            run(["--trust", selected?.name ?? "", selected?.host ?? ""])
        case .finderTrust:
            show(.ipadTrust, "On the unlocked iPad, tap Trust and enter its passcode.", action: "Check trust")
        case .ipadTrust:
            run(["--trust", selected?.name ?? "", selected?.host ?? ""])
        case .enable:
            run(["--enable", selected?.name ?? "", selected?.host ?? ""])
        case .unplug, .wireless:
            guard let configuration else { return }
            lastCharging = nil
            verifying = true
            onVerificationChange?(true)
            show(.wireless, "Checking the iPad over Wi-Fi, without USB.", action: nil)
            run(["--verify", configuration.udid, configuration.host])
        case .permission:
            if CGPreflightScreenCaptureAccess() {
                beginPencilCheck()
            } else {
                onRequestScreenAccess?()
                instruction = "Allow Trace in Screen Recording settings, then check again."
                action = "Check permission"
                onChange?()
            }
        case .attach, .pickup, .replace:
            break
        case .done:
            configuration = nil
            devices = []
            selected = nil
            show(.idle, "Look for an iPad on the same Wi-Fi network.", action: "Find iPad")
            advance()
        }
    }

    func stop() {
        helper.stop()
        endVerification()
        if step != .done {
            busy = false
            step = .idle
            action = "Find iPad"
            instruction = "Look for an iPad on the same Wi-Fi network."
        }
    }

    private func run(_ arguments: [String]) {
        retryAction = action
        busy = true
        action = nil
        onChange?()
        do {
            try helper.start(arguments: arguments)
        } catch {
            busy = false
            instruction = error.localizedDescription
                + " This debug experiment requires the local diagnostic tools described in Development."
            action = retryAction ?? "Try again"
            TraceLogger.shared.record(.error, category: .capture, "iPad setup helper failed", error: error)
            onChange?()
        }
    }

    private func receive(_ event: PencilTelemetryMonitor.Event) {
        busy = false
        switch event.event {
        case "devices":
            helper.stop()
            devices = event.devices ?? []
            selected = devices.first
            if let selected {
                show(.choose, "Set up \(selected.name) for Apple Pencil pickup.", action: "Set up")
            } else {
                let detail = (event.unavailable ?? 0) > 0
                    ? "Nearby devices could not be identified. Check Local Network access, or connect your iPad by USB."
                    : "No iPad is advertising on Wi-Fi. Connect your iPad by USB and unlock it to enable wireless access."
                show(.trust, detail, action: "Check USB")
            }
        case "trustNeeded":
            helper.stop()
            show(.finderTrust, "Select your iPad in Finder and click Trust.", action: "Continue")
        case "trusted", "prepared":
            helper.stop()
            guard let udid = event.udid, let name = event.name, let host = event.host else {
                instruction = "The iPad setup response was incomplete. Try again."
                action = "Try again"
                onChange?()
                return
            }
            selected = PencilNearbyIPad(name: name, host: host)
            configuration = PencilIPadConfiguration(udid: udid, host: host, name: name)
            if event.event == "trusted" {
                show(
                    .enable,
                    "Let this Mac read Pencil state over Wi-Fi. No iPad app or Developer Mode is needed.",
                    action: "Enable wireless"
                )
            } else {
                show(.unplug, "Unplug the USB cable. Keep the iPad awake on the same Wi-Fi.", action: "Check Wi-Fi")
            }
        default: break
        }
    }

    private func beginPencilCheck() {
        if lastCharging == true {
            show(.pickup, "Pick up the Pencil from the iPad's magnetic edge.", action: nil)
        } else {
            show(.attach, "Attach or reattach the Pencil to the iPad's magnetic edge.", action: nil)
        }
    }

    private func finish() {
        helper.stop()
        guard let configuration else { return }
        configuration.save()
        endVerification()
        show(.done, "\(configuration.name) is ready. Pencil automation is in Settings.", action: "Check again")
        onComplete?(configuration)
    }

    private func endVerification() {
        if verifying {
            verifying = false
            onVerificationChange?(false)
        }
    }

    private func show(_ step: Step, _ instruction: String, action: String?) {
        self.step = step
        self.instruction = instruction
        self.action = action
        onChange?()
    }
}
#endif
