import Darwin
import Dispatch
import Foundation
import NeoTransport

private enum DiagnosticsCommand: String {
    case observe
    case scan
}

private enum HoverSettingOption: String {
    case on
    case off

    var isEnabled: Bool {
        self == .on
    }
}

private struct DiagnosticsOptions {
    var command: DiagnosticsCommand = .observe
    var deviceFilter: String?
    var timeout: TimeInterval?
    var statusInterval: TimeInterval?
    var enableInput = false
    var hoverSetting: HoverSettingOption?
    var automaticallyReconnect = true
    var includeRawEvents = true
    var logFile: String?
    var pidFile: String?
    var stdoutOnly = false
    var showHelp = false

    static func parse(_ arguments: [String]) throws -> DiagnosticsOptions {
        var options = DiagnosticsOptions()
        var index = 0

        if let first = arguments.first,
           let command = DiagnosticsCommand(rawValue: first)
        {
            options.command = command
            index += 1
        }

        while index < arguments.count {
            let argument = arguments[index]
            switch argument {
            case "--device":
                index += 1
                guard index < arguments.count else {
                    throw DiagnosticsArgumentError("--device requires a UUID or name")
                }
                options.deviceFilter = arguments[index]
            case "--timeout":
                index += 1
                guard index < arguments.count,
                      let timeout = TimeInterval(arguments[index]),
                      timeout > 0
                else {
                    throw DiagnosticsArgumentError("--timeout requires positive seconds")
                }
                options.timeout = timeout
            case "--status-interval":
                index += 1
                guard index < arguments.count,
                      let interval = TimeInterval(arguments[index]),
                      interval > 0
                else {
                    throw DiagnosticsArgumentError(
                        "--status-interval requires positive seconds"
                    )
                }
                options.statusInterval = interval
            case "--enable-input":
                options.enableInput = true
            case "--hover":
                index += 1
                guard index < arguments.count,
                      let setting = HoverSettingOption(rawValue: arguments[index])
                else {
                    throw DiagnosticsArgumentError("--hover requires on or off")
                }
                options.hoverSetting = setting
            case "--no-reconnect":
                options.automaticallyReconnect = false
            case "--summary-only":
                options.includeRawEvents = false
            case "--log-file":
                index += 1
                guard index < arguments.count else {
                    throw DiagnosticsArgumentError("--log-file requires a path")
                }
                options.logFile = arguments[index]
            case "--pid-file":
                index += 1
                guard index < arguments.count else {
                    throw DiagnosticsArgumentError("--pid-file requires a path")
                }
                options.pidFile = arguments[index]
            case "--stdout-only":
                options.stdoutOnly = true
            case "--help", "-h":
                options.showHelp = true
            default:
                throw DiagnosticsArgumentError("unknown argument: \(argument)")
            }
            index += 1
        }

        return options
    }

    static let usage = """
    Trace Neo Smartpen diagnostics

    Usage:
      trace-neo-diagnostics observe [options]
      trace-neo-diagnostics scan [options]

    Commands:
      observe              Scan, connect to the first matching Neo pen, and log events
      scan                 Scan and inventory matching Neo pens without connecting

    Options:
      --device <value>     Match a macOS peripheral UUID or part of the pen name
      --timeout <seconds>  Stop the diagnostic session after the given duration
      --status-interval <seconds>
                           Poll pen status to observe battery/charging changes
      --enable-input       Register all available Ncode notes for live input
      --hover <on|off>     Change and confirm the persistent pen hover setting
      --no-reconnect       Do not reconnect after an unexpected disconnect
      --summary-only       Hide raw advertisement/GATT/protocol records
      --log-file <path>    Write the session log to a specific path
      --stdout-only        Do not create a session log file
      --help, -h           Show this help

    By default, logs are written to ./logs and raw events are included.
    """
}

private struct DiagnosticsArgumentError: Error, CustomStringConvertible {
    let description: String

    init(_ description: String) {
        self.description = description
    }
}

private final class DiagnosticsLogger {
    let logFileURL: URL?

    private let fileHandle: FileHandle?
    private let timestampFormatter: ISO8601DateFormatter

    init(options: DiagnosticsOptions) throws {
        let timestampFormatter = ISO8601DateFormatter()
        timestampFormatter.formatOptions = [
            .withInternetDateTime,
            .withFractionalSeconds,
        ]
        timestampFormatter.timeZone = .current
        self.timestampFormatter = timestampFormatter

        guard !options.stdoutOnly else {
            logFileURL = nil
            fileHandle = nil
            return
        }

        let url: URL
        if let path = options.logFile {
            url = URL(fileURLWithPath: path).standardizedFileURL
        } else {
            let directory: URL
            if let configuredDirectory = ProcessInfo.processInfo.environment[
                "TRACE_LOG_DIRECTORY"
            ] {
                directory = URL(fileURLWithPath: configuredDirectory, isDirectory: true)
            } else {
                directory = URL(
                    fileURLWithPath: FileManager.default.currentDirectoryPath,
                    isDirectory: true
                ).appendingPathComponent("logs", isDirectory: true)
            }
            let nameFormatter = DateFormatter()
            nameFormatter.locale = Locale(identifier: "en_US_POSIX")
            nameFormatter.dateFormat = "yyyyMMdd-HHmmss"
            url = directory.appendingPathComponent(
                "neo-diagnostics-\(nameFormatter.string(from: Date())).log"
            )
        }

        try FileManager.default.createDirectory(
            at: url.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        guard FileManager.default.createFile(atPath: url.path, contents: nil) else {
            throw DiagnosticsArgumentError("could not create log file at \(url.path)")
        }

        logFileURL = url
        fileHandle = try FileHandle(forWritingTo: url)
    }

    deinit {
        try? fileHandle?.close()
    }

    func log(_ message: String) {
        let line = "\(timestampFormatter.string(from: Date())) [neo] \(message)\n"
        let data = Data(line.utf8)
        FileHandle.standardOutput.write(data)
        fileHandle?.write(data)
    }
}

private struct StrokeAccumulator {
    let startedAtMilliseconds: UInt64
    var page: PenPageInfo?
    var dots: [PenDotEvent] = []
    var opticalErrorCount = 0
    var errorCodes: [UInt8: Int] = [:]

    mutating func add(_ dot: PenDotEvent) {
        dots.append(dot)
    }

    mutating func add(_ error: PenImageProcessingError) {
        opticalErrorCount += 1
        errorCodes[error.errorCode, default: 0] += 1
    }

    func summary(
        penUp: PenUpEvent,
        maxForce: UInt16?
    ) -> String {
        let duration = max(
            0,
            Int64(penUp.timestampMilliseconds) - Int64(startedAtMilliseconds)
        )
        let reportedRecognition = penUp.totalImageCount == 0
            ? 0
            : Double(penUp.successfulImageCount) / Double(penUp.totalImageCount)
        let observedTotal = dots.count + opticalErrorCount
        let observedRecognition = observedTotal == 0
            ? 0
            : Double(dots.count) / Double(observedTotal)

        var fields = [
            "stroke complete duration=\(duration)ms",
            "dots=\(dots.count)/reported:\(penUp.dotCount)",
            "images=\(penUp.successfulImageCount)/\(penUp.totalImageCount)",
            String(format: "imageRecognition=%.1f%%", reportedRecognition * 100),
            "opticalErrors=\(opticalErrorCount)",
            String(format: "observedRecognition=%.1f%%", observedRecognition * 100),
        ]

        if let page {
            fields.append(
                "page=section:\(page.section)/owner:\(page.owner)"
                    + "/note:\(page.note)/page:\(page.page)"
            )
        } else {
            fields.append("page=unrecognized")
        }

        if !dots.isEmpty {
            let xs = dots.map(\.preciseX)
            let ys = dots.map(\.preciseY)
            let forces = dots.map(\.force).sorted()
            let medianForce = forces[forces.count / 2]
            fields.append(
                String(
                    format: "bounds=(%.2f,%.2f)-(%.2f,%.2f)",
                    xs.min() ?? 0,
                    ys.min() ?? 0,
                    xs.max() ?? 0,
                    ys.max() ?? 0
                )
            )
            fields.append(
                "force=\(forces.first ?? 0)/\(medianForce)/\(forces.last ?? 0)"
            )
            if let maxForce, maxForce > 0 {
                fields.append(
                    String(
                        format: "pressure=%.1f%%/%.1f%%/%.1f%%",
                        Double(forces.first ?? 0) / Double(maxForce) * 100,
                        Double(medianForce) / Double(maxForce) * 100,
                        Double(forces.last ?? 0) / Double(maxForce) * 100
                    )
                )
            }
        }

        if !errorCodes.isEmpty {
            let codes = errorCodes
                .sorted { $0.key < $1.key }
                .map { "\($0.key):\($0.value)" }
                .joined(separator: ",")
            fields.append("errorCodes=\(codes)")
        }

        return fields.joined(separator: " ")
    }
}

private final class DiagnosticsApplication {
    private let options: DiagnosticsOptions
    private let logger: DiagnosticsLogger
    private let transport: CoreBluetoothNeoTransport
    private var didRequestConnection = false
    private var discoveredCount = 0
    private var isFinishing = false
    private var signalSource: DispatchSourceSignal?
    private var timeoutTimer: DispatchSourceTimer?
    private var statusPollTimer: DispatchSourceTimer?
    private var protocolReady = false
    private var didEnableOnlineData = false
    private var hoverSettingRequested = false
    private var latestMaxForce: UInt16?
    private var currentPage: PenPageInfo?
    private var currentStroke: StrokeAccumulator?
    private var hoverEventCount = 0

    init(options: DiagnosticsOptions, logger: DiagnosticsLogger) {
        self.options = options
        self.logger = logger
        transport = CoreBluetoothNeoTransport(
            automaticallyReconnect: options.automaticallyReconnect
        )
    }

    func run() -> Never {
        transport.eventHandler = { [weak self] event in
            self?.handle(event)
        }
        installSignalHandler()
        installTimeout()

        logger.log(
            "session started command=\(options.command.rawValue) "
                + "reconnect=\(options.automaticallyReconnect)"
        )
        if let logFileURL = logger.logFileURL {
            logger.log("session log \(logFileURL.path)")
        }
        if let filter = options.deviceFilter {
            logger.log("device filter \(filter)")
        }
        if let interval = options.statusInterval {
            logger.log("status polling interval \(interval)s")
        }
        if options.enableInput {
            logger.log("online Ncode input registration requested")
        }
        if let hoverSetting = options.hoverSetting {
            logger.log("hover setting requested \(hoverSetting.rawValue)")
        }
        transport.startDiscovery()
        dispatchMain()
    }

    private func installSignalHandler() {
        signal(SIGINT, SIG_IGN)
        let source = DispatchSource.makeSignalSource(signal: SIGINT, queue: .main)
        source.setEventHandler { [weak self] in
            self?.finish(reason: "interrupt", exitCode: 0)
        }
        source.resume()
        signalSource = source
    }

    private func installTimeout() {
        guard let timeout = options.timeout else {
            return
        }
        let timer = DispatchSource.makeTimerSource(queue: .main)
        timer.schedule(deadline: .now() + timeout)
        timer.setEventHandler { [weak self] in
            guard let self else {
                return
            }
            let exitCode: Int32 = self.discoveredCount == 0 ? 2 : 0
            self.finish(reason: "timeout after \(timeout)s", exitCode: exitCode)
        }
        timer.resume()
        timeoutTimer = timer
    }

    private func handle(_ event: NeoTransportEvent) {
        switch event {
        case let .bluetoothState(state):
            logger.log("bluetooth \(state.rawValue)")
        case .discoveryStarted:
            logger.log("discovery started")
        case .discoveryStopped:
            logger.log("discovery stopped")
        case let .deviceDiscovered(device):
            discoveredCount += 1
            logger.log(
                "device found name=\(device.name ?? "unknown") "
                    + "id=\(device.id.uuidString) rssi=\(device.rssi) "
                    + "services=\(device.advertisedServiceUUIDs.joined(separator: ",")) "
                    + "connectable=\(device.isConnectable.map(String.init) ?? "unknown")"
            )
            connectIfNeeded(to: device)
        case let .connectionState(state, deviceID):
            logger.log(
                "connection \(state.rawValue)"
                    + (deviceID.map { " device=\($0.uuidString)" } ?? "")
            )
            if state == .disconnecting
                || state == .disconnected
                || state == .reconnecting
                || state == .failed
            {
                protocolReady = false
                didEnableOnlineData = false
                hoverSettingRequested = false
                currentStroke = nil
                currentPage = nil
                hoverEventCount = 0
                stopStatusPolling()
            }
        case let .gattService(deviceID, uuid):
            logger.log("gatt service device=\(deviceID.uuidString) uuid=\(uuid)")
        case let .gattCharacteristic(deviceID, serviceUUID, uuid, properties):
            logger.log(
                "gatt characteristic device=\(deviceID.uuidString) "
                    + "service=\(serviceUUID) uuid=\(uuid) "
                    + "properties=\(properties.joined(separator: ","))"
            )
        case let .deviceMetadata(key, value):
            logger.log("metadata \(key)=\(value)")
        case let .deviceInfo(info):
            protocolReady = true
            startStatusPollingIfNeeded()
            logger.log(
                "device info model=\(info.modelName) subname=\(info.subName) "
                    + "firmware=\(info.firmwareVersion) "
                    + "protocol=\(info.protocolVersion) type=\(info.deviceType) "
                    + "mac=\(info.macAddress) "
                    + "pressureSensor=\(info.pressureSensorType.map(String.init) ?? "unknown") "
                    + "colorType=\(info.colorTypeID?.hexString ?? "unknown")"
            )
        case let .status(status):
            latestMaxForce = status.maxForce
            logger.log(
                "status battery=\(status.batteryPercent)% "
                    + "charging=\(status.isCharging) locked=\(status.isLocked) "
                    + "storage=\(status.usedStoragePercent)% "
                    + "autoPowerOff=\(status.autoPowerOffMinutes)m "
                    + "autoPowerOn=\(status.autoPowerOnEnabled) "
                    + "capPowerOff=\(status.penCapPowerOffEnabled) "
                    + "hover=\(status.hoverEnabled) beep=\(status.beepEnabled) "
                    + "offline=\(status.offlineDataEnabled) maxForce=\(status.maxForce) "
                    + "sensitivity=\(status.pressureSensitivityStep.map(String.init) ?? "unknown")"
            )
            if status.isLocked {
                logger.log(
                    "pen is password locked; authentication is intentionally not implemented "
                        + "in the observation-only Phase 1 transport"
                )
            } else if options.enableInput, !didEnableOnlineData {
                didEnableOnlineData = true
                transport.enableOnlineData()
            }
            applyHoverSettingIfNeeded(currentStatus: status.hoverEnabled)
        case .onlineDataEnabled:
            logger.log("online Ncode input enabled for all available notes")
        case let .settingChanged(setting):
            logger.log("setting changed type=\(setting.rawValue)")
            transport.requestStatus()
        case let .penDown(event):
            var stroke = StrokeAccumulator(
                startedAtMilliseconds: event.timestampMilliseconds
            )
            stroke.page = currentPage
            currentStroke = stroke
            logger.log(
                "pen down event=\(event.eventCount) tip=\(event.tipType) "
                    + String(format: "color=%08X", event.color)
            )
        case let .penUp(event):
            let summary = currentStroke?.summary(
                penUp: event,
                maxForce: latestMaxForce
            ) ?? "stroke complete without observed pen-down"
            logger.log(summary)
            currentStroke = nil
        case let .pageChanged(page):
            currentPage = page
            currentStroke?.page = page
            logger.log(
                "page section=\(page.section) owner=\(page.owner) "
                    + "note=\(page.note) page=\(page.page)"
            )
        case let .dot(dot):
            guard currentStroke != nil else {
                logHover(
                    source: "out-of-stroke-dot",
                    x: dot.preciseX,
                    y: dot.preciseY,
                    force: dot.force
                )
                break
            }
            currentStroke?.add(dot)
            guard let count = currentStroke?.dots.count,
                  count == 1 || count.isMultiple(of: 20)
            else {
                break
            }
            let pressure = latestMaxForce.flatMap { maxForce -> String? in
                guard maxForce > 0 else {
                    return nil
                }
                return String(
                    format: "%.1f%%",
                    Double(dot.force) / Double(maxForce) * 100
                )
            } ?? "unknown"
            logger.log(
                String(
                    format: "dot #%d x=%.2f y=%.2f force=%d pressure=%@",
                    count,
                    dot.preciseX,
                    dot.preciseY,
                    dot.force,
                    pressure
                )
            )
        case let .imageProcessingError(error):
            currentStroke?.add(error)
            guard let count = currentStroke?.opticalErrorCount,
                  count == 1 || count.isMultiple(of: 50)
            else {
                break
            }
            logger.log(
                "optical errors=\(count) lastCode=\(error.errorCode) "
                    + "force=\(error.force) brightness=\(error.imageBrightness)"
            )
        case let .hover(event):
            logHover(
                source: "explicit-0x6F",
                x: event.preciseX,
                y: event.preciseY,
                force: nil
            )
        case let .lowBattery(percent):
            logger.log("event low battery \(percent)%")
        case let .shutdown(reason):
            logger.log("event shutdown reason=\(reason)")
        case let .protocolMessage(message):
            logger.log("protocol unhandled \(message)")
        case let .notificationBatch(batch):
            guard options.includeRawEvents else {
                return
            }
            logger.log(
                "notification batch id=\(batch.id) bytes=\(batch.byteCount) "
                    + "frames=\(batch.frameCount)"
            )
        case let .raw(rawEvent):
            guard options.includeRawEvents else {
                return
            }
            logger.log(format(rawEvent))
        case let .failure(failure):
            logger.log("error stage=\(failure.stage) message=\(failure.message)")
        }
    }

    private func logHover(
        source: String,
        x: Double,
        y: Double,
        force: UInt16?
    ) {
        hoverEventCount += 1
        guard hoverEventCount == 1 || hoverEventCount.isMultiple(of: 20) else {
            return
        }
        let forceText = force.map(String.init) ?? "unknown"
        let pressure = force.flatMap { force in
            latestMaxForce.flatMap { maxForce -> String? in
                guard maxForce > 0 else {
                    return nil
                }
                return String(
                    format: "%.1f%%",
                    Double(force) / Double(maxForce) * 100
                )
            }
        } ?? "unknown"
        let page = currentPage.map {
            "\($0.section)/\($0.owner)/\($0.note)/\($0.page)"
        } ?? "unknown"
        logger.log(
            String(
                format: [
                    "hover #%d source=%@ x=%.2f y=%.2f",
                    "force=%@ pressure=%@ page=%@",
                ].joined(separator: " "),
                hoverEventCount,
                source,
                x,
                y,
                forceText,
                pressure,
                page
            )
        )
    }

    private func connectIfNeeded(to device: NeoDevice) {
        guard options.command == .observe, !didRequestConnection else {
            return
        }
        if let filter = options.deviceFilter {
            let normalizedFilter = filter.lowercased()
            let matchesID = device.id.uuidString.lowercased() == normalizedFilter
            let matchesName = device.name?
                .lowercased()
                .contains(normalizedFilter) == true
            guard matchesID || matchesName else {
                return
            }
        }

        didRequestConnection = true
        logger.log("connecting device=\(device.id.uuidString)")
        transport.connect(to: device.id)
    }

    private func applyHoverSettingIfNeeded(currentStatus: Bool) {
        guard let desired = options.hoverSetting?.isEnabled else {
            return
        }
        if currentStatus == desired {
            logger.log("hover setting confirmed \(desired ? "on" : "off")")
            return
        }
        guard !hoverSettingRequested else {
            return
        }
        hoverSettingRequested = true
        transport.setHoverEnabled(desired)
    }

    private func startStatusPollingIfNeeded() {
        guard statusPollTimer == nil,
              let interval = options.statusInterval
        else {
            return
        }

        let timer = DispatchSource.makeTimerSource(queue: .main)
        timer.schedule(
            deadline: .now() + interval,
            repeating: interval,
            leeway: .milliseconds(100)
        )
        timer.setEventHandler { [weak self] in
            guard let self, self.protocolReady else {
                return
            }
            self.transport.requestStatus()
        }
        timer.resume()
        statusPollTimer = timer
    }

    private func stopStatusPolling() {
        statusPollTimer?.cancel()
        statusPollTimer = nil
    }

    private func format(_ event: NeoRawEvent) -> String {
        var fields = [
            "raw",
            "layer=\(event.layer.rawValue)",
            "direction=\(event.direction.rawValue)",
        ]
        if let deviceID = event.deviceID {
            fields.append("device=\(deviceID.uuidString)")
        }
        if let serviceUUID = event.serviceUUID {
            fields.append("service=\(serviceUUID)")
        }
        if let characteristicUUID = event.characteristicUUID {
            fields.append("characteristic=\(characteristicUUID)")
        }
        if let bytes = event.bytes {
            fields.append("bytes=\(bytes.hexString)")
        }
        fields.append("detail=\(event.detail)")
        return fields.joined(separator: " ")
    }

    private func finish(reason: String, exitCode: Int32) {
        guard !isFinishing else {
            return
        }
        isFinishing = true
        logger.log("session ending reason=\(reason)")
        timeoutTimer?.cancel()
        stopStatusPolling()
        transport.stopDiscovery()
        transport.disconnect()
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
            self.removePIDFile()
            exit(exitCode)
        }
    }

    private func removePIDFile() {
        guard let pidFile = options.pidFile else {
            return
        }
        do {
            try FileManager.default.removeItem(atPath: pidFile)
        } catch CocoaError.fileNoSuchFile {
            return
        } catch {
            logger.log("error stage=pid-file message=\(error.localizedDescription)")
        }
    }
}

private extension Data {
    var hexString: String {
        map { String(format: "%02X", $0) }.joined(separator: " ")
    }
}

do {
    let options = try DiagnosticsOptions.parse(Array(CommandLine.arguments.dropFirst()))
    if options.showHelp {
        print(DiagnosticsOptions.usage)
        exit(0)
    }
    let logger = try DiagnosticsLogger(options: options)
    if let pidFile = options.pidFile {
        let pidURL = URL(fileURLWithPath: pidFile)
        try FileManager.default.createDirectory(
            at: pidURL.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        try Data("\(getpid())\n".utf8).write(to: pidURL, options: .atomic)
    }
    let application = DiagnosticsApplication(options: options, logger: logger)
    application.run()
} catch {
    fputs("error: \(error)\n\n\(DiagnosticsOptions.usage)\n", stderr)
    exit(64)
}
