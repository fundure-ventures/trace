import Dispatch
import Foundation
import NeoTransport

public struct InputArrivalTime: Equatable, Sendable {
    public let wallClockMilliseconds: UInt64
    public let uptimeNanoseconds: UInt64
    public let transportBatchID: UInt64?
    public let transportBatchFrameCount: Int?
    public let transportBatchByteCount: Int?

    public init(
        wallClockMilliseconds: UInt64,
        uptimeNanoseconds: UInt64,
        transportBatchID: UInt64? = nil,
        transportBatchFrameCount: Int? = nil,
        transportBatchByteCount: Int? = nil
    ) {
        self.wallClockMilliseconds = wallClockMilliseconds
        self.uptimeNanoseconds = uptimeNanoseconds
        self.transportBatchID = transportBatchID
        self.transportBatchFrameCount = transportBatchFrameCount
        self.transportBatchByteCount = transportBatchByteCount
    }

    public static func now() -> InputArrivalTime {
        InputArrivalTime(
            wallClockMilliseconds: UInt64(
                Date().timeIntervalSince1970 * 1_000
            ),
            uptimeNanoseconds: DispatchTime.now().uptimeNanoseconds,
            transportBatchID: nil,
            transportBatchFrameCount: nil,
            transportBatchByteCount: nil
        )
    }
}

public struct PenPageID: Codable, Equatable, Hashable, Sendable {
    public let section: UInt8
    public let owner: UInt32
    public let note: UInt32
    public let page: UInt32

    public init(section: UInt8, owner: UInt32, note: UInt32, page: UInt32) {
        self.section = section
        self.owner = owner
        self.note = note
        self.page = page
    }

    init(_ info: PenPageInfo) {
        self.init(
            section: info.section,
            owner: info.owner,
            note: info.note,
            page: info.page
        )
    }
}

public enum SampleContinuity: Equatable, Sendable {
    case first
    case continuous
    case gap(opticalErrors: Int, eventCountDelta: UInt8)
}

public struct InputStrokeStarted: Equatable, Sendable {
    public let strokeID: UInt64
    public let penTimestampMilliseconds: UInt64
    public let receivedWallClockMilliseconds: UInt64
    public let receivedUptimeNanoseconds: UInt64
    public let inputLatencyMilliseconds: Int64
    public let tipType: PenTipType
    public let color: UInt32

    public init(
        strokeID: UInt64,
        penTimestampMilliseconds: UInt64,
        receivedWallClockMilliseconds: UInt64,
        receivedUptimeNanoseconds: UInt64,
        inputLatencyMilliseconds: Int64,
        tipType: PenTipType,
        color: UInt32
    ) {
        self.strokeID = strokeID
        self.penTimestampMilliseconds = penTimestampMilliseconds
        self.receivedWallClockMilliseconds = receivedWallClockMilliseconds
        self.receivedUptimeNanoseconds = receivedUptimeNanoseconds
        self.inputLatencyMilliseconds = inputLatencyMilliseconds
        self.tipType = tipType
        self.color = color
    }
}

public struct RawPenSample: Equatable, Sendable {
    public let id: UInt64
    public let strokeID: UInt64
    public let sampleIndex: Int
    public let eventCount: UInt8
    public let page: PenPageID?
    public let penTimestampMilliseconds: UInt64
    public let receivedWallClockMilliseconds: UInt64
    public let receivedUptimeNanoseconds: UInt64
    public let protocolClockDeltaMilliseconds: Int64
    public let interArrivalMilliseconds: Double?
    public let x: Double
    public let y: Double
    public let force: UInt16
    public let pressure: Double?
    public let tiltX: UInt8
    public let tiltY: UInt8
    public let twist: UInt16
    public let continuity: SampleContinuity
    public let transportBatchID: UInt64?
    public let transportBatchFrameCount: Int?
    public let transportBatchByteCount: Int?

    public init(
        id: UInt64,
        strokeID: UInt64,
        sampleIndex: Int,
        eventCount: UInt8,
        page: PenPageID?,
        penTimestampMilliseconds: UInt64,
        receivedWallClockMilliseconds: UInt64,
        receivedUptimeNanoseconds: UInt64,
        protocolClockDeltaMilliseconds: Int64,
        interArrivalMilliseconds: Double?,
        x: Double,
        y: Double,
        force: UInt16,
        pressure: Double?,
        tiltX: UInt8,
        tiltY: UInt8,
        twist: UInt16,
        continuity: SampleContinuity,
        transportBatchID: UInt64? = nil,
        transportBatchFrameCount: Int? = nil,
        transportBatchByteCount: Int? = nil
    ) {
        self.id = id
        self.strokeID = strokeID
        self.sampleIndex = sampleIndex
        self.eventCount = eventCount
        self.page = page
        self.penTimestampMilliseconds = penTimestampMilliseconds
        self.receivedWallClockMilliseconds = receivedWallClockMilliseconds
        self.receivedUptimeNanoseconds = receivedUptimeNanoseconds
        self.protocolClockDeltaMilliseconds = protocolClockDeltaMilliseconds
        self.interArrivalMilliseconds = interArrivalMilliseconds
        self.x = x
        self.y = y
        self.force = force
        self.pressure = pressure
        self.tiltX = tiltX
        self.tiltY = tiltY
        self.twist = twist
        self.continuity = continuity
        self.transportBatchID = transportBatchID
        self.transportBatchFrameCount = transportBatchFrameCount
        self.transportBatchByteCount = transportBatchByteCount
    }
}

public enum HoverSampleSource: String, Equatable, Sendable {
    case outOfStrokeDot = "out-of-stroke-dot"
    case explicitProtocolEvent = "explicit-0x6f"
}

public struct RawHoverSample: Equatable, Sendable {
    public let id: UInt64
    public let source: HoverSampleSource
    public let eventCount: UInt8?
    public let timeDeltaMilliseconds: UInt8
    public let page: PenPageID?
    public let receivedWallClockMilliseconds: UInt64
    public let receivedUptimeNanoseconds: UInt64
    public let interArrivalMilliseconds: Double?
    public let x: Double
    public let y: Double
    public let force: UInt16?
    public let pressure: Double?
    public let tiltX: UInt8?
    public let tiltY: UInt8?
    public let twist: UInt16?
    public let transportBatchID: UInt64?
    public let transportBatchFrameCount: Int?
    public let transportBatchByteCount: Int?

    public init(
        id: UInt64,
        source: HoverSampleSource,
        eventCount: UInt8?,
        timeDeltaMilliseconds: UInt8,
        page: PenPageID?,
        receivedWallClockMilliseconds: UInt64,
        receivedUptimeNanoseconds: UInt64,
        interArrivalMilliseconds: Double?,
        x: Double,
        y: Double,
        force: UInt16?,
        pressure: Double?,
        tiltX: UInt8?,
        tiltY: UInt8?,
        twist: UInt16?,
        transportBatchID: UInt64? = nil,
        transportBatchFrameCount: Int? = nil,
        transportBatchByteCount: Int? = nil
    ) {
        self.id = id
        self.source = source
        self.eventCount = eventCount
        self.timeDeltaMilliseconds = timeDeltaMilliseconds
        self.page = page
        self.receivedWallClockMilliseconds = receivedWallClockMilliseconds
        self.receivedUptimeNanoseconds = receivedUptimeNanoseconds
        self.interArrivalMilliseconds = interArrivalMilliseconds
        self.x = x
        self.y = y
        self.force = force
        self.pressure = pressure
        self.tiltX = tiltX
        self.tiltY = tiltY
        self.twist = twist
        self.transportBatchID = transportBatchID
        self.transportBatchFrameCount = transportBatchFrameCount
        self.transportBatchByteCount = transportBatchByteCount
    }
}

public struct InputOpticalError: Equatable, Sendable {
    public let strokeID: UInt64
    public let page: PenPageID?
    public let penTimestampMilliseconds: UInt64
    public let receivedWallClockMilliseconds: UInt64
    public let receivedUptimeNanoseconds: UInt64
    public let protocolClockDeltaMilliseconds: Int64
    public let event: PenImageProcessingError

    public init(
        strokeID: UInt64,
        page: PenPageID?,
        penTimestampMilliseconds: UInt64,
        receivedWallClockMilliseconds: UInt64,
        receivedUptimeNanoseconds: UInt64,
        protocolClockDeltaMilliseconds: Int64,
        event: PenImageProcessingError
    ) {
        self.strokeID = strokeID
        self.page = page
        self.penTimestampMilliseconds = penTimestampMilliseconds
        self.receivedWallClockMilliseconds = receivedWallClockMilliseconds
        self.receivedUptimeNanoseconds = receivedUptimeNanoseconds
        self.protocolClockDeltaMilliseconds = protocolClockDeltaMilliseconds
        self.event = event
    }
}

public struct InputStrokeCompleted: Equatable, Sendable {
    public let strokeID: UInt64
    public let page: PenPageID?
    public let startedAtPenMilliseconds: UInt64
    public let endedAtPenMilliseconds: UInt64
    public let durationMilliseconds: UInt64
    public let sampleCount: Int
    public let opticalErrorCount: Int
    public let reportedDotCount: UInt16
    public let totalImageCount: UInt16
    public let processedImageCount: UInt16
    public let successfulImageCount: UInt16
    public let sentImageCount: UInt16
    public let imageRecognitionRate: Double
    public let receivedWallClockMilliseconds: UInt64
    public let receivedUptimeNanoseconds: UInt64
    public let completionLatencyMilliseconds: Int64

    public init(
        strokeID: UInt64,
        page: PenPageID?,
        startedAtPenMilliseconds: UInt64,
        endedAtPenMilliseconds: UInt64,
        durationMilliseconds: UInt64,
        sampleCount: Int,
        opticalErrorCount: Int,
        reportedDotCount: UInt16,
        totalImageCount: UInt16,
        processedImageCount: UInt16,
        successfulImageCount: UInt16,
        sentImageCount: UInt16,
        imageRecognitionRate: Double,
        receivedWallClockMilliseconds: UInt64 = 0,
        receivedUptimeNanoseconds: UInt64 = 0,
        completionLatencyMilliseconds: Int64 = 0
    ) {
        self.strokeID = strokeID
        self.page = page
        self.startedAtPenMilliseconds = startedAtPenMilliseconds
        self.endedAtPenMilliseconds = endedAtPenMilliseconds
        self.durationMilliseconds = durationMilliseconds
        self.sampleCount = sampleCount
        self.opticalErrorCount = opticalErrorCount
        self.reportedDotCount = reportedDotCount
        self.totalImageCount = totalImageCount
        self.processedImageCount = processedImageCount
        self.successfulImageCount = successfulImageCount
        self.sentImageCount = sentImageCount
        self.imageRecognitionRate = imageRecognitionRate
        self.receivedWallClockMilliseconds = receivedWallClockMilliseconds
        self.receivedUptimeNanoseconds = receivedUptimeNanoseconds
        self.completionLatencyMilliseconds = completionLatencyMilliseconds
    }
}

public enum InputAnomaly: Equatable, Sendable {
    case opticalErrorWithoutActiveStroke
    case penUpWithoutActiveStroke
    case penDownBeforePenUp(previousStrokeID: UInt64)
}

public enum NeoInputEvent: Equatable, Sendable {
    case strokeStarted(InputStrokeStarted)
    case pageChanged(PenPageID)
    case sample(RawPenSample)
    case hover(RawHoverSample)
    case opticalError(InputOpticalError)
    case strokeCompleted(InputStrokeCompleted)
    case anomaly(InputAnomaly)
}

public final class NeoInputNormalizer {
    public var eventHandler: ((NeoInputEvent) -> Void)?

    private struct ActiveStroke {
        let id: UInt64
        let startedAtPenMilliseconds: UInt64
        var currentPenMilliseconds: UInt64
        var sampleCount = 0
        var opticalErrorCount = 0
        var opticalErrorsSinceLastSample = 0
        var lastDotEventCount: UInt8?
        var lastSampleArrivalUptimeNanoseconds: UInt64?
    }

    private var maxForce: UInt16?
    private var currentPage: PenPageID?
    private var activeStroke: ActiveStroke?
    private var nextStrokeID: UInt64 = 1
    private var nextSampleID: UInt64 = 1
    private var nextHoverSampleID: UInt64 = 1
    private var lastHoverArrivalUptimeNanoseconds: UInt64?

    public init() {}

    public func resetConnectionState() {
        maxForce = nil
        currentPage = nil
        activeStroke = nil
        lastHoverArrivalUptimeNanoseconds = nil
    }

    public func receive(
        _ event: NeoTransportEvent,
        at arrival: InputArrivalTime = .now()
    ) {
        switch event {
        case let .status(status):
            maxForce = status.maxForce
        case let .penDown(event):
            beginStroke(event, arrival: arrival)
        case let .pageChanged(page):
            let pageID = PenPageID(page)
            currentPage = pageID
            emit(.pageChanged(pageID))
        case let .dot(event):
            receiveDot(event, arrival: arrival)
        case let .hover(event):
            receiveHover(event, arrival: arrival)
        case let .imageProcessingError(event):
            receiveOpticalError(event, arrival: arrival)
        case let .penUp(event):
            completeStroke(event, arrival: arrival)
        default:
            break
        }
    }

    private func beginStroke(_ event: PenDownEvent, arrival: InputArrivalTime) {
        if let activeStroke {
            emit(.anomaly(.penDownBeforePenUp(previousStrokeID: activeStroke.id)))
        }

        let strokeID = nextStrokeID
        nextStrokeID += 1
        lastHoverArrivalUptimeNanoseconds = nil
        activeStroke = ActiveStroke(
            id: strokeID,
            startedAtPenMilliseconds: event.timestampMilliseconds,
            currentPenMilliseconds: event.timestampMilliseconds
        )
        emit(
            .strokeStarted(
                InputStrokeStarted(
                    strokeID: strokeID,
                    penTimestampMilliseconds: event.timestampMilliseconds,
                    receivedWallClockMilliseconds: arrival.wallClockMilliseconds,
                    receivedUptimeNanoseconds: arrival.uptimeNanoseconds,
                    inputLatencyMilliseconds: latency(
                        arrival.wallClockMilliseconds,
                        event.timestampMilliseconds
                    ),
                    tipType: event.tipType,
                    color: event.color
                )
            )
        )
    }

    private func receiveDot(_ event: PenDotEvent, arrival: InputArrivalTime) {
        guard var stroke = activeStroke else {
            emitHover(
                source: .outOfStrokeDot,
                eventCount: event.eventCount,
                timeDeltaMilliseconds: event.timeDeltaMilliseconds,
                x: event.preciseX,
                y: event.preciseY,
                force: event.force,
                tiltX: event.tiltX,
                tiltY: event.tiltY,
                twist: event.twist,
                arrival: arrival
            )
            return
        }

        stroke.currentPenMilliseconds += UInt64(event.timeDeltaMilliseconds)
        let interArrival = stroke.lastSampleArrivalUptimeNanoseconds.map {
            Double(arrival.uptimeNanoseconds - $0) / 1_000_000
        }
        let continuity: SampleContinuity
        if stroke.sampleCount == 0 {
            continuity = .first
        } else {
            let eventCountDelta = event.eventCount &- (stroke.lastDotEventCount ?? 0)
            if eventCountDelta == 1, stroke.opticalErrorsSinceLastSample == 0 {
                continuity = .continuous
            } else {
                continuity = .gap(
                    opticalErrors: stroke.opticalErrorsSinceLastSample,
                    eventCountDelta: eventCountDelta
                )
            }
        }

        let sample = RawPenSample(
            id: nextSampleID,
            strokeID: stroke.id,
            sampleIndex: stroke.sampleCount,
            eventCount: event.eventCount,
            page: currentPage,
            penTimestampMilliseconds: stroke.currentPenMilliseconds,
            receivedWallClockMilliseconds: arrival.wallClockMilliseconds,
            receivedUptimeNanoseconds: arrival.uptimeNanoseconds,
            protocolClockDeltaMilliseconds: latency(
                arrival.wallClockMilliseconds,
                stroke.currentPenMilliseconds
            ),
            interArrivalMilliseconds: interArrival,
            x: event.preciseX,
            y: event.preciseY,
            force: event.force,
            pressure: normalizedPressure(for: event.force),
            tiltX: event.tiltX,
            tiltY: event.tiltY,
            twist: event.twist,
            continuity: continuity,
            transportBatchID: arrival.transportBatchID,
            transportBatchFrameCount: arrival.transportBatchFrameCount,
            transportBatchByteCount: arrival.transportBatchByteCount
        )

        nextSampleID += 1
        stroke.sampleCount += 1
        stroke.lastDotEventCount = event.eventCount
        stroke.lastSampleArrivalUptimeNanoseconds = arrival.uptimeNanoseconds
        stroke.opticalErrorsSinceLastSample = 0
        activeStroke = stroke
        emit(.sample(sample))
    }

    private func receiveHover(
        _ event: PenHoverEvent,
        arrival: InputArrivalTime
    ) {
        emitHover(
            source: .explicitProtocolEvent,
            eventCount: nil,
            timeDeltaMilliseconds: event.timeDeltaMilliseconds,
            x: event.preciseX,
            y: event.preciseY,
            force: nil,
            tiltX: nil,
            tiltY: nil,
            twist: nil,
            arrival: arrival
        )
    }

    private func emitHover(
        source: HoverSampleSource,
        eventCount: UInt8?,
        timeDeltaMilliseconds: UInt8,
        x: Double,
        y: Double,
        force: UInt16?,
        tiltX: UInt8?,
        tiltY: UInt8?,
        twist: UInt16?,
        arrival: InputArrivalTime
    ) {
        let interArrival = lastHoverArrivalUptimeNanoseconds.map {
            Double(arrival.uptimeNanoseconds - $0) / 1_000_000
        }
        let sample = RawHoverSample(
            id: nextHoverSampleID,
            source: source,
            eventCount: eventCount,
            timeDeltaMilliseconds: timeDeltaMilliseconds,
            page: currentPage,
            receivedWallClockMilliseconds: arrival.wallClockMilliseconds,
            receivedUptimeNanoseconds: arrival.uptimeNanoseconds,
            interArrivalMilliseconds: interArrival,
            x: x,
            y: y,
            force: force,
            pressure: force.flatMap(normalizedPressure),
            tiltX: tiltX,
            tiltY: tiltY,
            twist: twist,
            transportBatchID: arrival.transportBatchID,
            transportBatchFrameCount: arrival.transportBatchFrameCount,
            transportBatchByteCount: arrival.transportBatchByteCount
        )
        nextHoverSampleID += 1
        lastHoverArrivalUptimeNanoseconds = arrival.uptimeNanoseconds
        emit(.hover(sample))
    }

    private func normalizedPressure(for force: UInt16) -> Double? {
        guard let maxForce, maxForce > 0 else {
            return nil
        }
        return min(1, Double(force) / Double(maxForce))
    }

    private func receiveOpticalError(
        _ event: PenImageProcessingError,
        arrival: InputArrivalTime
    ) {
        guard var stroke = activeStroke else {
            emit(.anomaly(.opticalErrorWithoutActiveStroke))
            return
        }

        stroke.currentPenMilliseconds += UInt64(event.timeDeltaMilliseconds)
        stroke.opticalErrorCount += 1
        stroke.opticalErrorsSinceLastSample += 1
        activeStroke = stroke
        emit(
            .opticalError(
                InputOpticalError(
                    strokeID: stroke.id,
                    page: currentPage,
                    penTimestampMilliseconds: stroke.currentPenMilliseconds,
                    receivedWallClockMilliseconds: arrival.wallClockMilliseconds,
                    receivedUptimeNanoseconds: arrival.uptimeNanoseconds,
                    protocolClockDeltaMilliseconds: latency(
                        arrival.wallClockMilliseconds,
                        stroke.currentPenMilliseconds
                    ),
                    event: event
                )
            )
        )
    }

    private func completeStroke(
        _ event: PenUpEvent,
        arrival: InputArrivalTime
    ) {
        guard let stroke = activeStroke else {
            emit(.anomaly(.penUpWithoutActiveStroke))
            return
        }

        let duration = event.timestampMilliseconds >= stroke.startedAtPenMilliseconds
            ? event.timestampMilliseconds - stroke.startedAtPenMilliseconds
            : 0
        let recognition = event.totalImageCount == 0
            ? 0
            : Double(event.successfulImageCount) / Double(event.totalImageCount)
        emit(
            .strokeCompleted(
                InputStrokeCompleted(
                    strokeID: stroke.id,
                    page: currentPage,
                    startedAtPenMilliseconds: stroke.startedAtPenMilliseconds,
                    endedAtPenMilliseconds: event.timestampMilliseconds,
                    durationMilliseconds: duration,
                    sampleCount: stroke.sampleCount,
                    opticalErrorCount: stroke.opticalErrorCount,
                    reportedDotCount: event.dotCount,
                    totalImageCount: event.totalImageCount,
                    processedImageCount: event.processedImageCount,
                    successfulImageCount: event.successfulImageCount,
                    sentImageCount: event.sentImageCount,
                    imageRecognitionRate: recognition,
                    receivedWallClockMilliseconds: arrival.wallClockMilliseconds,
                    receivedUptimeNanoseconds: arrival.uptimeNanoseconds,
                    completionLatencyMilliseconds: latency(
                        arrival.wallClockMilliseconds,
                        event.timestampMilliseconds
                    )
                )
            )
        )
        activeStroke = nil
        lastHoverArrivalUptimeNanoseconds = nil
    }

    private func latency(_ arrival: UInt64, _ pen: UInt64) -> Int64 {
        Int64(arrival) - Int64(pen)
    }

    private func emit(_ event: NeoInputEvent) {
        eventHandler?(event)
    }
}
