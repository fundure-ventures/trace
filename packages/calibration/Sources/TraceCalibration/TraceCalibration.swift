import Foundation
import NeoInput
import TraceGeometry

public enum CalibrationCorner: Int, CaseIterable, Codable, Equatable, Sendable {
    case topLeft
    case topRight
    case bottomRight
    case bottomLeft

    public var displayName: String {
        switch self {
        case .topLeft:
            return "top-left"
        case .topRight:
            return "top-right"
        case .bottomRight:
            return "bottom-right"
        case .bottomLeft:
            return "bottom-left"
        }
    }
}

public enum CalibrationRetryReason: Equatable, Sendable {
    case noRecognizedSamples
    case differentPage
    case degenerateGeometry
}

public struct CalibratedSurface: Codable, Equatable, Sendable {
    public let page: PenPageID
    public let calibration: NcodeSurfaceCalibration

    public init(page: PenPageID, calibration: NcodeSurfaceCalibration) {
        self.page = page
        self.calibration = calibration
    }

    public func isCalibrationCompatible(
        with candidate: PenPageID?
    ) -> Bool {
        guard let candidate else {
            return false
        }
        return page.section == candidate.section
            && page.owner == candidate.owner
            && page.note == candidate.note
    }
}

public enum CalibrationUpdate: Equatable, Sendable {
    case pageRegistered(page: PenPageID, next: CalibrationCorner)
    case retryPageRegistration
    case captured(
        corner: CalibrationCorner,
        point: NcodePoint,
        next: CalibrationCorner
    )
    case completed(CalibratedSurface)
    case retry(corner: CalibrationCorner, reason: CalibrationRetryReason)
}

public final class SurfaceCalibrationSession {
    public private(set) var isAwaitingPageRegistration = true

    public var currentCorner: CalibrationCorner? {
        guard !isAwaitingPageRegistration else {
            return nil
        }
        guard capturedCorners.count < CalibrationCorner.allCases.count else {
            return nil
        }
        return CalibrationCorner.allCases[capturedCorners.count]
    }

    private var capturedCorners: [NcodePoint] = []
    private var page: PenPageID?
    private var pageCandidate: PenPageID?
    private var activeStrokeID: UInt64?
    private var activeSamples: [RawPenSample] = []

    public init() {}

    public func receive(_ event: NeoInputEvent) -> CalibrationUpdate? {
        switch event {
        case let .strokeStarted(stroke):
            activeStrokeID = stroke.strokeID
            activeSamples.removeAll(keepingCapacity: true)
            return nil
        case let .sample(sample):
            guard sample.strokeID == activeStrokeID else {
                return nil
            }
            activeSamples.append(sample)
            pageCandidate = pageCandidate ?? sample.page
            return nil
        case let .pageChanged(page):
            pageCandidate = page
            return nil
        case let .strokeCompleted(stroke):
            guard stroke.strokeID == activeStrokeID else {
                return nil
            }
            defer {
                activeStrokeID = nil
                activeSamples.removeAll(keepingCapacity: true)
            }
            if isAwaitingPageRegistration {
                return finishPageRegistration()
            }
            guard let corner = currentCorner else {
                return nil
            }
            return finishCorner(corner)
        default:
            return nil
        }
    }

    public func reset() {
        capturedCorners.removeAll(keepingCapacity: true)
        page = nil
        pageCandidate = nil
        isAwaitingPageRegistration = true
        activeStrokeID = nil
        activeSamples.removeAll(keepingCapacity: true)
    }

    private func finishPageRegistration() -> CalibrationUpdate {
        guard let pageCandidate else {
            return .retryPageRegistration
        }
        page = pageCandidate
        isAwaitingPageRegistration = false
        return .pageRegistered(page: pageCandidate, next: .topLeft)
    }

    private func finishCorner(_ corner: CalibrationCorner) -> CalibrationUpdate {
        guard !activeSamples.isEmpty else {
            return .retry(corner: corner, reason: .noRecognizedSamples)
        }
        let samplePages = Set(activeSamples.compactMap(\.page))
        guard samplePages.count == 1, let samplePage = samplePages.first else {
            return .retry(corner: corner, reason: .noRecognizedSamples)
        }
        if let page, page != samplePage {
            return .retry(corner: corner, reason: .differentPage)
        }

        page = samplePage
        let point = NcodePoint(
            x: median(activeSamples.map(\.x)),
            y: median(activeSamples.map(\.y))
        )
        capturedCorners.append(point)

        guard capturedCorners.count == CalibrationCorner.allCases.count else {
            return .captured(
                corner: corner,
                point: point,
                next: CalibrationCorner.allCases[capturedCorners.count]
            )
        }

        do {
            return .completed(
                CalibratedSurface(
                    page: samplePage,
                    calibration: try NcodeSurfaceCalibration(corners: capturedCorners)
                )
            )
        } catch {
            capturedCorners.removeAll(keepingCapacity: true)
            page = nil
            pageCandidate = nil
            isAwaitingPageRegistration = true
            return .retry(corner: .topLeft, reason: .degenerateGeometry)
        }
    }

    private func median(_ values: [Double]) -> Double {
        let sorted = values.sorted()
        let middle = sorted.count / 2
        if sorted.count.isMultiple(of: 2) {
            return (sorted[middle - 1] + sorted[middle]) / 2
        }
        return sorted[middle]
    }
}

public final class LocalCalibrationStore {
    public let fileURL: URL

    public init(fileURL: URL) {
        self.fileURL = fileURL
    }

    public func load() throws -> CalibratedSurface? {
        guard FileManager.default.fileExists(atPath: fileURL.path) else {
            return nil
        }
        return try JSONDecoder().decode(
            CalibratedSurface.self,
            from: Data(contentsOf: fileURL)
        )
    }

    public func save(_ surface: CalibratedSurface) throws {
        try FileManager.default.createDirectory(
            at: fileURL.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        try encoder.encode(surface).write(to: fileURL, options: .atomic)
    }
}
