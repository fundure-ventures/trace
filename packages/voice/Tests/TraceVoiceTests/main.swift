import Darwin
import AVFoundation
import Foundation
import Security
import TraceVoice

private struct TestFailure: Error, CustomStringConvertible {
    let description: String
}

private final class FakeOpenRouterAPIKeyStore: OpenRouterAPIKeyStoring {
    var apiKey: String?

    init(apiKey: String? = nil) {
        self.apiKey = apiKey
    }

    func loadAPIKey() throws -> String? {
        apiKey
    }

    func saveAPIKey(_ apiKey: String) throws {
        self.apiKey = apiKey
    }

    func removeAPIKey() throws {
        apiKey = nil
    }
}

private final class StubURLProtocol: URLProtocol {
    static var handler: ((URLRequest) throws -> (HTTPURLResponse, Data))?

    override class func canInit(with request: URLRequest) -> Bool {
        true
    }

    override class func canonicalRequest(
        for request: URLRequest
    ) -> URLRequest {
        request
    }

    override func startLoading() {
        do {
            guard let handler = Self.handler else {
                throw TestFailure(description: "missing URL stub")
            }
            let (response, data) = try handler(request)
            client?.urlProtocol(
                self,
                didReceive: response,
                cacheStoragePolicy: .notAllowed
            )
            client?.urlProtocol(self, didLoad: data)
            client?.urlProtocolDidFinishLoading(self)
        } catch {
            client?.urlProtocol(self, didFailWithError: error)
        }
    }

    override func stopLoading() {}
}

private final class FakeRecorder: TraceAudioChunkRecording {
    var onChunkReady: ((TraceAudioChunk) -> Void)?
    var onFailure: ((Error) -> Void)?
    var onLevelChange: ((Float) -> Void)?
    var authorizationStatus: TraceMicrophoneAuthorization = .authorized
    var finalChunk: TraceAudioChunk?
    var pauseChunk: TraceAudioChunk?
    private(set) var startCount = 0
    private(set) var pauseCount = 0
    private(set) var resumeCount = 0
    private(set) var stopCount = 0
    private(set) var cancelCount = 0
    private(set) var performanceCriticalValues: [Bool] = []

    func requestAccess(completion: @escaping (Bool) -> Void) {
        completion(authorizationStatus == .authorized)
    }

    func start() throws {
        startCount += 1
    }

    func pause() -> TraceAudioChunk? {
        pauseCount += 1
        defer {
            pauseChunk = nil
        }
        return pauseChunk
    }

    func resume() throws {
        resumeCount += 1
    }

    func stop() -> TraceAudioChunk? {
        stopCount += 1
        defer {
            finalChunk = nil
        }
        return finalChunk
    }

    func cancel() {
        cancelCount += 1
    }

    func setPerformanceCritical(_ critical: Bool) {
        performanceCriticalValues.append(critical)
    }

    func emit(_ chunk: TraceAudioChunk) {
        onChunkReady?(chunk)
    }
}

private final class FakeMerger:
    TraceAudioChunkMerging,
    @unchecked Sendable
{
    private(set) var mergedIndices: [Int] = []
    let outputURL = FileManager.default.temporaryDirectory
        .appendingPathComponent("voice.wav")

    func merge(_ chunks: [TraceAudioChunk]) throws -> URL {
        mergedIndices = chunks.map(\.index).sorted()
        return outputURL
    }
}

private final class FakeTranscriber:
    TraceAudioTranscribing,
    @unchecked Sendable
{
    let textByChunk: [Int: String]

    init(textByChunk: [Int: String]) {
        self.textByChunk = textByChunk
    }

    func transcribe(
        audioAt url: URL,
        format: String
    ) async throws -> TraceTranscriptionResult {
        let index = Int(
            url.deletingPathExtension().lastPathComponent
        ) ?? -1
        return result(textByChunk[index] ?? "")
    }
}

private final class FlakyTranscriber:
    TraceAudioTranscribing,
    @unchecked Sendable
{
    private var attempts: [Int: Int] = [:]

    func transcribe(
        audioAt url: URL,
        format: String
    ) async throws -> TraceTranscriptionResult {
        let index = Int(
            url.deletingPathExtension().lastPathComponent
        ) ?? -1
        attempts[index, default: 0] += 1
        if index == 0, attempts[index] == 1 {
            throw TestFailure(description: "temporary upstream failure")
        }
        return result(index == 0 ? "recovered" : "tail")
    }
}

private final class FakeTimedTranscriber:
    TraceAudioTranscribing,
    @unchecked Sendable
{
    func transcribe(
        audioAt url: URL,
        format: String
    ) async throws -> TraceTranscriptionResult {
        timedResult("sketch")
    }
}

private final class SignalingTimedTranscriber:
    TraceAudioTranscribing,
    @unchecked Sendable
{
    private let lock = NSLock()
    private var completed = false

    var didTranscribe: Bool {
        lock.withLock { completed }
    }

    func transcribe(
        audioAt url: URL,
        format: String
    ) async throws -> TraceTranscriptionResult {
        lock.withLock {
            completed = true
        }
        return timedResult("priority")
    }
}

private var failureCount = 0

private func test(
    _ name: String,
    _ body: () async throws -> Void
) async {
    do {
        try await body()
        print("PASS \(name)")
    } catch {
        failureCount += 1
        fputs("FAIL \(name): \(error)\n", stderr)
    }
}

private func expect(
    _ condition: @autoclosure () -> Bool,
    _ message: String,
    file: StaticString = #filePath,
    line: UInt = #line
) throws {
    guard condition() else {
        throw TestFailure(
            description: "\(message) (\(file):\(line))"
        )
    }
}

private func result(_ text: String) -> TraceTranscriptionResult {
    TraceTranscriptionResult(
        text: text,
        language: "en",
        duration: 1,
        segments: nil,
        words: nil,
        usage: nil
    )
}

private func timedResult(_ text: String) -> TraceTranscriptionResult {
    TraceTranscriptionResult(
        text: text,
        language: "en",
        duration: 1,
        segments: nil,
        words: [
            TraceTranscriptionWord(
                word: text,
                start: 0.25,
                end: 0.75,
                speaker: nil
            ),
        ],
        usage: nil
    )
}

private func temporaryAudioFile() throws -> URL {
    let url = FileManager.default.temporaryDirectory
        .appendingPathComponent("trace-voice-\(UUID().uuidString).wav")
    try Data([0x52, 0x49, 0x46, 0x46]).write(to: url)
    return url
}

private func chunk(_ index: Int) -> TraceAudioChunk {
    TraceAudioChunk(
        index: index,
        fileURL: FileManager.default.temporaryDirectory
            .appendingPathComponent("\(index).wav"),
        startTimeSeconds: Double(index) * 12,
        durationSeconds: 12
    )
}

private func writeSilentAudio(
    to url: URL,
    frameCount: AVAudioFrameCount
) throws {
    let format = AVAudioFormat(
        standardFormatWithSampleRate: 16_000,
        channels: 1
    )!
    let file = try AVAudioFile(
        forWriting: url,
        settings: format.settings
    )
    guard let buffer = AVAudioPCMBuffer(
        pcmFormat: format,
        frameCapacity: frameCount
    ),
    let samples = buffer.floatChannelData?[0]
    else {
        throw TestFailure(description: "could not create audio buffer")
    }
    buffer.frameLength = frameCount
    samples.initialize(
        repeating: 0,
        count: Int(frameCount)
    )
    try file.write(from: buffer)
}

private func waitUntil(
    _ condition: @escaping () -> Bool
) async throws {
    for _ in 0..<200 {
        if condition() {
            return
        }
        try await Task.sleep(nanoseconds: 5_000_000)
    }
    throw TestFailure(description: "timed out waiting for async state")
}

Task {
    await test("legacy Keychain ownership errors explain recovery") {
        try expect(
            OpenRouterAPIKeyStoreError
                .keychain(errSecInvalidOwnerEdit)
                .localizedDescription
                == "Trace cannot reset this key because macOS assigned it "
                    + "to an older build. Delete the Trace OpenRouter key "
                    + "in Keychain Access, then add it again.",
            "legacy Keychain ownership errors were not actionable"
        )
    }

    await test("rolling transcription chunks every twelve seconds") {
        try expect(
            TraceAudioChunkRecorder.defaultChunkDurationSeconds == 12,
            "rolling transcription chunk duration changed"
        )
    }

    await test("configuration reads the repository env key without exposing it") {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(
            at: directory,
            withIntermediateDirectories: true
        )
        defer {
            try? FileManager.default.removeItem(at: directory)
        }
        try "OPEN_ROUTER_API_KEY='test-secret'\n".write(
            to: directory.appendingPathComponent(".env"),
            atomically: true,
            encoding: .utf8
        )
        let configuration = try OpenRouterTranscriptionConfiguration.load(
            environment: [:],
            currentDirectoryURL: directory,
            bundleURL: directory.appendingPathComponent("Trace.app")
        )
        try expect(
            configuration.apiKey == "test-secret",
            "the configured OpenRouter key was not loaded"
        )
    }

    await test("bundled Trace resolves the env file above dot-build") {
        let repository = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        let bundle = repository
            .appendingPathComponent(".build", isDirectory: true)
            .appendingPathComponent("Trace.app", isDirectory: true)
        try FileManager.default.createDirectory(
            at: bundle,
            withIntermediateDirectories: true
        )
        defer {
            try? FileManager.default.removeItem(at: repository)
        }
        try "OPEN_ROUTER_API_KEY=bundle-secret\n".write(
            to: repository.appendingPathComponent(".env"),
            atomically: true,
            encoding: .utf8
        )
        let configuration = try OpenRouterTranscriptionConfiguration.load(
            environment: [:],
            currentDirectoryURL: repository.appendingPathComponent("elsewhere"),
            bundleURL: bundle
        )
        try expect(
            configuration.apiKey == "bundle-secret",
            "LaunchServices bundle path did not resolve repository .env"
        )
    }

    await test("supplied OpenRouter keys take precedence over Keychain") {
        let store = FakeOpenRouterAPIKeyStore(apiKey: "keychain-secret")
        let underscored = try OpenRouterTranscriptionConfiguration.resolve(
            environment: ["OPEN_ROUTER_API_KEY": "external-secret"],
            currentDirectoryURL: FileManager.default.temporaryDirectory,
            bundleURL: FileManager.default.temporaryDirectory
                .appendingPathComponent("Trace.app"),
            apiKeyStore: store
        )
        try expect(
            underscored.state == .externallySupplied
                && underscored.configuration?.apiKey == "external-secret",
            "Keychain overrode an externally supplied OpenRouter key"
        )
        let compact = try OpenRouterTranscriptionConfiguration.resolve(
            environment: ["OPENROUTER_API_KEY": "compact-secret"],
            currentDirectoryURL: FileManager.default.temporaryDirectory,
            bundleURL: FileManager.default.temporaryDirectory
                .appendingPathComponent("Trace.app"),
            apiKeyStore: store
        )
        try expect(
            compact.state == .externallySupplied
                && compact.configuration?.apiKey == "compact-secret",
            "OPENROUTER_API_KEY stopped taking precedence over Keychain"
        )

        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(
            at: directory,
            withIntermediateDirectories: true
        )
        defer {
            try? FileManager.default.removeItem(at: directory)
        }
        let envFile = directory.appendingPathComponent("custom.env")
        try "OPEN_ROUTER_API_KEY=file-secret\n".write(
            to: envFile,
            atomically: true,
            encoding: .utf8
        )
        let explicitFile = try OpenRouterTranscriptionConfiguration.resolve(
            environment: ["TRACE_ENV_FILE": envFile.path],
            currentDirectoryURL: directory.appendingPathComponent("elsewhere"),
            bundleURL: directory.appendingPathComponent("Trace.app"),
            apiKeyStore: store
        )
        try expect(
            explicitFile.state == .externallySupplied
                && explicitFile.configuration?.apiKey == "file-secret",
            "TRACE_ENV_FILE stopped taking precedence over Keychain"
        )
    }

    await test("OpenRouter configuration falls back to the Keychain key") {
        let store = FakeOpenRouterAPIKeyStore(apiKey: "keychain-secret")
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(
            at: directory,
            withIntermediateDirectories: true
        )
        defer {
            try? FileManager.default.removeItem(at: directory)
        }
        let resolution = try OpenRouterTranscriptionConfiguration.resolve(
            environment: [:],
            currentDirectoryURL: directory,
            bundleURL: directory.appendingPathComponent("Trace.app"),
            apiKeyStore: store
        )
        try expect(
            resolution.state == .userKeychain
                && resolution.configuration?.apiKey == "keychain-secret",
            "the user OpenRouter key was not loaded from Keychain"
        )
    }

    await test("missing OpenRouter configuration has an explicit state") {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(
            at: directory,
            withIntermediateDirectories: true
        )
        defer {
            try? FileManager.default.removeItem(at: directory)
        }
        let resolution = try OpenRouterTranscriptionConfiguration.resolve(
            environment: [:],
            currentDirectoryURL: directory,
            bundleURL: directory.appendingPathComponent("Trace.app"),
            apiKeyStore: FakeOpenRouterAPIKeyStore()
        )
        try expect(
            resolution.state == .missing
                && resolution.configuration == nil,
            "missing OpenRouter configuration was not modeled explicitly"
        )
    }

    await test("voice configuration reloads after a BYOK key is saved") {
        let store = FakeOpenRouterAPIKeyStore()
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(
            at: directory,
            withIntermediateDirectories: true
        )
        defer {
            try? FileManager.default.removeItem(at: directory)
        }
        let controller = TraceVoiceCaptureController(
            environment: [:],
            currentDirectoryURL: directory,
            bundleURL: directory.appendingPathComponent("Trace.app"),
            apiKeyStore: store
        )
        try expect(
            controller.apiKeyState == .missing && !controller.isConfigured,
            "voice unexpectedly started configured without a key"
        )
        try store.saveAPIKey("saved-secret")
        try controller.reloadConfiguration()
        try expect(
            controller.apiKeyState == .userKeychain
                && controller.isConfigured,
            "voice did not reload the saved BYOK key"
        )
        try store.removeAPIKey()
        try controller.reloadConfiguration()
        try expect(
            controller.apiKeyState == .missing && !controller.isConfigured,
            "voice stayed configured after the BYOK key was removed"
        )
    }

    await test("active voice states block OpenRouter key mutation") {
        try expect(
            TraceVoiceCaptureState.idle.allowsOpenRouterAPIKeyMutation
                && TraceVoiceCaptureState.failed("test")
                    .allowsOpenRouterAPIKeyMutation
                && !TraceVoiceCaptureState.recording(transcribedChunks: 0)
                    .allowsOpenRouterAPIKeyMutation
                && !TraceVoiceCaptureState.paused(transcribedChunks: 0)
                    .allowsOpenRouterAPIKeyMutation
                && !TraceVoiceCaptureState.transcribing(
                    completedChunks: 0,
                    pendingChunks: 1
                ).allowsOpenRouterAPIKeyMutation
                && !TraceVoiceCaptureState.ready
                    .allowsOpenRouterAPIKeyMutation,
            "voice state did not protect active or unconsumed capture data"
        )
    }

    await test("credential reload cannot cancel an active capture") {
        let recorder = FakeRecorder()
        let controller = TraceVoiceCaptureController(
            recorder: recorder,
            transcriber: FakeTranscriber(textByChunk: [:]),
            apiKeyState: .externallySupplied,
            configurationLoader: {
                OpenRouterTranscriptionResolution(
                    state: .userKeychain,
                    configuration: OpenRouterTranscriptionConfiguration(
                        apiKey: "replacement"
                    )
                )
            }
        )
        try controller.start()
        let cancelCount = recorder.cancelCount
        do {
            try controller.reloadConfiguration()
            throw TestFailure(
                description: "active credential reload unexpectedly succeeded"
            )
        } catch {
            try expect(
                error as? TraceVoiceConfigurationError == .captureInProgress,
                "credential reload returned the wrong active-capture error"
            )
        }
        guard case .recording = controller.state else {
            throw TestFailure(
                description: "credential reload changed active voice state"
            )
        }
        try expect(
            recorder.cancelCount == cancelCount,
            "credential reload cancelled the active recorder"
        )
    }

    await test("missing voice configuration routes the toolbar to setup") {
        let missing = TraceVoiceCaptureController(
            recorder: FakeRecorder(),
            transcriber: nil
        )
        try expect(
            missing.toggleIntent(hasDocument: true) == .showSetup,
            "an unconfigured microphone click did not route to setup"
        )

        let configured = TraceVoiceCaptureController(
            recorder: FakeRecorder(),
            transcriber: FakeTranscriber(textByChunk: [:])
        )
        try expect(
            configured.toggleIntent(hasDocument: false) == .ignore
                && configured.toggleIntent(hasDocument: true) == .start,
            "configured idle voice intent changed"
        )
    }

    await test("request encodes MAI timestamps diarization and clean style") {
        let client = OpenRouterTranscriptionClient(
            configuration: OpenRouterTranscriptionConfiguration(
                apiKey: "test-secret"
            )
        )
        let request = try client.makeURLRequest(
            audioData: Data([1, 2, 3])
        )
        try expect(
            request.value(forHTTPHeaderField: "Authorization")
                == "Bearer test-secret",
            "authorization header changed"
        )
        guard let body = request.httpBody,
              let json = try JSONSerialization.jsonObject(
                  with: body
              ) as? [String: Any],
              let audio = json["input_audio"] as? [String: Any],
              let provider = json["provider"] as? [String: Any],
              let options = provider["options"] as? [String: Any],
              let azure = options["azure"] as? [String: Any],
              let diarization = azure["diarization"] as? [String: Any],
              let enhancedMode = azure["enhancedMode"] as? [String: Any],
              let modelOptions =
                  enhancedMode["modelOptions"] as? [String: Any]
        else {
            throw TestFailure(description: "request JSON shape changed")
        }
        try expect(
            json["model"] as? String == "microsoft/mai-transcribe-2",
            "transcription model changed"
        )
        try expect(
            audio["format"] as? String == "wav"
                && audio["data"] as? String
                    == Data([1, 2, 3]).base64EncodedString(),
            "audio payload changed"
        )
        try expect(
            json["response_format"] as? String == "verbose_json"
                && json["timestamp_granularities"] as? [String]
                    == ["segment", "word"],
            "verbose timestamp request changed"
        )
        try expect(
            diarization["enabled"] as? Bool == true
                && modelOptions["transcribeStyle"] as? String == "clean",
            "Azure diarization or clean transcript options changed"
        )
    }

    await test("client decodes speakers timestamps and usage") {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [StubURLProtocol.self]
        let session = URLSession(configuration: configuration)
        StubURLProtocol.handler = { request in
            let response = HTTPURLResponse(
                url: request.url!,
                statusCode: 200,
                httpVersion: nil,
                headerFields: ["X-Generation-Id": "test"]
            )!
            let data = Data(
                """
                {
                  "text": "Hello Trace.",
                  "language": "en",
                  "duration": 1.2,
                  "segments": [
                    {
                      "id": 0,
                      "start": 0.0,
                      "end": 1.2,
                      "text": "Hello Trace.",
                      "speaker": 0
                    }
                  ],
                  "words": [
                    {
                      "word": "Hello",
                      "start": 0.0,
                      "end": 0.5,
                      "speaker": "speaker-a"
                    }
                  ],
                  "usage": {
                    "seconds": 1.2,
                    "total_tokens": 4,
                    "cost": 0.001
                  }
                }
                """.utf8
            )
            return (response, data)
        }
        let client = OpenRouterTranscriptionClient(
            configuration: OpenRouterTranscriptionConfiguration(
                apiKey: "test-secret"
            ),
            session: session
        )
        let audioURL = try temporaryAudioFile()
        defer {
            try? FileManager.default.removeItem(at: audioURL)
        }
        let transcription = try await client.transcribe(
            audioAt: audioURL
        )
        try expect(
            transcription.normalizedText == "Hello Trace.",
            "transcript text changed"
        )
        try expect(
            transcription.segments?.first?.speaker == .number(0)
                && transcription.words?.first?.speaker
                    == .label("speaker-a"),
            "speaker labels changed"
        )
        try expect(
            transcription.usage?.totalTokens == 4
                && transcription.usage?.cost == 0.001,
            "usage fields changed"
        )
    }

    await test("client surfaces OpenRouter failures without success fallback") {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [StubURLProtocol.self]
        let session = URLSession(configuration: configuration)
        StubURLProtocol.handler = { request in
            let response = HTTPURLResponse(
                url: request.url!,
                statusCode: 401,
                httpVersion: nil,
                headerFields: nil
            )!
            return (
                response,
                Data(
                    """
                    {"error":{"message":"invalid key"}}
                    """.utf8
                )
            )
        }
        let client = OpenRouterTranscriptionClient(
            configuration: OpenRouterTranscriptionConfiguration(
                apiKey: "test-secret"
            ),
            session: session
        )
        let audioURL = try temporaryAudioFile()
        defer {
            try? FileManager.default.removeItem(at: audioURL)
        }
        do {
            _ = try await client.transcribe(audioAt: audioURL)
            throw TestFailure(
                description: "HTTP failure returned a transcript"
            )
        } catch let error as TraceTranscriptionError {
            try expect(
                error == .requestFailed(
                    statusCode: 401,
                    message: "invalid key"
                ),
                "OpenRouter error status or message was hidden"
            )
        }
    }

    await test("ordered chunks assemble stable clipboard text") {
        var accumulator = OrderedTranscriptAccumulator()
        accumulator.add(chunkIndex: 2, result: result(" third "))
        accumulator.add(chunkIndex: 0, result: result("first"))
        accumulator.add(chunkIndex: 1, result: result("second"))
        try expect(
            accumulator.text == "first\nsecond\nthird",
            "rolling chunks assembled out of order"
        )
    }

    await test("word timestamps align to the app clock") {
        var accumulator = OrderedTranscriptAccumulator()
        accumulator.add(
            chunkIndex: 0,
            result: timedResult("sketch"),
            appClockStartTimeSeconds: 5_000
        )
        try expect(
            accumulator.words == [
                TraceTimedTranscriptionWord(
                    text: "sketch",
                    startedAtAppClockSeconds: 5_000.25,
                    endedAtAppClockSeconds: 5_000.75
                ),
            ],
            "word offsets were not aligned with the recording app clock"
        )
    }

    await test("temporary chunks merge into one lossless audio file") {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(
            at: directory,
            withIntermediateDirectories: true
        )
        defer {
            try? FileManager.default.removeItem(at: directory)
        }
        let firstURL = directory.appendingPathComponent("0.wav")
        let secondURL = directory.appendingPathComponent("1.wav")
        try writeSilentAudio(to: firstURL, frameCount: 1_600)
        try writeSilentAudio(to: secondURL, frameCount: 2_400)
        let outputURL = try TraceAudioChunkFileMerger().merge([
            TraceAudioChunk(
                index: 1,
                fileURL: secondURL,
                startTimeSeconds: 0.1,
                durationSeconds: 0.15
            ),
            TraceAudioChunk(
                index: 0,
                fileURL: firstURL,
                startTimeSeconds: 0,
                durationSeconds: 0.1
            ),
        ])
        let merged = try AVAudioFile(forReading: outputURL)
        try expect(
            merged.length == 4_000,
            "merged voice.wav did not preserve all recorded frames"
        )
    }

    await test("rolling capture transcribes chunks before final copy") {
        let recorder = FakeRecorder()
        let merger = FakeMerger()
        let controller = TraceVoiceCaptureController(
            recorder: recorder,
            transcriber: FakeTranscriber(
                textByChunk: [
                    0: "first",
                    1: "second",
                ]
            ),
            merger: merger
        )
        try controller.start()
        recorder.emit(chunk(0))
        try await waitUntil {
            controller.state == .recording(transcribedChunks: 1)
        }

        await test("rolling capture publishes timed words as chunks finish") {
            let recorder = FakeRecorder()
            let merger = FakeMerger()
            var update: TraceVoiceTranscriptSnapshot?
            let timedChunk = TraceAudioChunk(
                index: 0,
                fileURL: FileManager.default.temporaryDirectory
                    .appendingPathComponent("0.wav"),
                startTimeSeconds: 0,
                durationSeconds: 1,
                appClockStartTimeSeconds: 8_000
            )
            let transcriber = FakeTimedTranscriber()
            let timedController = TraceVoiceCaptureController(
                recorder: recorder,
                transcriber: transcriber,
                merger: merger
            )
            timedController.onTranscriptChange = {
                update = $0
            }
            try timedController.start()
            recorder.emit(timedChunk)
            try await waitUntil {
                timedController.state == .recording(transcribedChunks: 1)
            }
            try expect(
                update?.text == "sketch"
                    && update?.words.first?.startedAtAppClockSeconds
                        == 8_000.25,
                "completed transcription did not publish aligned words"
            )
            let result = try await withCheckedThrowingContinuation {
                continuation in
                timedController.finish { result in
                    continuation.resume(with: result)
                }
            }
            try expect(
                result?.words == update?.words,
                "final voice result dropped processed word timestamps"
            )
        }
        recorder.finalChunk = chunk(1)
        let result = try await withCheckedThrowingContinuation {
            continuation in
            controller.finish { result in
                continuation.resume(with: result)
            }
        }
        try expect(
            result?.transcript == "first\nsecond"
                && result?.audioFileURL == merger.outputURL,
            "Cmd+C did not reuse rolling transcript plus final tail"
        )
        try expect(
            recorder.startCount == 1
                && recorder.stopCount == 1
                && merger.mergedIndices == [0, 1],
            "rolling recorder lifecycle or audio merge changed"
        )
        try expect(
            controller.state == .ready,
            "voice capture did not finish ready for clipboard"
        )
    }

    await test("Cmd+C retries a failed rolling chunk before copying") {
        let recorder = FakeRecorder()
        let merger = FakeMerger()
        let controller = TraceVoiceCaptureController(
            recorder: recorder,
            transcriber: FlakyTranscriber(),
            merger: merger
        )
        try controller.start()
        recorder.pauseChunk = chunk(1)
        recorder.emit(chunk(0))
        try await waitUntil {
            if case .failed = controller.state {
                return true
            }
            return false
        }
        let result = try await withCheckedThrowingContinuation {
            continuation in
            controller.finish { result in
                continuation.resume(with: result)
            }
        }
        try expect(
            result?.transcript == "recovered\ntail",
            "copy retry dropped the failed chunk or final tail"
        )
    }

    await test("recording can pause and resume without losing chunks") {
        let recorder = FakeRecorder()
        recorder.pauseChunk = chunk(0)
        let merger = FakeMerger()
        let controller = TraceVoiceCaptureController(
            recorder: recorder,
            transcriber: FakeTranscriber(textByChunk: [0: "paused"]),
            merger: merger
        )
        try controller.start()
        controller.pause()
        try expect(
            recorder.pauseCount == 1,
            "stop recording did not finalize the current chunk"
        )
        try await waitUntil {
            controller.state == .paused(transcribedChunks: 1)
        }
        try controller.resume()
        try expect(
            recorder.resumeCount == 1
                && controller.state == .recording(transcribedChunks: 1),
            "start again did not resume the same voice session"
        )
    }

    await test("transcription failure stops microphone recording") {
        let recorder = FakeRecorder()
        let controller = TraceVoiceCaptureController(
            recorder: recorder,
            transcriber: FlakyTranscriber(),
            merger: FakeMerger()
        )
        try controller.start()
        recorder.emit(chunk(0))
        try await waitUntil {
            if case .failed = controller.state {
                return true
            }
            return false
        }
        try expect(
            recorder.pauseCount == 1,
            "transcription failure left the microphone recording"
        )
    }

    await test("pen-critical mode reaches the audio recorder") {
        let recorder = FakeRecorder()
        let controller = TraceVoiceCaptureController(
            recorder: recorder,
            transcriber: FakeTranscriber(textByChunk: [:]),
            merger: FakeMerger()
        )
        controller.setPerformanceCritical(true)
        controller.setPerformanceCritical(false)
        try expect(
            recorder.performanceCriticalValues == [true, false],
            "pen-down did not suspend and resume recorder-side UI work"
        )
    }

    await test("pen-critical mode defers transcription completion") {
        let recorder = FakeRecorder()
        let transcriber = SignalingTimedTranscriber()
        let controller = TraceVoiceCaptureController(
            recorder: recorder,
            transcriber: transcriber,
            merger: FakeMerger()
        )
        var transcriptUpdate: TraceVoiceTranscriptSnapshot?
        controller.onTranscriptChange = {
            transcriptUpdate = $0
        }
        try controller.start()
        controller.setPerformanceCritical(true)
        recorder.emit(
            TraceAudioChunk(
                index: 0,
                fileURL: FileManager.default.temporaryDirectory
                    .appendingPathComponent("0.wav"),
                startTimeSeconds: 0,
                durationSeconds: 1,
                appClockStartTimeSeconds: 9_000
            )
        )
        try await waitUntil {
            transcriber.didTranscribe
        }
        try await Task.sleep(nanoseconds: 20_000_000)
        try expect(
            transcriptUpdate == nil
                && controller.state == .recording(transcribedChunks: 0),
            "transcription completion published during pen-down"
        )
        controller.setPerformanceCritical(false)
        try expect(
            transcriptUpdate == nil,
            "pen-up synchronously drained transcription work"
        )
        try await waitUntil {
            controller.state == .recording(transcribedChunks: 1)
        }
        try expect(
            transcriptUpdate?.text == "priority",
            "deferred transcription did not publish after pen-up"
        )
    }

    await test("finishing drains a pen-deferred transcription") {
        let recorder = FakeRecorder()
        let transcriber = SignalingTimedTranscriber()
        let controller = TraceVoiceCaptureController(
            recorder: recorder,
            transcriber: transcriber,
            merger: FakeMerger()
        )
        try controller.start()
        controller.setPerformanceCritical(true)
        recorder.emit(chunk(0))
        try await waitUntil {
            transcriber.didTranscribe
        }
        try await Task.sleep(nanoseconds: 20_000_000)
        var finishResult:
            Result<TraceVoiceCaptureResult?, Error>?
        controller.finish {
            finishResult = $0
        }
        try await waitUntil {
            finishResult != nil
        }
        let capture = try finishResult?.get()
        try expect(
            capture?.transcript == "priority"
                && controller.state == .ready
                && recorder.performanceCriticalValues == [true, false],
            "voice finalization did not release and preserve deferred work"
        )
    }

    if let liveIndex = CommandLine.arguments.firstIndex(of: "--live"),
       CommandLine.arguments.indices.contains(liveIndex + 1)
    {
        await test("live OpenRouter transcription") {
            let configuration =
                try OpenRouterTranscriptionConfiguration.load()
            let client = OpenRouterTranscriptionClient(
                configuration: configuration
            )
            let result = try await client.transcribe(
                audioAt: URL(
                    fileURLWithPath:
                        CommandLine.arguments[liveIndex + 1]
                )
            )
            try expect(
                !result.normalizedText.isEmpty,
                "live transcription returned no recognized speech"
            )
            try expect(
                result.segments?.isEmpty == false,
                "live transcription omitted segments"
            )
            try expect(
                result.words?.isEmpty == false,
                "live transcription omitted word timestamps"
            )
            try expect(
                result.segments?.first?.speaker != nil,
                "live transcription omitted speaker diarization"
            )
            print(
                "LIVE \(result.normalizedText) "
                    + "segments=\(result.segments?.count ?? 0) "
                    + "words=\(result.words?.count ?? 0)"
            )
        }
    }

    if failureCount > 0 {
        exit(1)
    }
    print("All Trace voice tests passed.")
    exit(0)
}

dispatchMain()
