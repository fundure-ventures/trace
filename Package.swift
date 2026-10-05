// swift-tools-version: 5.10

import PackageDescription

let package = Package(
    name: "Trace",
    platforms: [
        .macOS(.v13),
    ],
    products: [
        .library(name: "NeoTransport", targets: ["NeoTransport"]),
        .library(name: "NeoInput", targets: ["NeoInput"]),
        .library(name: "TraceMetrics", targets: ["TraceMetrics"]),
        .library(name: "TraceGeometry", targets: ["TraceGeometry"]),
        .library(name: "TraceCalibration", targets: ["TraceCalibration"]),
        .library(name: "TraceLabReplay", targets: ["TraceLabReplay"]),
        .library(name: "TraceAppCore", targets: ["TraceAppCore"]),
        .library(name: "TraceStrokeProcessing", targets: ["TraceStrokeProcessing"]),
        .library(name: "TraceVoice", targets: ["TraceVoice"]),
        .library(name: "TraceLogging", targets: ["TraceLogging"]),
        .library(name: "TraceCLICore", targets: ["TraceCLICore"]),
        .executable(name: "trace-logging-tests", targets: ["TraceLoggingTests"]),
        .executable(name: "trace-cli-core-tests", targets: ["TraceCLICoreTests"]),
        .executable(name: "traceapp", targets: ["TraceCLI"]),
        .executable(name: "trace-neo-diagnostics", targets: ["TraceNeoDiagnostics"]),
        .executable(name: "trace", targets: ["TraceApp"]),
        .executable(name: "trace-input-lab", targets: ["TraceInputLab"]),
        .executable(name: "neo-transport-tests", targets: ["NeoTransportTests"]),
        .executable(name: "neo-input-tests", targets: ["NeoInputTests"]),
        .executable(name: "trace-metrics-tests", targets: ["TraceMetricsTests"]),
        .executable(name: "trace-geometry-tests", targets: ["TraceGeometryTests"]),
        .executable(name: "trace-calibration-tests", targets: ["TraceCalibrationTests"]),
        .executable(
            name: "trace-stroke-processing-tests",
            targets: ["TraceStrokeProcessingTests"]
        ),
        .executable(
            name: "trace-lab-replay-tests",
            targets: ["TraceLabReplayTests"]
        ),
        .executable(
            name: "trace-app-core-tests",
            targets: ["TraceAppCoreTests"]
        ),
        .executable(
            name: "trace-voice-tests",
            targets: ["TraceVoiceTests"]
        ),
        .executable(name: "trace-stroke-bench", targets: ["TraceStrokeBench"]),
    ],
    dependencies: [
        .package(
            url: "https://github.com/sindresorhus/KeyboardShortcuts",
            exact: "3.1.0"
        ),
    ],
    targets: [
        .target(
            name: "TraceCLICore",
            path: "packages/cli-core/Sources/TraceCLICore"
        ),
        .executableTarget(
            name: "TraceCLICoreTests",
            dependencies: ["TraceCLICore"],
            path: "packages/cli-core/Tests/TraceCLICoreTests"
        ),
        .executableTarget(
            name: "TraceCLI",
            dependencies: ["TraceCLICore"],
            path: "apps/trace-cli",
            linkerSettings: [.linkedFramework("AppKit")]
        ),
        .target(
            name: "TraceLogging",
            path: "packages/logging/Sources/TraceLogging"
        ),
        .executableTarget(
            name: "TraceLoggingTests",
            dependencies: ["TraceLogging"],
            path: "packages/logging/Tests/TraceLoggingTests"
        ),
        .target(
            name: "NeoTransport",
            path: "packages/neo-transport/Sources/NeoTransport",
            linkerSettings: [
                .linkedFramework("CoreBluetooth"),
            ]
        ),
        .target(
            name: "NeoInput",
            dependencies: ["NeoTransport"],
            path: "packages/neo-input/Sources/NeoInput"
        ),
        .target(
            name: "TraceMetrics",
            dependencies: ["NeoInput"],
            path: "packages/trace-metrics/Sources/TraceMetrics"
        ),
        .target(
            name: "TraceGeometry",
            path: "packages/geometry/Sources/TraceGeometry"
        ),
        .target(
            name: "TraceCalibration",
            dependencies: ["NeoInput", "TraceGeometry"],
            path: "packages/calibration/Sources/TraceCalibration"
        ),
        .target(
            name: "TraceStrokeProcessing",
            dependencies: ["NeoInput"],
            path: "packages/stroke-processing/Sources/TraceStrokeProcessing"
        ),
        .target(
            name: "TraceLabReplay",
            dependencies: ["NeoInput"],
            path: "packages/lab-replay/Sources/TraceLabReplay"
        ),
        .target(
            name: "TraceAppCore",
            path: "packages/app-core/Sources/TraceAppCore"
        ),
        .target(
            name: "TraceVoice",
            path: "packages/voice/Sources/TraceVoice",
            linkerSettings: [
                .linkedFramework("AVFoundation"),
                .linkedFramework("Security"),
            ]
        ),
        .executableTarget(
            name: "TraceNeoDiagnostics",
            dependencies: ["NeoTransport"],
            path: "apps/diagnostics/Sources/TraceNeoDiagnostics",
            linkerSettings: [
                .unsafeFlags([
                    "-Xlinker", "-sectcreate",
                    "-Xlinker", "__TEXT",
                    "-Xlinker", "__info_plist",
                    "-Xlinker", "apps/diagnostics/Info.plist",
                ]),
            ]
        ),
        .executableTarget(
            name: "TraceInputLab",
            dependencies: [
                "NeoTransport",
                "NeoInput",
                "TraceCalibration",
                "TraceGeometry",
                "TraceLabReplay",
                "TraceMetrics",
                "TraceStrokeProcessing",
            ],
            path: "apps/trace-macos/Sources/TraceInputLab",
            linkerSettings: [
                .linkedFramework("AppKit"),
                .linkedFramework("WebKit"),
                .unsafeFlags([
                    "-Xlinker", "-sectcreate",
                    "-Xlinker", "__TEXT",
                    "-Xlinker", "__info_plist",
                    "-Xlinker", "apps/trace-macos/Info.plist",
                ]),
            ]
        ),
        .executableTarget(
            name: "TraceApp",
            dependencies: [
                .product(
                    name: "KeyboardShortcuts",
                    package: "KeyboardShortcuts"
                ),
                "NeoTransport",
                "NeoInput",
                "TraceAppCore",
                "TraceCalibration",
                "TraceGeometry",
                "TraceStrokeProcessing",
                "TraceVoice",
                "TraceLogging",
                "TraceCLICore",
            ],
            path: "apps/trace-macos/Sources/TraceApp",
            linkerSettings: [
                .linkedFramework("AppKit"),
                .linkedFramework("IOKit"),
                .linkedFramework("MetalKit"),
                .linkedFramework("ScreenCaptureKit"),
                .linkedFramework("WebKit"),
                .unsafeFlags([
                    "-Xlinker", "-sectcreate",
                    "-Xlinker", "__TEXT",
                    "-Xlinker", "__info_plist",
                    "-Xlinker", "apps/trace-macos/Trace-Info.plist",
                ]),
            ]
        ),
        .executableTarget(
            name: "NeoTransportTests",
            dependencies: ["NeoTransport"],
            path: "packages/neo-transport/Tests/NeoTransportTests"
        ),
        .executableTarget(
            name: "NeoInputTests",
            dependencies: ["NeoInput", "NeoTransport"],
            path: "packages/neo-input/Tests/NeoInputTests"
        ),
        .executableTarget(
            name: "TraceMetricsTests",
            dependencies: ["NeoInput", "NeoTransport", "TraceMetrics"],
            path: "packages/trace-metrics/Tests/TraceMetricsTests"
        ),
        .executableTarget(
            name: "TraceGeometryTests",
            dependencies: ["TraceGeometry"],
            path: "packages/geometry/Tests/TraceGeometryTests"
        ),
        .executableTarget(
            name: "TraceCalibrationTests",
            dependencies: [
                "NeoInput",
                "NeoTransport",
                "TraceCalibration",
                "TraceGeometry",
            ],
            path: "packages/calibration/Tests/TraceCalibrationTests"
        ),
        .executableTarget(
            name: "TraceStrokeProcessingTests",
            dependencies: ["NeoInput", "TraceStrokeProcessing"],
            path: "packages/stroke-processing/Tests/TraceStrokeProcessingTests"
        ),
        .executableTarget(
            name: "TraceLabReplayTests",
            dependencies: ["NeoInput", "TraceLabReplay"],
            path: "packages/lab-replay/Tests/TraceLabReplayTests"
        ),
        .executableTarget(
            name: "TraceAppCoreTests",
            dependencies: ["TraceAppCore"],
            path: "packages/app-core/Tests/TraceAppCoreTests"
        ),
        .executableTarget(
            name: "TraceVoiceTests",
            dependencies: ["TraceVoice"],
            path: "packages/voice/Tests/TraceVoiceTests"
        ),
        .executableTarget(
            name: "TraceStrokeBench",
            dependencies: ["NeoInput", "TraceStrokeProcessing"],
            path: "tools/stroke-bench/Sources/TraceStrokeBench"
        ),
    ],
    swiftLanguageVersions: [.v5]
)
