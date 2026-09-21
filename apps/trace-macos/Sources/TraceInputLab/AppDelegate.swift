import AppKit
import Darwin

final class AppDelegate: NSObject, NSApplicationDelegate {
    private let configuration: LabConfiguration
    private var window: NSWindow?
    private var model: LabModel?
    private var liveInstanceLock: LiveInstanceLock?

    init(configuration: LabConfiguration) {
        self.configuration = configuration
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
#if DEBUG
        if ProcessInfo.processInfo.environment[
            "TRACE_LAB_RENDERER_PROBE"
        ] == "1" {
            Task { @MainActor in
                do {
                    try await RendererLabProbe.run()
                    print("web canvas probe passed")
                    NSApp.terminate(nil)
                } catch {
                    fputs(
                        "web canvas probe failed: "
                            + error.localizedDescription
                            + "\n",
                        stderr
                    )
                    exit(1)
                }
            }
            return
        }
        if ProcessInfo.processInfo.environment[
            "TRACE_LAB_HOVER_PROBE"
        ] == "1" {
            do {
                try HoverCursorProbe.run()
                NSApp.terminate(nil)
            } catch {
                fputs(
                    "hover-cursor probe failed: "
                        + error.localizedDescription
                        + "\n",
                    stderr
                )
                exit(1)
            }
            return
        }
#endif
        do {
            if configuration.replayURL == nil {
                liveInstanceLock = try LiveInstanceLock()
            }
            let model: LabModel
#if DEBUG
            if ProcessInfo.processInfo.environment[
                "TRACE_LAB_NO_HARDWARE"
            ] == "1" {
                model = try LabModel(
                    configuration: configuration,
                    transport: RendererProbeTransport()
                )
            } else {
                model = try LabModel(configuration: configuration)
            }
#else
            model = try LabModel(configuration: configuration)
#endif
            let viewController = LabViewController(
                model: model,
                showsAnchors: ProcessInfo.processInfo.environment[
                    "TRACE_LAB_SHOW_ANCHORS"
                ] == "1"
            )
            viewController.preferredContentSize =
                LabPaperLayout.preferredWindowContentSize
            let window = NSWindow(
                contentRect: NSRect(
                    origin: .zero,
                    size: LabPaperLayout.preferredWindowContentSize
                ),
                styleMask: [
                    .titled,
                    .closable,
                    .miniaturizable,
                    .resizable,
                ],
                backing: .buffered,
                defer: false
            )
            window.title = "Trace Input Lab"
            window.isRestorable = false
            window.contentViewController = viewController
            window.contentMinSize =
                LabPaperLayout.minimumWindowContentSize
            window.makeKeyAndOrderFront(nil)
            window.setContentSize(
                LabPaperLayout.preferredWindowContentSize
            )
            window.center()

            self.model = model
            self.window = window
            NSApp.activate(ignoringOtherApps: true)
#if DEBUG
            if let snapshotPath = ProcessInfo.processInfo.environment[
                "TRACE_LAB_SNAPSHOT"
            ] {
                DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
                    try? self.writeSnapshot(
                        of: window,
                        to: URL(fileURLWithPath: snapshotPath)
                    )
                    NSApp.terminate(nil)
                }
            }
#endif
        } catch LiveInstanceError.alreadyRunning {
            let currentPID = ProcessInfo.processInfo.processIdentifier
            let existingLab = NSRunningApplication.runningApplications(
                withBundleIdentifier: "com.traceproject.input-lab"
            ).first {
                $0.processIdentifier != currentPID
            }
            if let existingLab {
                existingLab.activate(options: [.activateAllWindows])
            } else {
                let alert = NSAlert()
                alert.alertStyle = .informational
                alert.messageText = "The Neo pen is already in use"
                alert.informativeText =
                    "Quit Trace from its menu-bar item before opening the Input Lab."
                alert.runModal()
            }
            NSApp.terminate(nil)
        } catch {
            let alert = NSAlert()
            alert.alertStyle = .critical
            alert.messageText = "Trace Input Lab could not start"
            alert.informativeText = [
                error.localizedDescription,
                (error as? LocalizedError)?.recoverySuggestion,
            ].compactMap { $0 }.joined(separator: "\n")
            alert.runModal()
            NSApp.terminate(nil)
        }
    }

    func applicationWillTerminate(_ notification: Notification) {
        model?.stop()
    }

    func applicationShouldTerminateAfterLastWindowClosed(
        _ sender: NSApplication
    ) -> Bool {
        true
    }

#if DEBUG
    private func writeSnapshot(
        of window: NSWindow,
        to url: URL
    ) throws {
        guard let contentView = window.contentView,
              let representation = contentView.bitmapImageRepForCachingDisplay(
                  in: contentView.bounds
              )
        else {
            return
        }
        contentView.cacheDisplay(
            in: contentView.bounds,
            to: representation
        )
        if let data = representation.representation(
            using: .png,
            properties: [:]
        ) {
            try data.write(to: url, options: .atomic)
        }
    }
#endif
}

private final class LiveInstanceLock {
    private let fileDescriptor: Int32

    init() throws {
        let fileURL = FileManager.default.temporaryDirectory
            .appendingPathComponent(
                "com.traceproject.pen.live.lock"
            )
        let descriptor = Darwin.open(
            fileURL.path,
            O_CREAT | O_RDWR,
            S_IRUSR | S_IWUSR
        )
        guard descriptor >= 0 else {
            throw CocoaError(.fileWriteUnknown)
        }
        guard flock(descriptor, LOCK_EX | LOCK_NB) == 0 else {
            Darwin.close(descriptor)
            if errno == EWOULDBLOCK {
                throw LiveInstanceError.alreadyRunning
            }
            throw CocoaError(.fileWriteUnknown)
        }
        fileDescriptor = descriptor
    }

    deinit {
        flock(fileDescriptor, LOCK_UN)
        Darwin.close(fileDescriptor)
    }
}

private enum LiveInstanceError: Error {
    case alreadyRunning
}
