import Foundation

public enum TraceVoiceCaptureState: Equatable, Sendable {
    case idle
    case recording(transcribedChunks: Int)
    case paused(transcribedChunks: Int)
    case transcribing(completedChunks: Int, pendingChunks: Int)
    case ready
    case failed(String)

    public var isFinishing: Bool {
        if case .transcribing = self {
            return true
        }
        return false
    }

    public var allowsOpenRouterAPIKeyMutation: Bool {
        switch self {
        case .idle, .failed:
            return true
        case .recording, .paused, .transcribing, .ready:
            return false
        }
    }
}

public enum TraceVoiceConfigurationError: LocalizedError, Equatable {
    case captureInProgress

    public var errorDescription: String? {
        switch self {
        case .captureInProgress:
            return "Finish or cancel the current Dictation recording before "
                + "changing the OpenRouter API key."
        }
    }
}

public enum TraceVoiceToggleIntent: Equatable, Sendable {
    case showSetup
    case start
    case pause
    case resume
    case restart
    case ignore
}

public struct TraceVoiceCaptureResult: Equatable, Sendable {
    public let transcript: String
    public let words: [TraceTimedTranscriptionWord]
    public let audioFileURL: URL?

    public init(
        transcript: String,
        words: [TraceTimedTranscriptionWord] = [],
        audioFileURL: URL?
    ) {
        self.transcript = transcript
        self.words = words
        self.audioFileURL = audioFileURL
    }
}

public struct TraceVoiceTranscriptSnapshot: Equatable, Sendable {
    public let text: String
    public let words: [TraceTimedTranscriptionWord]

    public init(
        text: String,
        words: [TraceTimedTranscriptionWord]
    ) {
        self.text = text
        self.words = words
    }
}

public final class TraceVoiceCaptureController: @unchecked Sendable {
    public var onStateChange: ((TraceVoiceCaptureState) -> Void)?
    public var onLevelChange: ((Float) -> Void)?
    public var onTranscriptChange: ((TraceVoiceTranscriptSnapshot) -> Void)?

    public private(set) var state: TraceVoiceCaptureState = .idle {
        didSet {
            guard state != oldValue else {
                return
            }
            onStateChange?(state)
        }
    }

    public var isConfigured: Bool {
        transcriber != nil
    }

    public private(set) var apiKeyState: OpenRouterAPIKeyState

    public var configurationErrorDescription: String? {
        configurationError?.localizedDescription
    }

    public func toggleIntent(
        hasDocument: Bool
    ) -> TraceVoiceToggleIntent {
        switch state {
        case .recording:
            return .pause
        case .paused:
            return .resume
        case .failed:
            return isConfigured ? .restart : .showSetup
        case .idle:
            guard isConfigured else {
                return .showSetup
            }
            return hasDocument ? .start : .ignore
        case .transcribing, .ready:
            return .ignore
        }
    }

    public var transcriptSnapshot: TraceVoiceTranscriptSnapshot? {
        guard !accumulator.text.isEmpty else {
            return nil
        }
        return TraceVoiceTranscriptSnapshot(
            text: accumulator.text,
            words: accumulator.words
        )
    }

    public var microphoneAuthorization: TraceMicrophoneAuthorization {
        recorder.authorizationStatus
    }

    private let recorder: TraceAudioChunkRecording
    private var transcriber: TraceAudioTranscribing?
    private let merger: TraceAudioChunkMerging
    private var configurationError: Error?
    private let configurationLoader:
        (() throws -> OpenRouterTranscriptionResolution)?
    private struct DeferredTranscriptionCompletion {
        let chunk: TraceAudioChunk
        let result: TraceTranscriptionResult
        let generation: UInt64
    }

    private var pendingChunks: [TraceAudioChunk] = []
    private var allChunks: [TraceAudioChunk] = []
    private var accumulator = OrderedTranscriptAccumulator()
    private var processedChunkCount = 0
    private var activeTask: Task<Void, Never>?
    private var generation: UInt64 = 0
    private var finalizing = false
    private var paused = false
    private var performanceCritical = false
    private var deferredTranscriptionCompletion:
        DeferredTranscriptionCompletion?
    private var readyResult: TraceVoiceCaptureResult?
    private var finishCompletion:
        ((Result<TraceVoiceCaptureResult?, Error>) -> Void)?
    private var lastFailure: Error?

    public convenience init(
        environment: [String: String] = ProcessInfo.processInfo.environment,
        currentDirectoryURL: URL = URL(
            fileURLWithPath: FileManager.default.currentDirectoryPath,
            isDirectory: true
        ),
        bundleURL: URL = Bundle.main.bundleURL,
        apiKeyStore: any OpenRouterAPIKeyStoring =
            OpenRouterKeychainStore()
    ) {
        let loader = {
            try OpenRouterTranscriptionConfiguration.resolve(
                environment: environment,
                currentDirectoryURL: currentDirectoryURL,
                bundleURL: bundleURL,
                apiKeyStore: apiKeyStore
            )
        }
        let configuration = Result {
            try loader()
        }
        switch configuration {
        case let .success(resolution):
            self.init(
                recorder: TraceAudioChunkRecorder(),
                transcriber: resolution.configuration.map {
                    OpenRouterTranscriptionClient(configuration: $0)
                },
                merger: TraceAudioChunkFileMerger(),
                apiKeyState: resolution.state,
                configurationLoader: loader
            )
        case let .failure(error):
            self.init(
                recorder: TraceAudioChunkRecorder(),
                transcriber: nil,
                merger: TraceAudioChunkFileMerger(),
                configurationError: error,
                apiKeyState: .missing,
                configurationLoader: loader
            )
        }
    }

    public init(
        recorder: TraceAudioChunkRecording,
        transcriber: TraceAudioTranscribing?,
        merger: TraceAudioChunkMerging = TraceAudioChunkFileMerger(),
        configurationError: Error? = nil,
        apiKeyState: OpenRouterAPIKeyState? = nil,
        configurationLoader:
            (() throws -> OpenRouterTranscriptionResolution)? = nil
    ) {
        self.recorder = recorder
        self.transcriber = transcriber
        self.merger = merger
        self.configurationError = configurationError
        self.apiKeyState = apiKeyState
            ?? (transcriber == nil ? .missing : .externallySupplied)
        self.configurationLoader = configurationLoader
        recorder.onChunkReady = { [weak self] chunk in
            if Thread.isMainThread {
                self?.enqueue(chunk)
            } else {
                DispatchQueue.main.async {
                    self?.enqueue(chunk)
                }
            }
        }
        recorder.onFailure = { [weak self] error in
            if Thread.isMainThread {
                self?.handleRecordingFailure(error)
            } else {
                DispatchQueue.main.async {
                    self?.handleRecordingFailure(error)
                }
            }
        }
        recorder.onLevelChange = { [weak self] level in
            if Thread.isMainThread {
                self?.onLevelChange?(level)
            } else {
                DispatchQueue.main.async {
                    self?.onLevelChange?(level)
                }
            }
        }
    }

    public func reloadConfiguration() throws {
        guard let configurationLoader else {
            return
        }
        guard state.allowsOpenRouterAPIKeyMutation else {
            throw TraceVoiceConfigurationError.captureInProgress
        }
        cancel()
        do {
            let resolution = try configurationLoader()
            apiKeyState = resolution.state
            transcriber = resolution.configuration.map {
                OpenRouterTranscriptionClient(configuration: $0)
            }
            configurationError = resolution.configuration == nil
                ? TraceTranscriptionError.missingAPIKey
                : nil
        } catch {
            apiKeyState = .missing
            transcriber = nil
            configurationError = error
            throw error
        }
    }

    public func requestMicrophoneAccess(
        completion: @escaping (Bool) -> Void
    ) {
        recorder.requestAccess { granted in
            DispatchQueue.main.async {
                completion(granted)
            }
        }
    }

    public func start() throws {
        cancel()
        guard transcriber != nil else {
            throw configurationError
                ?? TraceTranscriptionError.missingAPIKey
        }
        try recorder.start()
        paused = false
        state = .recording(transcribedChunks: 0)
    }

    public func pause() {
        guard case .recording = state else {
            return
        }
        paused = true
        if let chunk = recorder.pause() {
            enqueue(chunk)
        }
        updateActiveState()
    }

    public func resume() throws {
        guard case .paused = state else {
            return
        }
        try recorder.resume()
        paused = false
        updateActiveState()
    }

    public func restart() throws {
        try start()
    }

    public func setPerformanceCritical(_ critical: Bool) {
        guard performanceCritical != critical else {
            return
        }
        performanceCritical = critical
        recorder.setPerformanceCritical(critical)
        if !critical, deferredTranscriptionCompletion != nil {
            DispatchQueue.main.async { [weak self] in
                self?.completeDeferredTranscriptionIfPossible()
            }
        }
    }

    public func finish(
        completion: @escaping (
            Result<TraceVoiceCaptureResult?, Error>
        ) -> Void
    ) {
        switch state {
        case .idle:
            completion(.success(nil))
            return
        case .ready:
            completion(.success(readyResult))
            return
        case .transcribing:
            return
        case .recording, .paused, .failed:
            break
        }

        finishCompletion = completion
        finalizing = true
        lastFailure = nil
        setPerformanceCritical(false)
        if !paused, let finalChunk = recorder.stop() {
            enqueue(finalChunk)
        }
        paused = true
        updateActiveState()
        processNextChunk()
        finishIfReady()
    }

    public func completeCopy() {
        cancel()
    }

    public func cancel() {
        generation &+= 1
        activeTask?.cancel()
        activeTask = nil
        recorder.cancel()
        pendingChunks.removeAll(keepingCapacity: false)
        allChunks.removeAll(keepingCapacity: false)
        accumulator = OrderedTranscriptAccumulator()
        processedChunkCount = 0
        finalizing = false
        paused = false
        performanceCritical = false
        deferredTranscriptionCompletion = nil
        readyResult = nil
        finishCompletion = nil
        lastFailure = nil
        state = .idle
    }

    private func enqueue(_ chunk: TraceAudioChunk) {
        if !allChunks.contains(where: { $0.index == chunk.index }) {
            allChunks.append(chunk)
        }
        if !pendingChunks.contains(where: { $0.index == chunk.index }) {
            pendingChunks.append(chunk)
        }
        updateActiveState()
        processNextChunk()
    }

    private func processNextChunk() {
        guard activeTask == nil,
              lastFailure == nil,
              let transcriber,
              let chunk = pendingChunks.first
        else {
            finishIfReady()
            return
        }
        let generation = generation
        let controller = self
        activeTask = Task(priority: .utility) {
            do {
                let result = try await transcriber.transcribe(
                    audioAt: chunk.fileURL
                )
                await MainActor.run {
                    controller.complete(
                        chunk,
                        with: result,
                        generation: generation
                    )
                }
            } catch {
                await MainActor.run {
                    controller.fail(
                        chunk,
                        with: error,
                        generation: generation
                    )
                }
            }
        }
    }

    private func complete(
        _ chunk: TraceAudioChunk,
        with result: TraceTranscriptionResult,
        generation: UInt64
    ) {
        guard generation == self.generation,
              pendingChunks.first?.index == chunk.index
        else {
            return
        }
        if performanceCritical {
            deferredTranscriptionCompletion =
                DeferredTranscriptionCompletion(
                    chunk: chunk,
                    result: result,
                    generation: generation
                )
            return
        }
        activeTask = nil
        pendingChunks.removeFirst()
        accumulator.add(
            chunkIndex: chunk.index,
            result: result,
            appClockStartTimeSeconds: chunk.appClockStartTimeSeconds
        )
        if !result.normalizedText.isEmpty {
            onTranscriptChange?(
                TraceVoiceTranscriptSnapshot(
                    text: accumulator.text,
                    words: accumulator.words
                )
            )
        }
        processedChunkCount += 1
        updateActiveState()
        processNextChunk()
    }

    private func completeDeferredTranscriptionIfPossible() {
        guard !performanceCritical,
              let deferred = deferredTranscriptionCompletion
        else {
            return
        }
        deferredTranscriptionCompletion = nil
        complete(
            deferred.chunk,
            with: deferred.result,
            generation: deferred.generation
        )
    }

    private func fail(
        _ chunk: TraceAudioChunk,
        with error: Error,
        generation: UInt64
    ) {
        guard generation == self.generation,
              pendingChunks.first?.index == chunk.index
        else {
            return
        }
        activeTask = nil
        lastFailure = error
        stopRecordingForFailure()
        state = .failed(error.localizedDescription)
        if finalizing {
            finalizing = false
            let completion = finishCompletion
            finishCompletion = nil
            completion?(.failure(error))
        }
    }

    private func handleRecordingFailure(_ error: Error) {
        lastFailure = error
        stopRecordingForFailure()
        state = .failed(error.localizedDescription)
        if finalizing {
            finalizing = false
            let completion = finishCompletion
            finishCompletion = nil
            completion?(.failure(error))
        }
    }

    private func updateActiveState() {
        if let lastFailure {
            state = .failed(lastFailure.localizedDescription)
        } else if finalizing {
            state = .transcribing(
                completedChunks: processedChunkCount,
                pendingChunks: pendingChunks.count
            )
        } else if paused {
            state = .paused(
                transcribedChunks: processedChunkCount
            )
        } else {
            state = .recording(
                transcribedChunks: processedChunkCount
            )
        }
    }

    private func finishIfReady() {
        guard finalizing,
              activeTask == nil,
              pendingChunks.isEmpty,
              lastFailure == nil
        else {
            return
        }
        guard !allChunks.isEmpty else {
            completeMerge(
                audioFileURL: nil,
                generation: generation
            )
            return
        }
        let chunks = allChunks
        let generation = generation
        let merger = merger
        let controller = self
        activeTask = Task {
            do {
                let outputURL = try await Task.detached(
                    priority: .utility
                ) {
                    try merger.merge(chunks)
                }.value
                await MainActor.run {
                    controller.completeMerge(
                        audioFileURL: outputURL,
                        generation: generation
                    )
                }
            } catch {
                await MainActor.run {
                    controller.failMerge(
                        with: error,
                        generation: generation
                    )
                }
            }
        }
    }

    private func completeMerge(
        audioFileURL: URL?,
        generation: UInt64
    ) {
        guard generation == self.generation else {
            return
        }
        activeTask = nil
        let result = TraceVoiceCaptureResult(
            transcript: accumulator.text,
            words: accumulator.words,
            audioFileURL: audioFileURL
        )
        readyResult = result
        finalizing = false
        state = .ready
        let completion = finishCompletion
        finishCompletion = nil
        completion?(.success(result))
    }

    private func failMerge(
        with error: Error,
        generation: UInt64
    ) {
        guard generation == self.generation else {
            return
        }
        activeTask = nil
        lastFailure = error
        finalizing = false
        state = .failed(error.localizedDescription)
        let completion = finishCompletion
        finishCompletion = nil
        completion?(.failure(error))
    }

    private func stopRecordingForFailure() {
        guard !paused else {
            return
        }
        paused = true
        if let finalChunk = recorder.pause() {
            if !allChunks.contains(where: { $0.index == finalChunk.index }) {
                allChunks.append(finalChunk)
            }
            if !pendingChunks.contains(where: {
                $0.index == finalChunk.index
            }) {
                pendingChunks.append(finalChunk)
            }
        }
        onLevelChange?(0)
    }
}
