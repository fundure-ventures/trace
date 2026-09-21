import NeoInput

public extension NeoInputEvent {
    func replayed(at arrival: InputArrivalTime) -> NeoInputEvent {
        switch self {
        case let .strokeStarted(stroke):
            return .strokeStarted(
                InputStrokeStarted(
                    strokeID: stroke.strokeID,
                    penTimestampMilliseconds:
                        arrival.wallClockMilliseconds,
                    receivedWallClockMilliseconds:
                        arrival.wallClockMilliseconds,
                    receivedUptimeNanoseconds:
                        arrival.uptimeNanoseconds,
                    inputLatencyMilliseconds: 0,
                    tipType: stroke.tipType,
                    color: stroke.color
                )
            )
        case let .sample(sample):
            return .sample(
                RawPenSample(
                    id: sample.id,
                    strokeID: sample.strokeID,
                    sampleIndex: sample.sampleIndex,
                    eventCount: sample.eventCount,
                    page: sample.page,
                    penTimestampMilliseconds:
                        arrival.wallClockMilliseconds,
                    receivedWallClockMilliseconds:
                        arrival.wallClockMilliseconds,
                    receivedUptimeNanoseconds:
                        arrival.uptimeNanoseconds,
                    protocolClockDeltaMilliseconds: 0,
                    interArrivalMilliseconds:
                        sample.interArrivalMilliseconds,
                    x: sample.x,
                    y: sample.y,
                    force: sample.force,
                    pressure: sample.pressure,
                    tiltX: sample.tiltX,
                    tiltY: sample.tiltY,
                    twist: sample.twist,
                    continuity: sample.continuity,
                    transportBatchID: sample.transportBatchID,
                    transportBatchFrameCount:
                        sample.transportBatchFrameCount,
                    transportBatchByteCount:
                        sample.transportBatchByteCount
                )
            )
        case let .strokeCompleted(stroke):
            let startedAt = arrival.wallClockMilliseconds
                >= stroke.durationMilliseconds
                ? arrival.wallClockMilliseconds - stroke.durationMilliseconds
                : 0
            return .strokeCompleted(
                InputStrokeCompleted(
                    strokeID: stroke.strokeID,
                    page: stroke.page,
                    startedAtPenMilliseconds: startedAt,
                    endedAtPenMilliseconds:
                        arrival.wallClockMilliseconds,
                    durationMilliseconds: stroke.durationMilliseconds,
                    sampleCount: stroke.sampleCount,
                    opticalErrorCount: stroke.opticalErrorCount,
                    reportedDotCount: stroke.reportedDotCount,
                    totalImageCount: stroke.totalImageCount,
                    processedImageCount: stroke.processedImageCount,
                    successfulImageCount: stroke.successfulImageCount,
                    sentImageCount: stroke.sentImageCount,
                    imageRecognitionRate: stroke.imageRecognitionRate,
                    receivedWallClockMilliseconds:
                        arrival.wallClockMilliseconds,
                    receivedUptimeNanoseconds:
                        arrival.uptimeNanoseconds,
                    completionLatencyMilliseconds: 0
                )
            )
        case let .opticalError(error):
            return .opticalError(
                InputOpticalError(
                    strokeID: error.strokeID,
                    page: error.page,
                    penTimestampMilliseconds:
                        arrival.wallClockMilliseconds,
                    receivedWallClockMilliseconds:
                        arrival.wallClockMilliseconds,
                    receivedUptimeNanoseconds:
                        arrival.uptimeNanoseconds,
                    protocolClockDeltaMilliseconds: 0,
                    event: error.event
                )
            )
        case let .hover(sample):
            return .hover(
                RawHoverSample(
                    id: sample.id,
                    source: sample.source,
                    eventCount: sample.eventCount,
                    timeDeltaMilliseconds: sample.timeDeltaMilliseconds,
                    page: sample.page,
                    receivedWallClockMilliseconds:
                        arrival.wallClockMilliseconds,
                    receivedUptimeNanoseconds:
                        arrival.uptimeNanoseconds,
                    interArrivalMilliseconds:
                        sample.interArrivalMilliseconds,
                    x: sample.x,
                    y: sample.y,
                    force: sample.force,
                    pressure: sample.pressure,
                    tiltX: sample.tiltX,
                    tiltY: sample.tiltY,
                    twist: sample.twist,
                    transportBatchID: sample.transportBatchID,
                    transportBatchFrameCount:
                        sample.transportBatchFrameCount,
                    transportBatchByteCount:
                        sample.transportBatchByteCount
                )
            )
        case .pageChanged, .anomaly:
            return self
        }
    }
}
