import AppKit
import Darwin

#if DEBUG
let environment = ProcessInfo.processInfo.environment
if environment["TRACE_HARDWARE_FREE_SETUP_SNAPSHOT"] != nil
    || environment["TRACE_HARDWARE_FREE_CALIBRATION_SNAPSHOT"] != nil
    || environment["TRACE_HARDWARE_FREE_TOOLBAR_SNAPSHOT"] != nil
{
    _ = NSApplication.shared
    do {
        try MainActor.assumeIsolated {
            if let path = environment[
                "TRACE_HARDWARE_FREE_TOOLBAR_SNAPSHOT"
            ] {
                try TraceRetainedInkProbe.writeToolbarSnapshot(
                    to: URL(fileURLWithPath: path)
                )
            }
            try TraceRetainedInkProbe.writeOnboardingSnapshots(
                setupURL: environment[
                    "TRACE_HARDWARE_FREE_SETUP_SNAPSHOT"
                ].map { URL(fileURLWithPath: $0) },
                calibrationURL: environment[
                    "TRACE_HARDWARE_FREE_CALIBRATION_SNAPSHOT"
                ].map { URL(fileURLWithPath: $0) }
            )
        }
        exit(0)
    } catch {
        fputs("onboarding snapshot failed: \(error)\n", stderr)
        exit(1)
    }
}
if ProcessInfo.processInfo.environment[
    "TRACE_ONBOARDING_PROBE"
] == "1" {
    _ = NSApplication.shared
    do {
        try MainActor.assumeIsolated {
            try TraceRetainedInkProbe.runOnboardingChecks()
        }
        print("onboarding probe passed")
        exit(0)
    } catch {
        fputs("onboarding probe failed: \(error)\n", stderr)
        exit(1)
    }
}
if ProcessInfo.processInfo.environment[
    "TRACE_GLOBAL_SHORTCUTS_PROBE"
] == "1" {
    _ = NSApplication.shared
    do {
        try MainActor.assumeIsolated {
            try TraceRetainedInkProbe.runGlobalShortcutChecks()
        }
        print("global shortcuts probe passed")
        exit(0)
    } catch {
        fputs("global shortcuts probe failed: \(error)\n", stderr)
        exit(1)
    }
}
if ProcessInfo.processInfo.environment[
    "TRACE_OPEN_FILE_PROBE"
] == "1" {
    _ = NSApplication.shared
    do {
        try MainActor.assumeIsolated {
            try TraceRetainedInkProbe.runOpenFileChecks()
        }
        print("open-file probe passed")
        exit(0)
    } catch {
        fputs("open-file probe failed: \(error)\n", stderr)
        exit(1)
    }
}
if ProcessInfo.processInfo.environment[
    "TRACE_HARDWARE_FREE_PROBE"
] == "1" {
    _ = NSApplication.shared
    do {
        try MainActor.assumeIsolated {
            try TraceRetainedInkProbe.runHardwareFreeChecks()
        }
        print("hardware-free probe passed")
        exit(0)
    } catch {
        fputs("hardware-free probe failed: \(error)\n", stderr)
        exit(1)
    }
}
if ProcessInfo.processInfo.environment[
    "TRACE_GRID_SPACING_BASELINE_PROBE"
] == "1" {
    _ = NSApplication.shared
    do {
        try MainActor.assumeIsolated {
            try TraceRetainedInkProbe.runGridSpacingBaselineCheck()
        }
        print("grid spacing baseline probe passed")
        exit(0)
    } catch {
        fputs("grid spacing baseline probe failed: \(error)\n", stderr)
        exit(1)
    }
}
#endif

MainActor.assumeIsolated {
    let application = NSApplication.shared
    let delegate = TraceAppDelegate()
    application.delegate = delegate
    application.setActivationPolicy(.accessory)
    application.run()
}
