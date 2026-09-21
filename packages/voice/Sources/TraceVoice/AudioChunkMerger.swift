import AVFoundation
import Foundation

public protocol TraceAudioChunkMerging: Sendable {
    func merge(_ chunks: [TraceAudioChunk]) throws -> URL
}

public struct TraceAudioChunkFileMerger:
    TraceAudioChunkMerging,
    Sendable
{
    public init() {}

    public func merge(_ chunks: [TraceAudioChunk]) throws -> URL {
        let ordered = chunks.sorted { $0.index < $1.index }
        guard let first = ordered.first else {
            throw TraceTranscriptionError.emptyAudio
        }
        let outputURL = first.fileURL
            .deletingLastPathComponent()
            .appendingPathComponent("voice.wav")
        try? FileManager.default.removeItem(at: outputURL)
        let firstFile = try AVAudioFile(forReading: first.fileURL)
        let format = firstFile.processingFormat
        let output = try AVAudioFile(
            forWriting: outputURL,
            settings: firstFile.fileFormat.settings,
            commonFormat: format.commonFormat,
            interleaved: format.isInterleaved
        )

        for chunk in ordered {
            let input = try AVAudioFile(forReading: chunk.fileURL)
            guard input.processingFormat == format else {
                throw TraceAudioRecordingError.couldNotPrepare
            }
            while input.framePosition < input.length {
                let remaining = input.length - input.framePosition
                let capacity = AVAudioFrameCount(min(4_096, remaining))
                guard let buffer = AVAudioPCMBuffer(
                    pcmFormat: format,
                    frameCapacity: capacity
                ) else {
                    throw TraceAudioRecordingError.couldNotPrepare
                }
                try input.read(into: buffer)
                guard buffer.frameLength > 0 else {
                    break
                }
                try output.write(from: buffer)
            }
        }
        return outputURL
    }
}
