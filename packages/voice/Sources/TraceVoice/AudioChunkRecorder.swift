import AVFoundation
import Foundation

public enum TraceMicrophoneAuthorization: Equatable, Sendable {
    case notDetermined
    case restricted
    case denied
    case authorized
}

public struct TraceAudioChunk: Equatable, Sendable {
    public let index: Int
    public let fileURL: URL
    public let startTimeSeconds: Double
    public let durationSeconds: Double
    public let appClockStartTimeSeconds: Double

    public init(
        index: Int,
        fileURL: URL,
        startTimeSeconds: Double,
        durationSeconds: Double,
        appClockStartTimeSeconds: Double = 0
    ) {
        self.index = index
        self.fileURL = fileURL
        self.startTimeSeconds = startTimeSeconds
        self.durationSeconds = durationSeconds
        self.appClockStartTimeSeconds = appClockStartTimeSeconds
    }
}

public enum TraceAudioRecordingError: LocalizedError {
    case microphonePermissionRequired
    case couldNotPrepare
    case couldNotStart

    public var errorDescription: String? {
        switch self {
        case .microphonePermissionRequired:
            return "Trace needs Microphone access to record a voice annotation."
        case .couldNotPrepare:
            return "Trace could not prepare a microphone recording."
        case .couldNotStart:
            return "Trace could not start the microphone recording."
        }
    }
}

public protocol TraceAudioChunkRecording: AnyObject {
    var onChunkReady: ((TraceAudioChunk) -> Void)? { get set }
    var onFailure: ((Error) -> Void)? { get set }
    var onLevelChange: ((Float) -> Void)? { get set }
    var authorizationStatus: TraceMicrophoneAuthorization { get }

    func requestAccess(completion: @escaping (Bool) -> Void)
    func start() throws
    func pause() -> TraceAudioChunk?
    func resume() throws
    func stop() -> TraceAudioChunk?
    func cancel()
    func setPerformanceCritical(_ critical: Bool)
}

public final class TraceAudioChunkRecorder: TraceAudioChunkRecording {
    public static let defaultChunkDurationSeconds: TimeInterval = 12

    public var onChunkReady: ((TraceAudioChunk) -> Void)?
    public var onFailure: ((Error) -> Void)?
    public var onLevelChange: ((Float) -> Void)?

    public static var authorizationStatus: TraceMicrophoneAuthorization {
        switch AVCaptureDevice.authorizationStatus(for: .audio) {
        case .notDetermined:
            return .notDetermined
        case .restricted:
            return .restricted
        case .denied:
            return .denied
        case .authorized:
            return .authorized
        @unknown default:
            return .denied
        }
    }

    public static func requestAccess(
        completion: @escaping (Bool) -> Void
    ) {
        AVCaptureDevice.requestAccess(
            for: .audio,
            completionHandler: completion
        )
    }

    public var authorizationStatus: TraceMicrophoneAuthorization {
        Self.authorizationStatus
    }

    public func requestAccess(
        completion: @escaping (Bool) -> Void
    ) {
        Self.requestAccess(completion: completion)
    }

    private let chunkDurationSeconds: TimeInterval
    private let minimumChunkDurationSeconds: TimeInterval
    private let appClock: () -> Double
    private var recorder: AVAudioRecorder?
    private var rotationTimer: DispatchSourceTimer?
    private var meterTimer: DispatchSourceTimer?
    private var performanceCritical = false
    private var rotationPending = false
    private var sessionDirectory: URL?
    private var nextChunkIndex = 0
    private var elapsedSeconds: Double = 0
    private var currentChunkAppClockStartTimeSeconds: Double?

    public init(
        chunkDurationSeconds: TimeInterval =
            TraceAudioChunkRecorder.defaultChunkDurationSeconds,
        minimumChunkDurationSeconds: TimeInterval = 0.2,
        appClock: @escaping () -> Double = {
            Date().timeIntervalSince1970
        }
    ) {
        self.chunkDurationSeconds = chunkDurationSeconds
        self.minimumChunkDurationSeconds = minimumChunkDurationSeconds
        self.appClock = appClock
    }

    deinit {
        cancel()
    }

    public func start() throws {
        guard Self.authorizationStatus == .authorized else {
            throw TraceAudioRecordingError.microphonePermissionRequired
        }
        cancel()
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("TraceVoice", isDirectory: true)
            .appendingPathComponent(
                UUID().uuidString,
                isDirectory: true
            )
        try FileManager.default.createDirectory(
            at: directory,
            withIntermediateDirectories: true
        )
        sessionDirectory = directory
        nextChunkIndex = 0
        elapsedSeconds = 0
        currentChunkAppClockStartTimeSeconds = nil
        performanceCritical = false
        rotationPending = false
        try startNextChunk()
        startTimers()
    }

    public func pause() -> TraceAudioChunk? {
        stopTimers()
        rotationPending = false
        onLevelChange?(0)
        return finishCurrentChunk(emit: true)
    }

    public func resume() throws {
        guard recorder == nil else {
            return
        }
        try startNextChunk()
        startTimers()
    }

    public func stop() -> TraceAudioChunk? {
        pause()
    }

    public func cancel() {
        stopTimers()
        onLevelChange?(0)
        _ = finishCurrentChunk(emit: false)
        if let sessionDirectory {
            try? FileManager.default.removeItem(at: sessionDirectory)
        }
        sessionDirectory = nil
        nextChunkIndex = 0
        elapsedSeconds = 0
        currentChunkAppClockStartTimeSeconds = nil
        performanceCritical = false
        rotationPending = false
    }

    public func setPerformanceCritical(_ critical: Bool) {
        guard critical != performanceCritical else {
            return
        }
        performanceCritical = critical
        if critical {
            meterTimer?.cancel()
            meterTimer = nil
            return
        }
        DispatchQueue.main.async { [weak self] in
            self?.resumeDeferredWorkIfPossible()
        }
    }

    private func rotateChunk() {
        guard recorder != nil else {
            return
        }
        if performanceCritical {
            rotationPending = true
            return
        }
        let finished = finishCurrentChunk(emit: true)
        do {
            try startNextChunk()
            scheduleRotationTimer()
            if let finished {
                onChunkReady?(finished)
            }
        } catch {
            stopTimers()
            onLevelChange?(0)
            if let finished {
                onChunkReady?(finished)
            }
            onFailure?(error)
        }
    }

    private func resumeDeferredWorkIfPossible() {
        guard !performanceCritical else {
            return
        }
        if recorder != nil, meterTimer == nil {
            startMeterTimer()
        }
        if rotationPending {
            rotationPending = false
            rotateChunk()
        }
    }

    private func startNextChunk() throws {
        guard let sessionDirectory else {
            throw TraceAudioRecordingError.couldNotPrepare
        }
        let url = sessionDirectory.appendingPathComponent(
            String(format: "chunk-%04d.wav", nextChunkIndex)
        )
        let settings: [String: Any] = [
            AVFormatIDKey: kAudioFormatLinearPCM,
            AVSampleRateKey: 16_000,
            AVNumberOfChannelsKey: 1,
            AVLinearPCMBitDepthKey: 16,
            AVLinearPCMIsFloatKey: false,
            AVLinearPCMIsBigEndianKey: false,
        ]
        let recorder = try AVAudioRecorder(
            url: url,
            settings: settings
        )
        guard recorder.prepareToRecord() else {
            throw TraceAudioRecordingError.couldNotPrepare
        }
        recorder.isMeteringEnabled = true
        guard recorder.record() else {
            throw TraceAudioRecordingError.couldNotStart
        }
        self.recorder = recorder
        currentChunkAppClockStartTimeSeconds = appClock()
    }

    private func startTimers() {
        scheduleRotationTimer()
        if !performanceCritical {
            startMeterTimer()
        }
    }

    private func scheduleRotationTimer() {
        rotationTimer?.cancel()
        let rotationTimer = DispatchSource.makeTimerSource(queue: .main)
        rotationTimer.schedule(
            deadline: .now() + chunkDurationSeconds,
            leeway: .milliseconds(50)
        )
        rotationTimer.setEventHandler { [weak self] in
            self?.rotationTimer = nil
            self?.rotateChunk()
        }
        rotationTimer.resume()
        self.rotationTimer = rotationTimer
    }

    private func startMeterTimer() {
        let meterTimer = DispatchSource.makeTimerSource(queue: .main)
        meterTimer.schedule(
            deadline: .now(),
            repeating: .milliseconds(100),
            leeway: .milliseconds(10)
        )
        meterTimer.setEventHandler { [weak self] in
            self?.publishLevel()
        }
        meterTimer.resume()
        self.meterTimer = meterTimer
    }

    private func stopTimers() {
        rotationTimer?.cancel()
        rotationTimer = nil
        meterTimer?.cancel()
        meterTimer = nil
    }

    private func publishLevel() {
        guard let recorder else {
            onLevelChange?(0)
            return
        }
        recorder.updateMeters()
        let decibels = recorder.averagePower(forChannel: 0)
        let normalized = max(
            0,
            min(1, (decibels + 50) / 50)
        )
        onLevelChange?(normalized)
    }

    private func finishCurrentChunk(
        emit: Bool
    ) -> TraceAudioChunk? {
        guard let recorder else {
            return nil
        }
        let duration = recorder.currentTime
        let url = recorder.url
        let appClockStartTimeSeconds =
            currentChunkAppClockStartTimeSeconds
                ?? appClock()
        recorder.stop()
        self.recorder = nil
        currentChunkAppClockStartTimeSeconds = nil

        defer {
            elapsedSeconds += duration
            nextChunkIndex += 1
        }
        guard emit, duration >= minimumChunkDurationSeconds else {
            try? FileManager.default.removeItem(at: url)
            return nil
        }
        return TraceAudioChunk(
            index: nextChunkIndex,
            fileURL: url,
            startTimeSeconds: elapsedSeconds,
            durationSeconds: duration,
            appClockStartTimeSeconds: appClockStartTimeSeconds
        )
    }
}
