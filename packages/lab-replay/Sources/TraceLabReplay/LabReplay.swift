import Foundation
import NeoInput

public struct LabReplay {
    public enum InputSource: String {
        case pen
        case mouse
    }

    public struct Entry {
        public let uptimeNanoseconds: UInt64
        public let event: NeoInputEvent
        public let inputSource: InputSource
    }

    public let events: [Entry]

    public static func load(from url: URL) throws -> LabReplay {
        let rows = try String(contentsOf: url, encoding: .utf8)
            .split(separator: "\n")
            .compactMap { line -> [String: Any]? in
                let object = try JSONSerialization.jsonObject(
                    with: Data(line.utf8)
                )
                return object as? [String: Any]
            }
        let eligibleSamples = measurementSamples(rows)
        let eligibleStrokeIDs = Set(eligibleSamples.map {
            uint64($0, "stroke_id")
        })
        let startPenByStroke = Dictionary(
            uniqueKeysWithValues: rows.compactMap { row -> (UInt64, UInt64)? in
                guard row["type"] as? String == "stroke-start" else {
                    return nil
                }
                return (
                    uint64(row, "stroke_id"),
                    uint64(row, "pen_ms")
                )
            }
        )
        guard !eligibleSamples.isEmpty else {
            throw ReplayError.noMeasurementSamples
        }

        var entries: [Entry] = []
        for row in rows {
            let type = row["type"] as? String
            let strokeID = uint64(row, "stroke_id")
            guard strokeID == 0 || eligibleStrokeIDs.contains(strokeID) else {
                continue
            }

            switch type {
            case "stroke-start":
                entries.append(
                    Entry(
                        uptimeNanoseconds: uint64(row, "received_uptime_ns"),
                        event: .strokeStarted(
                            InputStrokeStarted(
                                strokeID: strokeID,
                                penTimestampMilliseconds: uint64(row, "pen_ms"),
                                receivedWallClockMilliseconds: uint64(
                                    row,
                                    "received_ms"
                                ),
                                receivedUptimeNanoseconds: uint64(
                                    row,
                                    "received_uptime_ns"
                                ),
                                inputLatencyMilliseconds: Int64(
                                    int(
                                        row,
                                        row["raw_start_clock_delta_ms"] == nil
                                            ? "input_latency_ms"
                                            : "raw_start_clock_delta_ms"
                                    )
                                ),
                                tipType: .normal,
                                color: 0xFF00_0000
                            )
                        ),
                        inputSource: inputSource(from: row)
                    )
                )
            case "sample":
                guard eligible(row) else {
                    continue
                }
                let sample = try sample(from: row)
                if sample.sampleIndex == 0, let page = sample.page {
                    entries.append(
                        Entry(
                            uptimeNanoseconds: sample.receivedUptimeNanoseconds,
                            event: .pageChanged(page),
                            inputSource: inputSource(from: row)
                        )
                    )
                }
                entries.append(
                    Entry(
                        uptimeNanoseconds: sample.receivedUptimeNanoseconds,
                        event: .sample(sample),
                        inputSource: inputSource(from: row)
                    )
                )
            case "hover":
                let sample = hoverSample(from: row)
                entries.append(
                    Entry(
                        uptimeNanoseconds: sample.receivedUptimeNanoseconds,
                        event: .hover(sample),
                        inputSource: inputSource(from: row)
                    )
                )
            case "stroke-complete":
                let startedAtPenMilliseconds = startPenByStroke[strokeID] ?? 0
                let durationMilliseconds = uint64(row, "duration_ms")
                entries.append(
                    Entry(
                        uptimeNanoseconds: uint64(row, "received_uptime_ns"),
                        event: .strokeCompleted(
                            InputStrokeCompleted(
                                strokeID: strokeID,
                                page: page(from: row),
                                startedAtPenMilliseconds:
                                    startedAtPenMilliseconds,
                                endedAtPenMilliseconds:
                                    startedAtPenMilliseconds
                                        + durationMilliseconds,
                                durationMilliseconds: durationMilliseconds,
                                sampleCount: int(row, "sample_count"),
                                opticalErrorCount: int(
                                    row,
                                    "optical_error_count"
                                ),
                                reportedDotCount: UInt16(
                                    int(row, "reported_dot_count")
                                ),
                                totalImageCount: UInt16(
                                    int(row, "total_image_count")
                                ),
                                processedImageCount: UInt16(
                                    int(row, "processed_image_count")
                                ),
                                successfulImageCount: UInt16(
                                    int(row, "successful_image_count")
                                ),
                                sentImageCount: UInt16(
                                    int(row, "sent_image_count")
                                ),
                                imageRecognitionRate: double(
                                    row,
                                    "image_recognition_rate"
                                ),
                                receivedWallClockMilliseconds: uint64(
                                    row,
                                    "received_ms"
                                ),
                                receivedUptimeNanoseconds: uint64(
                                    row,
                                    "received_uptime_ns"
                                ),
                                completionLatencyMilliseconds: Int64(
                                    int(
                                        row,
                                        row["raw_completion_clock_delta_ms"] == nil
                                            ? "completion_latency_ms"
                                            : "raw_completion_clock_delta_ms"
                                    )
                                )
                            )
                        ),
                        inputSource: inputSource(from: row)
                    )
                )
            default:
                continue
            }
        }

        entries.sort {
            if $0.uptimeNanoseconds == $1.uptimeNanoseconds {
                return eventOrder($0.event) < eventOrder($1.event)
            }
            return $0.uptimeNanoseconds < $1.uptimeNanoseconds
        }
        return LabReplay(events: entries)
    }

    private enum ReplayError: Error {
        case noMeasurementSamples
        case unknownContinuity
    }

    private static func measurementSamples(
        _ rows: [[String: Any]]
    ) -> [[String: Any]] {
        let hasMarkers = rows.contains {
            let type = $0["type"] as? String
            return type == "page-primed"
                || type == "calibration"
                || type == "measurement-paused"
        }
        var ready = !hasMarkers
        var samples: [[String: Any]] = []
        for row in rows {
            switch row["type"] as? String {
            case "measurement-paused":
                ready = false
            case "page-primed", "calibration":
                ready = true
            case "sample":
                let explicit = row["measurement_eligible"] as? Bool
                if explicit ?? ready {
                    samples.append(row)
                }
            default:
                break
            }
        }

        return samples
    }

    private static func eligible(_ row: [String: Any]) -> Bool {
        (row["measurement_eligible"] as? Bool) ?? true
    }

    private static func inputSource(
        from row: [String: Any]
    ) -> InputSource {
        if let value = row["input_source"] as? String,
           let source = InputSource(rawValue: value)
        {
            return source
        }
        let mouseIDBase = UInt64(1) << 62
        let identifier = uint64(row, "id")
        let strokeID = uint64(row, "stroke_id")
        return max(identifier, strokeID) >= mouseIDBase
            ? .mouse
            : .pen
    }

    private static func sample(from row: [String: Any]) throws -> RawPenSample {
        let continuity: SampleContinuity
        switch row["continuity"] as? String {
        case "first":
            continuity = .first
        case "continuous":
            continuity = .continuous
        case "gap":
            continuity = .gap(
                opticalErrors: int(row, "gap_optical_errors"),
                eventCountDelta: UInt8(int(row, "gap_event_count_delta"))
            )
        default:
            throw ReplayError.unknownContinuity
        }

        return RawPenSample(
            id: uint64(row, "id"),
            strokeID: uint64(row, "stroke_id"),
            sampleIndex: int(row, "sample_index"),
            eventCount: UInt8(int(row, "event_count")),
            page: page(from: row),
            penTimestampMilliseconds: uint64(row, "pen_ms"),
            receivedWallClockMilliseconds: uint64(row, "received_ms"),
            receivedUptimeNanoseconds: uint64(row, "received_uptime_ns"),
            protocolClockDeltaMilliseconds: Int64(
                int(
                    row,
                    row["protocol_reconstructed_latency_ms"] == nil
                        ? "input_latency_ms"
                        : "protocol_reconstructed_latency_ms"
                )
            ),
            interArrivalMilliseconds: doubleOptional(row, "inter_arrival_ms"),
            x: double(row, "x"),
            y: double(row, "y"),
            force: UInt16(int(row, "force")),
            pressure: doubleOptional(row, "pressure"),
            tiltX: UInt8(int(row, "tilt_x")),
            tiltY: UInt8(int(row, "tilt_y")),
            twist: UInt16(int(row, "twist")),
            continuity: continuity,
            transportBatchID: uint64Optional(row, "transport_batch_id"),
            transportBatchFrameCount: intOptional(
                row,
                "transport_batch_frame_count"
            ),
            transportBatchByteCount: intOptional(
                row,
                "transport_batch_byte_count"
            )
        )
    }

    private static func hoverSample(
        from row: [String: Any]
    ) -> RawHoverSample {
        RawHoverSample(
            id: uint64(row, "id"),
            source: HoverSampleSource(
                rawValue: row["source"] as? String ?? ""
            ) ?? .outOfStrokeDot,
            eventCount: intOptional(row, "event_count").map(UInt8.init),
            timeDeltaMilliseconds: UInt8(int(row, "time_delta_ms")),
            page: page(from: row),
            receivedWallClockMilliseconds: uint64(row, "received_ms"),
            receivedUptimeNanoseconds: uint64(
                row,
                "received_uptime_ns"
            ),
            interArrivalMilliseconds: doubleOptional(
                row,
                "inter_arrival_ms"
            ),
            x: double(row, "x"),
            y: double(row, "y"),
            force: intOptional(row, "force").map(UInt16.init),
            pressure: doubleOptional(row, "pressure"),
            tiltX: intOptional(row, "tilt_x").map(UInt8.init),
            tiltY: intOptional(row, "tilt_y").map(UInt8.init),
            twist: intOptional(row, "twist").map(UInt16.init),
            transportBatchID: uint64Optional(
                row,
                "transport_batch_id"
            ),
            transportBatchFrameCount: intOptional(
                row,
                "transport_batch_frame_count"
            ),
            transportBatchByteCount: intOptional(
                row,
                "transport_batch_byte_count"
            )
        )
    }

    private static func page(from row: [String: Any]) -> PenPageID? {
        guard row["page_section"] != nil else {
            return nil
        }
        return PenPageID(
            section: UInt8(int(row, "page_section")),
            owner: UInt32(int(row, "page_owner")),
            note: UInt32(int(row, "page_note")),
            page: UInt32(int(row, "page_number"))
        )
    }

    private static func eventOrder(_ event: NeoInputEvent) -> Int {
        switch event {
        case .strokeStarted:
            return 0
        case .pageChanged:
            return 1
        case .sample:
            return 2
        case .hover:
            return 3
        case .opticalError:
            return 4
        case .strokeCompleted:
            return 5
        case .anomaly:
            return 6
        }
    }

    private static func int(_ row: [String: Any], _ key: String) -> Int {
        (row[key] as? NSNumber)?.intValue ?? 0
    }

    private static func intOptional(_ row: [String: Any], _ key: String) -> Int? {
        (row[key] as? NSNumber)?.intValue
    }

    private static func uint64(_ row: [String: Any], _ key: String) -> UInt64 {
        (row[key] as? NSNumber)?.uint64Value ?? 0
    }

    private static func uint64Optional(
        _ row: [String: Any],
        _ key: String
    ) -> UInt64? {
        (row[key] as? NSNumber)?.uint64Value
    }

    private static func double(_ row: [String: Any], _ key: String) -> Double {
        (row[key] as? NSNumber)?.doubleValue ?? 0
    }

    private static func doubleOptional(
        _ row: [String: Any],
        _ key: String
    ) -> Double? {
        (row[key] as? NSNumber)?.doubleValue
    }
}
