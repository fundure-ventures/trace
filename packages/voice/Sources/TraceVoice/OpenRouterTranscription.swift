import Foundation

public enum OpenRouterAPIKeyState: Equatable, Sendable {
    case externallySupplied
    case userKeychain
    case missing
}

public struct OpenRouterTranscriptionResolution: Equatable, Sendable {
    public let state: OpenRouterAPIKeyState
    public let configuration: OpenRouterTranscriptionConfiguration?

    public init(
        state: OpenRouterAPIKeyState,
        configuration: OpenRouterTranscriptionConfiguration?
    ) {
        self.state = state
        self.configuration = configuration
    }
}

public struct OpenRouterTranscriptionConfiguration:
    Equatable,
    Sendable
{
    public let apiKey: String
    public let endpoint: URL
    public let referer: String
    public let title: String

    public init(
        apiKey: String,
        endpoint: URL = URL(
            string: "https://openrouter.ai/api/v1/audio/transcriptions"
        )!,
        referer: String = "https://github.com/basiclines/trace",
        title: String = "Trace"
    ) {
        self.apiKey = apiKey
        self.endpoint = endpoint
        self.referer = referer
        self.title = title
    }

    public static func load(
        environment: [String: String] = ProcessInfo.processInfo.environment,
        currentDirectoryURL: URL = URL(
            fileURLWithPath: FileManager.default.currentDirectoryPath,
            isDirectory: true
        ),
        bundleURL: URL = Bundle.main.bundleURL,
        apiKeyStore: any OpenRouterAPIKeyStoring =
            OpenRouterKeychainStore()
    ) throws -> OpenRouterTranscriptionConfiguration {
        let resolution = try resolve(
            environment: environment,
            currentDirectoryURL: currentDirectoryURL,
            bundleURL: bundleURL,
            apiKeyStore: apiKeyStore
        )
        guard let configuration = resolution.configuration else {
            throw TraceTranscriptionError.missingAPIKey
        }
        return configuration
    }

    public static func resolve(
        environment: [String: String] = ProcessInfo.processInfo.environment,
        currentDirectoryURL: URL = URL(
            fileURLWithPath: FileManager.default.currentDirectoryPath,
            isDirectory: true
        ),
        bundleURL: URL = Bundle.main.bundleURL,
        apiKeyStore: any OpenRouterAPIKeyStoring =
            OpenRouterKeychainStore()
    ) throws -> OpenRouterTranscriptionResolution {
        let keyNames = [
            "OPEN_ROUTER_API_KEY",
            "OPENROUTER_API_KEY",
        ]
        for keyName in keyNames {
            if let value = environment[keyName]?.trimmedNonempty {
                return OpenRouterTranscriptionResolution(
                    state: .externallySupplied,
                    configuration: OpenRouterTranscriptionConfiguration(
                        apiKey: value
                    )
                )
            }
        }

        var candidates: [URL] = []
        if let explicitPath = environment["TRACE_ENV_FILE"]?.trimmedNonempty {
            candidates.append(URL(fileURLWithPath: explicitPath))
        }
        candidates.append(
            currentDirectoryURL.appendingPathComponent(".env")
        )
        candidates.append(
            bundleURL
                .deletingLastPathComponent()
                .deletingLastPathComponent()
                .appendingPathComponent(".env")
        )
        // An installed app bundle (e.g. /Applications/Trace.app) is no
        // longer sitting under a repository checkout, so it carries its
        // own copy of the repository .env inside Resources.
        candidates.append(
            bundleURL
                .appendingPathComponent("Contents", isDirectory: true)
                .appendingPathComponent("Resources", isDirectory: true)
                .appendingPathComponent(".env")
        )

        var visited: Set<String> = []
        for candidate in candidates where visited.insert(
            candidate.standardizedFileURL.path
        ).inserted {
            guard let contents = try? String(
                contentsOf: candidate,
                encoding: .utf8
            ) else {
                continue
            }
            let values = parseEnvironment(contents)
            for keyName in keyNames {
                if let value = values[keyName]?.trimmedNonempty {
                    return OpenRouterTranscriptionResolution(
                        state: .externallySupplied,
                        configuration: OpenRouterTranscriptionConfiguration(
                            apiKey: value
                        )
                    )
                }
            }
        }
        if let apiKey = try apiKeyStore.loadAPIKey()?.trimmedNonempty {
            return OpenRouterTranscriptionResolution(
                state: .userKeychain,
                configuration: OpenRouterTranscriptionConfiguration(
                    apiKey: apiKey
                )
            )
        }
        return OpenRouterTranscriptionResolution(
            state: .missing,
            configuration: nil
        )
    }

    private static func parseEnvironment(
        _ contents: String
    ) -> [String: String] {
        var values: [String: String] = [:]
        for rawLine in contents.split(
            whereSeparator: \.isNewline
        ) {
            var line = rawLine.trimmingCharacters(
                in: .whitespacesAndNewlines
            )
            if line.hasPrefix("export ") {
                line.removeFirst("export ".count)
            }
            guard !line.isEmpty,
                  !line.hasPrefix("#"),
                  let separator = line.firstIndex(of: "=")
            else {
                continue
            }
            let key = line[..<separator].trimmingCharacters(
                in: .whitespaces
            )
            var value = line[line.index(after: separator)...]
                .trimmingCharacters(in: .whitespaces)
            if value.count >= 2,
               (value.first == "\"" && value.last == "\"")
                    || (value.first == "'" && value.last == "'")
            {
                value.removeFirst()
                value.removeLast()
            }
            values[key] = value
        }
        return values
    }
}

public enum TraceSpeaker: Equatable, Sendable, Codable {
    case number(Int)
    case label(String)

    public init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        if let number = try? container.decode(Int.self) {
            self = .number(number)
            return
        }
        self = .label(try container.decode(String.self))
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        switch self {
        case let .number(number):
            try container.encode(number)
        case let .label(label):
            try container.encode(label)
        }
    }

    public var displayValue: String {
        switch self {
        case let .number(number):
            return String(number)
        case let .label(label):
            return label
        }
    }
}

public struct TraceTranscriptionSegment:
    Codable,
    Equatable,
    Sendable
{
    public let id: Int?
    public let start: Double?
    public let end: Double?
    public let text: String
    public let speaker: TraceSpeaker?
}

public struct TraceTranscriptionWord:
    Codable,
    Equatable,
    Sendable
{
    public let word: String
    public let start: Double?
    public let end: Double?
    public let speaker: TraceSpeaker?

    public init(
        word: String,
        start: Double?,
        end: Double?,
        speaker: TraceSpeaker?
    ) {
        self.word = word
        self.start = start
        self.end = end
        self.speaker = speaker
    }
}

public struct TraceTimedTranscriptionWord:
    Codable,
    Equatable,
    Sendable
{
    public let text: String
    public let startedAtAppClockSeconds: Double
    public let endedAtAppClockSeconds: Double

    public init(
        text: String,
        startedAtAppClockSeconds: Double,
        endedAtAppClockSeconds: Double
    ) {
        self.text = text
        self.startedAtAppClockSeconds = startedAtAppClockSeconds
        self.endedAtAppClockSeconds = endedAtAppClockSeconds
    }
}

public struct TraceTranscriptionUsage:
    Codable,
    Equatable,
    Sendable
{
    public let seconds: Double?
    public let totalTokens: Int?
    public let inputTokens: Int?
    public let outputTokens: Int?
    public let cost: Double?

    enum CodingKeys: String, CodingKey {
        case seconds
        case totalTokens = "total_tokens"
        case inputTokens = "input_tokens"
        case outputTokens = "output_tokens"
        case cost
    }
}

public struct TraceTranscriptionResult:
    Codable,
    Equatable,
    Sendable
{
    public let text: String
    public let language: String?
    public let duration: Double?
    public let segments: [TraceTranscriptionSegment]?
    public let words: [TraceTranscriptionWord]?
    public let usage: TraceTranscriptionUsage?

    public init(
        text: String,
        language: String?,
        duration: Double?,
        segments: [TraceTranscriptionSegment]?,
        words: [TraceTranscriptionWord]?,
        usage: TraceTranscriptionUsage?
    ) {
        self.text = text
        self.language = language
        self.duration = duration
        self.segments = segments
        self.words = words
        self.usage = usage
    }

    public var normalizedText: String {
        text.trimmingCharacters(in: .whitespacesAndNewlines)
    }
}

public enum TraceTranscriptionError: LocalizedError, Equatable {
    case missingAPIKey
    case emptyAudio
    case invalidResponse
    case requestFailed(statusCode: Int, message: String)

    public var errorDescription: String? {
        switch self {
        case .missingAPIKey:
            return "Trace could not find an OpenRouter API key in the environment, an .env file, or Keychain."
        case .emptyAudio:
            return "Trace did not record enough audio for Dictation."
        case .invalidResponse:
            return "OpenRouter returned an unreadable Dictation response."
        case let .requestFailed(statusCode, message):
            return "OpenRouter Dictation failed (\(statusCode)): \(message)"
        }
    }
}

public protocol TraceAudioTranscribing: Sendable {
    func transcribe(
        audioAt url: URL,
        format: String
    ) async throws -> TraceTranscriptionResult
}

public extension TraceAudioTranscribing {
    func transcribe(
        audioAt url: URL
    ) async throws -> TraceTranscriptionResult {
        try await transcribe(audioAt: url, format: "wav")
    }
}

public final class OpenRouterTranscriptionClient:
    TraceAudioTranscribing,
    @unchecked Sendable
{
    private let configuration: OpenRouterTranscriptionConfiguration
    private let session: URLSession
    private let encoder = JSONEncoder()
    private let decoder = JSONDecoder()

    public init(
        configuration: OpenRouterTranscriptionConfiguration,
        session: URLSession = .shared
    ) {
        self.configuration = configuration
        self.session = session
    }

    public func makeURLRequest(
        audioData: Data,
        format: String = "wav"
    ) throws -> URLRequest {
        guard !audioData.isEmpty else {
            throw TraceTranscriptionError.emptyAudio
        }
        var request = URLRequest(url: configuration.endpoint)
        request.httpMethod = "POST"
        request.timeoutInterval = 75
        request.setValue(
            "Bearer \(configuration.apiKey)",
            forHTTPHeaderField: "Authorization"
        )
        request.setValue(
            "application/json",
            forHTTPHeaderField: "Content-Type"
        )
        request.setValue(
            configuration.referer,
            forHTTPHeaderField: "HTTP-Referer"
        )
        request.setValue(
            configuration.title,
            forHTTPHeaderField: "X-OpenRouter-Title"
        )
        request.httpBody = try encoder.encode(
            OpenRouterTranscriptionRequest(
                model: "microsoft/mai-transcribe-2",
                inputAudio: .init(
                    data: audioData.base64EncodedString(),
                    format: format
                ),
                responseFormat: "verbose_json",
                timestampGranularities: ["segment", "word"],
                provider: .init(
                    options: .init(
                        azure: .init(
                            diarization: .init(enabled: true),
                            phraseList: .init(
                                phrases: [
                                    "Trace",
                                    "OpenRouter",
                                    "MAI-Transcribe",
                                    "Neo Smartpen",
                                ]
                            ),
                            enhancedMode: .init(
                                modelOptions: .init(
                                    transcribeStyle: "clean"
                                )
                            )
                        )
                    )
                )
            )
        )
        return request
    }

    public func transcribe(
        audioAt url: URL,
        format: String = "wav"
    ) async throws -> TraceTranscriptionResult {
        let audioData = try await Task.detached(priority: .utility) {
            try Data(contentsOf: url)
        }.value
        let request = try makeURLRequest(
            audioData: audioData,
            format: format
        )
        let (data, response) = try await session.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse else {
            throw TraceTranscriptionError.invalidResponse
        }
        guard (200..<300).contains(httpResponse.statusCode) else {
            let message = (
                try? decoder.decode(
                    OpenRouterErrorResponse.self,
                    from: data
                )
            )?.error.message ?? HTTPURLResponse.localizedString(
                forStatusCode: httpResponse.statusCode
            )
            throw TraceTranscriptionError.requestFailed(
                statusCode: httpResponse.statusCode,
                message: message
            )
        }
        guard let result = try? decoder.decode(
            TraceTranscriptionResult.self,
            from: data
        ) else {
            throw TraceTranscriptionError.invalidResponse
        }
        return result
    }
}

public struct OrderedTranscriptAccumulator:
    Equatable,
    Sendable
{
    private struct Chunk: Equatable, Sendable {
        let text: String
        let words: [TraceTimedTranscriptionWord]
    }

    private var chunks: [Int: Chunk] = [:]

    public init() {}

    public mutating func add(
        chunkIndex: Int,
        result: TraceTranscriptionResult,
        appClockStartTimeSeconds: Double = 0
    ) {
        let text = result.normalizedText
        guard !text.isEmpty else {
            return
        }
        let words = (result.words ?? []).compactMap { word
            -> TraceTimedTranscriptionWord? in
            guard let start = word.start,
                  let end = word.end,
                  start.isFinite,
                  end.isFinite,
                  start >= 0,
                  end >= start
            else {
                return nil
            }
            return TraceTimedTranscriptionWord(
                text: word.word,
                startedAtAppClockSeconds:
                    appClockStartTimeSeconds + start,
                endedAtAppClockSeconds:
                    appClockStartTimeSeconds + end
            )
        }
        chunks[chunkIndex] = Chunk(text: text, words: words)
    }

    public var text: String {
        chunks
            .sorted { $0.key < $1.key }
            .map(\.value.text)
            .joined(separator: "\n")
    }

    public var words: [TraceTimedTranscriptionWord] {
        chunks
            .sorted { $0.key < $1.key }
            .flatMap(\.value.words)
    }

    public var completedChunkCount: Int {
        chunks.count
    }
}

private struct OpenRouterTranscriptionRequest: Encodable {
    struct InputAudio: Encodable {
        let data: String
        let format: String
    }

    struct Provider: Encodable {
        struct Options: Encodable {
            struct Azure: Encodable {
                struct Diarization: Encodable {
                    let enabled: Bool
                }

                struct PhraseList: Encodable {
                    let phrases: [String]
                }

                struct EnhancedMode: Encodable {
                    struct ModelOptions: Encodable {
                        let transcribeStyle: String

                        enum CodingKeys: String, CodingKey {
                            case transcribeStyle = "transcribe_style"
                        }
                    }

                    let modelOptions: ModelOptions

                    enum CodingKeys: String, CodingKey {
                        case modelOptions = "model_options"
                    }
                }

                let diarization: Diarization
                let phraseList: PhraseList
                let enhancedMode: EnhancedMode

                enum CodingKeys: String, CodingKey {
                    case diarization
                    case phraseList = "phrase_list"
                    case enhancedMode = "enhanced_mode"
                }
            }

            let azure: Azure
        }

        let options: Options
    }

    let model: String
    let inputAudio: InputAudio
    let responseFormat: String
    let timestampGranularities: [String]
    let provider: Provider

    enum CodingKeys: String, CodingKey {
        case model
        case inputAudio = "input_audio"
        case responseFormat = "response_format"
        case timestampGranularities = "timestamp_granularities"
        case provider
    }
}

private struct OpenRouterErrorResponse: Decodable {
    struct ErrorDetail: Decodable {
        let message: String
    }

    let error: ErrorDetail
}

private extension String {
    var trimmedNonempty: String? {
        let value = trimmingCharacters(in: .whitespacesAndNewlines)
        return value.isEmpty ? nil : value
    }
}
