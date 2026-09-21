import AppKit
import Foundation
import TraceStrokeProcessing

struct LabConfiguration {
    let logDirectory: URL
    let implementationID: String
    let paperProfile: String
    let replayURL: URL?
    let replaySpeed: Double
    let quitAfterReplay: Bool
    let processingMode: StrokeRenderMode
    let interpolationAlgorithm: GapInterpolationAlgorithm
    let refinementAlgorithm: StrokeRefinementAlgorithm
    let predictionAlgorithm: PredictionAlgorithm
    let rendererMode: LabRendererMode

    static func current() -> LabConfiguration {
        let arguments = Array(CommandLine.arguments.dropFirst())
        let logDirectory = value(after: "--log-directory", in: arguments).map {
            URL(fileURLWithPath: $0, isDirectory: true)
        } ?? URL(
            fileURLWithPath: FileManager.default.currentDirectoryPath,
            isDirectory: true
        ).appendingPathComponent("logs", isDirectory: true)
        return LabConfiguration(
            logDirectory: logDirectory,
            implementationID: value(after: "--implementation", in: arguments)
                ?? "unknown",
            paperProfile: value(after: "--paper-profile", in: arguments)
                ?? "unlabeled",
            replayURL: value(after: "--replay", in: arguments).map {
                URL(fileURLWithPath: $0)
            },
            replaySpeed: Double(value(after: "--replay-speed", in: arguments) ?? "1")
                .flatMap { $0.isFinite && $0 > 0 ? $0 : nil } ?? 1,
            quitAfterReplay: arguments.contains("--quit-after-replay"),
            processingMode: StrokeRenderMode(
                rawValue: value(after: "--processing-mode", in: arguments) ?? ""
            ) ?? .predict,
            interpolationAlgorithm: GapInterpolationAlgorithm(
                rawValue: value(
                    after: "--interpolation-algorithm",
                    in: arguments
                ) ?? ""
            ) ?? .circularArc,
            refinementAlgorithm: StrokeRefinementAlgorithm(
                rawValue: value(
                    after: "--stroke-refinement",
                    in: arguments
                ) ?? ""
            ) ?? .smoothPath,
            predictionAlgorithm: PredictionAlgorithm(
                rawValue: value(
                    after: "--prediction-algorithm",
                    in: arguments
                ) ?? ""
            ) ?? .velocity,
            rendererMode: LabRendererMode(
                rawValue: value(after: "--renderer", in: arguments) ?? ""
            ) ?? .trace
        )
    }

    private static func value(after option: String, in arguments: [String]) -> String? {
        guard let index = arguments.firstIndex(of: option),
              arguments.indices.contains(index + 1)
        else {
            return nil
        }
        return arguments[index + 1]
    }
}

let application = NSApplication.shared
let applicationDelegate = AppDelegate(configuration: .current())
application.delegate = applicationDelegate
let environment = ProcessInfo.processInfo.environment
let isProbe =
    environment["TRACE_LAB_RENDERER_PROBE"] == "1"
    || environment["TRACE_LAB_HOVER_PROBE"] == "1"
application.setActivationPolicy(isProbe ? .accessory : .regular)
application.run()
