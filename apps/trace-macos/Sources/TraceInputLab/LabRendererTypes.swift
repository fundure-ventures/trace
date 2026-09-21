import AppKit
import NeoInput
import TraceCalibration
import TraceGeometry
import TraceStrokeProcessing

enum LabMouseIdentifier {
    static let base: UInt64 = 1 << 62
}

enum LabRendererMode: String, CaseIterable, Hashable {
    case trace
    case paperKit = "paperkit"
    case tldraw

    var title: String {
        switch self {
        case .trace:
            return "Trace"
        case .paperKit:
            return "PaperKit"
        case .tldraw:
            return "tldraw"
        }
    }

    var supportsTraceProcessingForMouse: Bool {
        self != .paperKit
    }

    func supportsTraceProcessing(
        penInputReady: Bool,
        isReplay: Bool
    ) -> Bool {
        supportsTraceProcessingForMouse
            || penInputReady
            || isReplay
    }

    func prepare(_ update: LabRendererUpdate) -> LabRendererUpdate {
        guard self == .tldraw else {
            return update
        }
        return LabRendererUpdate(
            strokeID: update.strokeID,
            committed: update.committed,
            predicted:
                update.strokeID >= LabMouseIdentifier.base
                    ? Array(update.predicted.prefix(1))
                    : update.predicted,
            replacement: nil,
            sourceSamples: update.sourceSamples,
            refinementReadyUptimeNanoseconds: nil,
            isFinal: update.isFinal
        )
    }
}

struct LabRenderPoint {
    let render: RenderPoint
    let normalized: UnitPoint
}

struct LabRendererUpdate {
    let strokeID: UInt64
    let committed: [LabRenderPoint]
    let predicted: [LabRenderPoint]
    let replacement: [LabRenderPoint]?
    let sourceSamples: [RawPenSample]
    let refinementReadyUptimeNanoseconds: UInt64?
    let isFinal: Bool
}

struct LabMouseSample {
    let point: UnitPoint
    let pressure: Double?
    let wallClockMilliseconds: UInt64
    let uptimeNanoseconds: UInt64
}

struct LabRendererPresentation: Equatable {
    let calibration: CalibratedSurface?
    let calibrationActive: Bool
    let pagePriming: Bool
    let calibrationCorner: CalibrationCorner?
    let message: String?
}

enum LabMouseStrokeEvent {
    case began(LabMouseSample)
    case moved(LabMouseSample)
    case ended(LabMouseSample)
}

protocol LabRendererSurface: AnyObject {
    var view: NSView { get }
    var childViewControllers: [NSViewController] { get }
    var onSamplesRendered: (([RawPenSample], UInt64) -> Void)? { get set }
    var unavailableReason: String? { get }
    var isReadyForInput: Bool { get }
    var pendingRenderWorkCount: Int { get }

    func updatePresentation(_ presentation: LabRendererPresentation)
    func apply(_ update: LabRendererUpdate)
    func clear()
    func activate()
    func deactivate()
}

extension LabRendererSurface {
    var isReadyForInput: Bool { true }
    var pendingRenderWorkCount: Int { 0 }
}
