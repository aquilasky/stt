import Foundation

enum AliyunRealtimeProviderError: LocalizedError, Equatable {
    case missingAPIKey
    case invalidEndpoint
    case taskNotReady
    case taskAlreadyRunning
    case handshakeFailed(region: AliyunRealtimeSettings.Region, underlying: Error)

    var errorDescription: String? {
        switch self {
        case .missingAPIKey: "未配置阿里云 API Key。"
        case .invalidEndpoint: "阿里云 Workspace ID 或区域无效。"
        case .taskNotReady: "语音识别任务尚未准备好接收音频。"
        case .taskAlreadyRunning: "语音识别任务已在运行。"
        case let .handshakeFailed(region, _):
            "阿里云 WebSocket 连接失败（\(region.displayName)）。请检查 API Key、Workspace ID 和地域是否匹配。"
        }
    }

    var failureReason: String? {
        guard case let .handshakeFailed(_, underlying) = self else { return nil }
        return (underlying as? URLError)?.localizedDescription
    }

    static func == (lhs: AliyunRealtimeProviderError, rhs: AliyunRealtimeProviderError) -> Bool {
        switch (lhs, rhs) {
        case (.missingAPIKey, .missingAPIKey),
             (.invalidEndpoint, .invalidEndpoint),
             (.taskNotReady, .taskNotReady),
             (.taskAlreadyRunning, .taskAlreadyRunning):
            true
        case let (.handshakeFailed(leftRegion, _), .handshakeFailed(rightRegion, _)):
            leftRegion == rightRegion
        default:
            false
        }
    }
}

protocol AliyunWebSocketTransport: Sendable {
    func connect(request: URLRequest) async throws
    func send(text: String) async throws
    func send(data: Data) async throws
    func receive() async throws -> String
    func close() async
}

final class URLSessionAliyunWebSocketTransport: AliyunWebSocketTransport, @unchecked Sendable {
    private let session: URLSession
    private var task: URLSessionWebSocketTask?

    init(session: URLSession = .shared) {
        self.session = session
    }

    func connect(request: URLRequest) async throws {
        let task = session.webSocketTask(with: request)
        self.task = task
        task.resume()
    }

    func send(text: String) async throws {
        guard let task else { throw URLError(.notConnectedToInternet) }
        try await task.send(.string(text))
    }

    func send(data: Data) async throws {
        guard let task else { throw URLError(.notConnectedToInternet) }
        try await task.send(.data(data))
    }

    func receive() async throws -> String {
        guard let task else { throw URLError(.notConnectedToInternet) }
        switch try await task.receive() {
        case let .string(text): return text
        case let .data(data): return String(decoding: data, as: UTF8.self)
        @unknown default: throw URLError(.cannotParseResponse)
        }
    }

    func close() async {
        task?.cancel(with: .normalClosure, reason: nil)
        task = nil
    }
}

actor AliyunRealtimeSTTProvider: SpeechRecognitionProvider {
    nonisolated let capabilities = SpeechProviderCapabilities(
        supportsPartialResults: true,
        acceptsStreamingPCM: true,
        supportsVocabulary: true,
        supportedLanguages: [.automatic, .english, .chinese]
    )

    private let settings: AliyunRealtimeSettings
    private let apiKeyLoader: @Sendable () throws -> String?
    private let transport: AliyunWebSocketTransport
    private var taskID: String?
    private var isReady = false
    private var hasSentFinish = false
    private let eventChannel = TranscriptEventChannel()
    private var receiveTask: Task<Void, Never>?

    init(
        settings: AliyunRealtimeSettings,
        apiKeyLoader: @escaping @Sendable () throws -> String?,
        transport: AliyunWebSocketTransport = URLSessionAliyunWebSocketTransport()
    ) {
        self.settings = settings
        self.apiKeyLoader = apiKeyLoader
        self.transport = transport
    }

    func start(configuration: SpeechConfiguration) async throws {
        guard taskID == nil else { throw AliyunRealtimeProviderError.taskAlreadyRunning }
        guard let endpoint = settings.endpoint else {
            throw AliyunRealtimeProviderError.invalidEndpoint
        }
        guard let apiKey = try apiKeyLoader(), !apiKey.isEmpty else {
            throw AliyunRealtimeProviderError.missingAPIKey
        }

        let id = UUID().uuidString.lowercased()
        var request = URLRequest(url: endpoint.url)
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        request.setValue(endpoint.workspaceID, forHTTPHeaderField: "X-DashScope-WorkSpace")
        request.setValue("LectureCaption/1.0.0", forHTTPHeaderField: "User-Agent")

        taskID = id
        hasSentFinish = false
        isReady = false
        do {
            try await transport.connect(request: request)
            receiveTask = Task { [weak self] in
                await self?.receiveEvents(taskID: id)
            }
            try await transport.send(text: AliyunRealtimeProtocol.runTask(
                taskID: id,
                settings: settings,
                speech: configuration
            ))
        } catch {
            let reportedError = userFacingError(for: error)
            await reset(closeTransport: true, finishStreamWith: reportedError)
            throw reportedError
        }
    }

    func send(audio: Data) async throws {
        guard isReady else { throw AliyunRealtimeProviderError.taskNotReady }
        guard !audio.isEmpty else { return }
        try await transport.send(data: audio)
    }

    func flush() async throws {
        guard let taskID, !hasSentFinish else { return }
        hasSentFinish = true
        try await transport.send(text: AliyunRealtimeProtocol.finishTask(taskID: taskID))
    }

    func isReadyForAudio() -> Bool {
        isReady
    }

    nonisolated func events() -> AsyncThrowingStream<TranscriptEvent, Error> {
        eventChannel.stream
    }

    func stop() async {
        receiveTask?.cancel()
        receiveTask = nil
        await reset(closeTransport: true, finishStreamWith: nil)
    }

    private func receiveEvents(taskID: String) async {
        do {
            while !Task.isCancelled {
                let text = try await transport.receive()
                guard let event = try AliyunRealtimeProtocol.parseServerEvent(text, expectedTaskID: taskID) else {
                    continue
                }
                if case .ready = event {
                    isReady = true
                }
                eventChannel.yield(event)
                switch event {
                case .finished:
                    await reset(closeTransport: true, finishStreamWith: nil)
                    return
                case let .failed(code, message):
                    await reset(
                        closeTransport: true,
                        finishStreamWith: AliyunServerError(code: code, message: message)
                    )
                    return
                default:
                    break
                }
            }
        } catch is CancellationError {
            return
        } catch {
            await reset(
                closeTransport: true,
                finishStreamWith: userFacingError(for: error)
            )
        }
    }

    private func userFacingError(for error: Error) -> Error {
        guard let urlError = error as? URLError,
              [
                  URLError.Code.badServerResponse,
                  .networkConnectionLost,
                  .notConnectedToInternet,
                  .cannotConnectToHost,
                  .cannotFindHost,
                  .dnsLookupFailed,
                  .timedOut
              ].contains(urlError.code) else {
            return error
        }
        return AliyunRealtimeProviderError.handshakeFailed(
            region: settings.region,
            underlying: urlError
        )
    }

    private func reset(closeTransport: Bool, finishStreamWith error: Error?) async {
        isReady = false
        taskID = nil
        hasSentFinish = false
        if closeTransport {
            await transport.close()
        }
        if let error {
            eventChannel.finish(throwing: error)
        } else {
            eventChannel.finish()
        }
    }
}

struct AliyunServerError: LocalizedError, Equatable, Sendable {
    let code: String
    let message: String

    var errorDescription: String? {
        "阿里云语音识别任务失败。请检查网络、模型与凭据配置。"
    }
}

private final class TranscriptEventChannel: @unchecked Sendable {
    let stream: AsyncThrowingStream<TranscriptEvent, Error>
    private let continuation: AsyncThrowingStream<TranscriptEvent, Error>.Continuation

    init() {
        var capturedContinuation: AsyncThrowingStream<TranscriptEvent, Error>.Continuation?
        stream = AsyncThrowingStream { continuation in
            capturedContinuation = continuation
        }
        continuation = capturedContinuation!
    }

    func yield(_ event: TranscriptEvent) {
        continuation.yield(event)
    }

    func finish(throwing error: Error? = nil) {
        continuation.finish(throwing: error)
    }
}
