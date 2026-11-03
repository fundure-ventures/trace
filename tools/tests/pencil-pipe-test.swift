import Foundation

enum SidecarCaptureProbeError: Error {
    case failed(String)
}

@main
enum PencilPipeTest {
    static func main() throws {
        let helper = Bundle.main.bundleURL.appendingPathComponent(
            "Contents/Helpers/PencilTelemetry.app/Contents/MacOS/trace-pencil-telemetry"
        )
        try FileManager.default.createDirectory(
            at: helper.deletingLastPathComponent(), withIntermediateDirectories: true
        )
        // Close stdout while still alive so termination cannot mask an EOF spin.
        let script = """
        #!/bin/sh
        printf '%s\\n' '{"event":"ready","name":"Test iPad"}'
        printf '%s' '{"event":"state","charging":false,'
        printf '%s\\n' '"baseline":false,"appOpen":true}'
        exec 1>&-
        sleep 2
        """
        try Data(script.utf8).write(to: helper)
        try FileManager.default.setAttributes(
            [.posixPermissions: 0o755], ofItemAtPath: helper.path
        )

        let monitor = PencilTelemetryMonitor()
        defer { monitor.stop() }
        var ready = 0
        var states = 0
        var errors = 0
        monitor.onReady = { name in
            if name == "Test iPad" { ready += 1 }
        }
        monitor.onState = { charging, baseline, appOpen in
            if !charging && !baseline && appOpen == true { states += 1 }
        }
        monitor.onError = { _ in errors += 1 }
        try monitor.start(arguments: [])
        RunLoop.main.run(until: Date().addingTimeInterval(0.5))

        guard ready == 1, states == 1, errors == 0 else {
            fatalError("Expected queued helper events to be delivered once before EOF")
        }
        guard let pipe = Mirror(reflecting: monitor).children.first(
            where: { $0.label == "output" }
        )?.value as? Pipe else {
            fatalError("Expected the monitor's output pipe")
        }
        guard pipe.fileHandleForReading.readabilityHandler == nil else {
            fatalError("EOF must unregister the reader instead of repeatedly queuing empty callbacks")
        }
        print("Pencil pipe EOF regression passed")
    }
}
