#if DEBUG
import AppKit
import CoreGraphics
import WebKit

/// DEBUG-only diagnostics for Sidecar + Apple Pencil input and display changes.
/// Enabled with TRACE_SIDECAR_INPUT_PROBE=1; writes to /tmp/trace-sidecar-probe.log.
public final class SidecarInputProbe: NSObject, WKScriptMessageHandler {
    public static let shared = SidecarInputProbe()
    public static let logPath = "/tmp/trace-sidecar-probe.log"

    public let isEnabled =
        ProcessInfo.processInfo.environment["TRACE_SIDECAR_INPUT_PROBE"] == "1"
        || CommandLine.arguments.contains("--sidecar-probe")

    private var monitors: [Any] = []
    private var observers: [NSObjectProtocol] = []
    private var probedViews = NSHashTable<NSView>.weakObjects()
    private var fileHandle: FileHandle?
    private let timestamp: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "HH:mm:ss.SSS"
        return formatter
    }()

    private override init() {
        fileHandle = nil
        super.init()
    }

    public func log(_ source: String, _ message: String) {
        guard isEnabled else { return }
        let line = "\(timestamp.string(from: Date())) [\(source)] \(message)\n"
        do {
            try fileHandle?.write(contentsOf: Data(line.utf8))
        } catch {
            fputs("Sidecar probe write failed: \(error.localizedDescription)\n", stderr)
        }
    }

    public func start() throws {
        guard isEnabled, monitors.isEmpty else { return }
        try Data().write(to: URL(fileURLWithPath: Self.logPath), options: .atomic)
        fileHandle = try FileHandle(forWritingTo: URL(fileURLWithPath: Self.logPath))
        log("probe", "started pid=\(ProcessInfo.processInfo.processIdentifier)")
        logScreens(reason: "launch")

        let mask: NSEvent.EventTypeMask = [
            .leftMouseDown, .leftMouseUp, .leftMouseDragged, .mouseMoved,
            .rightMouseDown, .rightMouseUp,
            .otherMouseDown, .otherMouseUp,
            .tabletPoint, .tabletProximity,
            .pressure, .directTouch, .gesture,
            .magnify, .rotate, .swipe, .smartMagnify,
            .beginGesture, .endGesture,
        ]
        if let local = NSEvent.addLocalMonitorForEvents(
            matching: mask,
            handler: { [weak self] event in
                self?.log("local", Self.describe(event))
                return event
            }
        ) {
            monitors.append(local)
        } else {
            log("probe", "local event monitor unavailable")
        }
        if let global = NSEvent.addGlobalMonitorForEvents(
            matching: mask,
            handler: { [weak self] event in
                self?.log("global", Self.describe(event))
            }
        ) {
            monitors.append(global)
        } else {
            log("probe", "global event monitor unavailable; local probes remain active")
        }

        let center = NotificationCenter.default
        observers.append(
            center.addObserver(
                forName: NSApplication.didChangeScreenParametersNotification,
                object: nil,
                queue: .main
            ) { [weak self] _ in
                self?.logScreens(reason: "screenParametersChanged")
            }
        )
        observers.append(
            center.addObserver(
                forName: NSWindow.didChangeScreenNotification,
                object: nil,
                queue: .main
            ) { [weak self] note in
                guard let window = note.object as? NSWindow else { return }
                self?.log(
                    "window",
                    "\(type(of: window)) moved to screen=\(window.screen?.localizedName ?? "nil")"
                )
            }
        )
        observers.append(
            center.addObserver(
                forName: NSWindow.didBecomeKeyNotification,
                object: nil,
                queue: .main
            ) { [weak self] note in
                guard let window = note.object as? NSWindow else { return }
                self?.attachRecognizer(to: window)
            }
        )
        let registration = CGDisplayRegisterReconfigurationCallback(
            { display, flags, _ in
                guard !flags.contains(.beginConfigurationFlag) else { return }
                let detail =
                    "id=\(display) flags=\(flags.rawValue) "
                        + "added=\(flags.contains(.addFlag)) "
                        + "removed=\(flags.contains(.removeFlag)) "
                        + "mirror=\(flags.contains(.mirrorFlag)) "
                        + "builtin=\(CGDisplayIsBuiltin(display) != 0) "
                        + "vendor=\(CGDisplayVendorNumber(display)) "
                        + "model=\(CGDisplayModelNumber(display)) "
                        + "serial=\(CGDisplaySerialNumber(display))"
                DispatchQueue.main.async {
                    SidecarInputProbe.shared.log("cgdisplay", detail)
                }
            },
            nil
        )
        if registration != .success {
            log("probe", "CG display callback unavailable: \(registration.rawValue)")
        }
        NSApp.windows.forEach(attachRecognizer(to:))
    }

    public func attachRecognizer(to window: NSWindow) {
        guard isEnabled, let view = window.contentView,
            !probedViews.contains(view)
        else { return }
        probedViews.add(view)
        view.addGestureRecognizer(
            SidecarProbeGestureRecognizer(windowName: "\(type(of: window))")
        )
        log("gesture", "attached to \(type(of: window))")
    }

    private func logScreens(reason: String) {
        log("screens", "reason=\(reason) count=\(NSScreen.screens.count)")
        for screen in NSScreen.screens {
            let id = (screen.deviceDescription[
                NSDeviceDescriptionKey("NSScreenNumber")
            ] as? NSNumber)?.uint32Value ?? 0
            log(
                "screens",
                "name=\"\(screen.localizedName)\" id=\(id) "
                    + "builtin=\(CGDisplayIsBuiltin(id) != 0) "
                    + "vendor=\(CGDisplayVendorNumber(id)) "
                    + "model=\(CGDisplayModelNumber(id)) "
                    + "serial=\(CGDisplaySerialNumber(id)) "
                    + "frame=\(NSStringFromRect(screen.frame)) "
                    + "scale=\(screen.backingScaleFactor) "
                    + "main=\(screen == NSScreen.main)"
            )
        }
    }

    public static func describe(_ event: NSEvent) -> String {
        var fields = [
            "type=\(event.type.rawValue)",
            "window=\(event.window.map { "\(type(of: $0))" } ?? "nil")",
            "screen=\(event.window?.screen?.localizedName ?? "nil")",
            "x=\(Int(event.locationInWindow.x))",
            "y=\(Int(event.locationInWindow.y))",
        ]
        switch event.type {
        case .leftMouseDown, .leftMouseUp, .leftMouseDragged,
            .rightMouseDown, .rightMouseUp, .otherMouseDown, .otherMouseUp,
            .tabletPoint:
            fields.append("subtype=\(event.subtype.rawValue)")
            fields.append("pressure=\(event.pressure)")
        case .pressure:
            fields.append("pressure=\(event.pressure) stage=\(event.stage)")
        case .directTouch:
            let touches = event.allTouches()
            fields.append("touches=\(touches.count)")
            fields.append(
                contentsOf: touches.map { "touchType=\($0.type.rawValue) phase=\($0.phase.rawValue)" }
            )
        default:
            break
        }
        if event.type == .tabletProximity {
            fields.append("proximity=\(event.isEnteringProximity ? "enter" : "exit")")
        }
        if event.type == .tabletProximity || event.type == .tabletPoint
            || ([.leftMouseDown, .leftMouseUp, .leftMouseDragged].contains(event.type)
                && event.subtype == .tabletPoint)
        {
            fields.append(contentsOf: [
                "deviceID=\(event.deviceID)",
                "pointingDeviceID=\(event.pointingDeviceID)",
                "vendorID=\(event.vendorID)",
                "tabletID=\(event.tabletID)",
                "uniqueID=\(event.uniqueID)",
                "tiltX=\(event.tilt.x)",
                "tiltY=\(event.tilt.y)",
                "pointingDeviceType=\(event.pointingDeviceType.rawValue)",
            ])
        }
        return fields.joined(separator: " ")
    }

    public func installWebProbe(in configuration: WKWebViewConfiguration) {
        guard isEnabled else { return }
        configuration.userContentController.add(self, name: "sidecarProbe")
        configuration.userContentController.addUserScript(WKUserScript(
            source: """
            for (const type of [
              'pointerover', 'pointerenter', 'pointerdown', 'pointermove',
              'pointerup', 'pointercancel', 'pointerout', 'pointerleave'
            ]) {
              window.addEventListener(type, event => {
                const fields = { eventType: event.type };
                for (const key of [
                  'pointerType', 'pointerId', 'isPrimary', 'pressure',
                  'tangentialPressure', 'tiltX', 'tiltY', 'twist',
                  'width', 'height', 'buttons', 'clientX', 'clientY'
                ]) fields[key] = event[key];
                window.webkit.messageHandlers.sidecarProbe.postMessage(fields);
              }, { capture: true, passive: true });
            }
            window.webkit.messageHandlers.sidecarProbe.postMessage({eventType: 'installed'});
            """,
            injectionTime: .atDocumentStart,
            forMainFrameOnly: true
        ))
    }

    public func userContentController(
        _ userContentController: WKUserContentController,
        didReceive message: WKScriptMessage
    ) {
        guard let fields = message.body as? [String: Any] else { return }
        log("web", fields.keys.sorted().map {
            "\($0)=\(String(describing: fields[$0]!))"
        }.joined(separator: " "))
    }

    @objc public func markStep(_ sender: NSMenuItem) {
        log("marker", sender.title)
    }
}

/// Never recognizes; only observes what AppKit routes to gesture recognizers.
private final class SidecarProbeGestureRecognizer: NSGestureRecognizer {
    private let windowName: String

    init(windowName: String) {
        self.windowName = windowName
        super.init(target: nil, action: nil)
        delaysPrimaryMouseButtonEvents = false
        delaysSecondaryMouseButtonEvents = false
        delaysOtherMouseButtonEvents = false
        delaysKeyEvents = false
        delaysMagnificationEvents = false
        delaysRotationEvents = false
        allowedTouchTypes = [.direct, .indirect]
    }

    required init?(coder: NSCoder) {
        nil
    }

    override func canPrevent(_ preventedGestureRecognizer: NSGestureRecognizer) -> Bool {
        false
    }

    override func canBePrevented(by preventingGestureRecognizer: NSGestureRecognizer) -> Bool {
        false
    }

    private func record(_ name: String, _ event: NSEvent) {
        SidecarInputProbe.shared.log(
            "gesture",
            "\(name) host=\(windowName) \(SidecarInputProbe.describe(event))"
        )
    }

    override func mouseDown(with event: NSEvent) { record("mouseDown", event) }
    override func mouseDragged(with event: NSEvent) { record("mouseDragged", event) }
    override func mouseUp(with event: NSEvent) { record("mouseUp", event) }
    override func tabletPoint(with event: NSEvent) { record("tabletPoint", event) }
    override func pressureChange(with event: NSEvent) { record("pressure", event) }
    override func magnify(with event: NSEvent) { record("magnify", event) }
    override func touchesBegan(with event: NSEvent) { record("touchesBegan", event) }
    override func touchesMoved(with event: NSEvent) { record("touchesMoved", event) }
    override func touchesEnded(with event: NSEvent) { record("touchesEnded", event) }
    override func touchesCancelled(with event: NSEvent) { record("touchesCancelled", event) }
}
#endif
