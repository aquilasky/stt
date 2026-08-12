import Foundation
import Testing
@testable import LectureCaption

@Test @MainActor func automaticPauseKeepsLocalMonitoringReady() {
    let appState = AppState()

    appState.phase = .monitoringLocal
    appState.receiveInputActivity(true)
    appState.receiveSilence(elapsed: 30)

    #expect(appState.phase == .autoPaused)
    #expect(appState.isInputActive == false)
}

@Test @MainActor func manualPauseDoesNotResumeFromInputActivity() {
    let appState = AppState()

    appState.phase = .monitoringLocal
    appState.receiveInputActivity(true)
    appState.pauseSession()
    appState.receiveInputActivity(true)

    #expect(appState.phase == .manuallyPaused)
}

@Test @MainActor func inputActivityResumesAnAutomaticallyPausedSession() {
    let appState = AppState()

    appState.phase = .monitoringLocal
    appState.receiveInputActivity(true)
    appState.receiveSilence(elapsed: 30)
    appState.receiveInputActivity(true)

    #expect(appState.phase == .recognizing)
}

@Test func captureGenerationInvalidatesAnOlderPendingStart() {
    var gate = CaptureGenerationGate()
    let firstStart = gate.begin()

    gate.invalidate()
    let secondStart = gate.begin()

    #expect(!gate.accepts(firstStart))
    #expect(gate.accepts(secondStart))
}

@Test func chunkerEmitsFixedDurationFramesAndFlushesRemainder() {
    var chunker = PCM16Chunker(sampleRate: 16_000, chunkDuration: 0.04)
    let input = PCM16Frame(
        sequence: 0,
        data: pcm16Data(sampleCount: 960, value: 1_000),
        sampleRate: 16_000,
        startedAt: 5
    )

    let chunks = chunker.append(input)
    let remainder = chunker.flush()

    #expect(chunks.count == 1)
    #expect(chunks[0].data.count == 1_280)
    #expect(chunks[0].startedAt == 5)
    #expect(remainder?.data.count == 640)
    #expect(remainder?.startedAt == 5.04)
}

@Test func preRollBufferKeepsOnlyTheMostRecentAudio() {
    var buffer = PreRollAudioBuffer(maximumDuration: 0.1, sampleRate: 16_000)
    let first = PCM16Frame(sequence: 0, data: pcm16Data(sampleCount: 960, value: 100), sampleRate: 16_000, startedAt: 0)
    let second = PCM16Frame(sequence: 1, data: pcm16Data(sampleCount: 960, value: 200), sampleRate: 16_000, startedAt: 0.06)

    buffer.append(first)
    buffer.append(second)

    #expect(buffer.data.count == 3_200)
    #expect(buffer.data == Data((first.data + second.data).suffix(3_200)))
}

@Test func localActivityDetectorUsesActivationAndReleaseHysteresis() {
    var detector = LocalActivityDetector(
        configuration: LocalActivityConfiguration(
            analysisWindow: 0.02,
            activationHold: 0.04,
            releaseHold: 0.04,
            preRoll: 0.8,
            activationAboveNoiseFloor: 12,
            releaseAboveNoiseFloor: 6
        )
    )
    let quiet = PCM16Frame(sequence: 0, data: pcm16Data(sampleCount: 320, value: 0), sampleRate: 16_000, startedAt: 0)
    let loud = PCM16Frame(sequence: 1, data: pcm16Data(sampleCount: 320, value: 16_000), sampleRate: 16_000, startedAt: 0.02)

    _ = detector.process(quiet)
    let beforeActivation = detector.process(loud)
    let activation = detector.process(loud)
    let beforeRelease = detector.process(quiet)
    let release = detector.process(quiet)

    #expect(beforeActivation.event == .none)
    #expect(activation.event == LocalActivityEvent.started)
    #expect(activation.isActive)
    #expect(beforeRelease.event == .none)
    #expect(release.event == LocalActivityEvent.stopped)
    #expect(!release.isActive)
}

@Test func localActivityDetectorReturnsToIdleForStableBackgroundNoise() {
    var detector = LocalActivityDetector(
        configuration: LocalActivityConfiguration(
            analysisWindow: 0.02,
            activationHold: 0.04,
            releaseHold: 0.04,
            preRoll: 0.8,
            activationAboveNoiseFloor: 12,
            releaseAboveNoiseFloor: 6,
            stableNoiseHold: 0.04,
            stableNoiseToleranceDB: 2,
            maximumAdaptiveNoiseDBFS: -35
        )
    )
    let steadyNoise = PCM16Frame(
        sequence: 0,
        data: pcm16Data(sampleCount: 320, value: 330),
        sampleRate: 16_000,
        startedAt: 0
    )

    var lastMeasurement: LocalActivityMeasurement?
    for _ in 0..<200 {
        lastMeasurement = detector.process(steadyNoise)
    }

    #expect(lastMeasurement?.isActive == false)
    #expect(lastMeasurement?.noiseFloorDBFS ?? -96 > -50)
}

@Test func aliyunRunTaskUsesRealtimeProtocolAndGlossary() throws {
    let configuration = SpeechConfiguration(
        provider: .aliyunRealtime,
        sourceLanguage: .english,
        sampleRate: 16_000,
        glossary: [GlossaryEntry(source: "gradient descent", target: "梯度下降")]
    )
    let json = try AliyunRealtimeProtocol.runTask(
        taskID: "task-1",
        settings: AliyunRealtimeSettings(workspaceID: "workspace", region: .singapore),
        speech: configuration
    )
    let root = try #require(JSONSerialization.jsonObject(with: Data(json.utf8)) as? [String: Any])
    let header = try #require(root["header"] as? [String: Any])
    let payload = try #require(root["payload"] as? [String: Any])
    let parameters = try #require(payload["parameters"] as? [String: Any])

    #expect(header["action"] as? String == "run-task")
    #expect(header["task_id"] as? String == "task-1")
    #expect(header["streaming"] as? String == "duplex")
    #expect(payload["model"] as? String == "qwen-audio-3.0-asr-flash-streaming")
    #expect(parameters["sample_rate"] as? Int == 16_000)
    #expect(parameters["language_hints"] as? [String] == ["en"])
    #expect((parameters["vocabulary"] as? [String: Int])?["gradient descent"] == 3)
}

@Test func aliyunSettingsBuildRegionSpecificEndpoints() throws {
    let singapore = try #require(AliyunRealtimeSettings(workspaceID: "workspace", region: .singapore).endpoint)
    let beijing = try #require(AliyunRealtimeSettings(workspaceID: "workspace", region: .beijing).endpoint)

    #expect(singapore.absoluteString == "wss://workspace.ap-southeast-1.maas.aliyuncs.com/api-ws/v1/inference")
    #expect(beijing.absoluteString == "wss://workspace.cn-beijing.maas.aliyuncs.com/api-ws/v1/inference")
    #expect(AliyunRealtimeSettings.Region.beijing.displayName == "北京")
}

@Test func aliyunBadServerResponseHasActionableHandshakeError() {
    let error = AliyunRealtimeProviderError.handshakeFailed(
        region: .beijing,
        underlying: URLError(.badServerResponse)
    )

    #expect(error.localizedDescription.contains("北京"))
    #expect(error.localizedDescription.contains("API Key"))
}

@Test func localCredentialsStoreWritesAndReadsDashScopeAPIKey() throws {
    let directory = URL(fileURLWithPath: NSTemporaryDirectory(), isDirectory: true)
        .appendingPathComponent(UUID().uuidString, isDirectory: true)
    let fileURL = directory.appendingPathComponent("LocalCredentials.json")
    let store = LocalCredentialsStore(fileURL: fileURL)
    defer { try? FileManager.default.removeItem(at: directory) }

    try store.saveDashScopeAPIKey("test-dashscope-key")

    #expect(try store.loadDashScopeAPIKey() == "test-dashscope-key")
    #expect(FileManager.default.fileExists(atPath: fileURL.path))
}

@Test func localCredentialsStorePreservesBothProviderKeys() throws {
    let directory = URL(fileURLWithPath: NSTemporaryDirectory(), isDirectory: true)
        .appendingPathComponent(UUID().uuidString, isDirectory: true)
    let store = LocalCredentialsStore(fileURL: directory.appendingPathComponent("LocalCredentials.json"))
    defer { try? FileManager.default.removeItem(at: directory) }

    try store.saveDashScopeAPIKey("dashscope-key")
    try store.saveDeepSeekAPIKey("deepseek-key")

    #expect(try store.loadDashScopeAPIKey() == "dashscope-key")
    #expect(try store.loadDeepSeekAPIKey() == "deepseek-key")
}

@Test func deepSeekProviderBuildsNonThinkingTranslationRequest() async throws {
    let transport = FakeDeepSeekHTTPTransport(responses: [
        .success("{\"choices\":[{\"message\":{\"content\":\"学习率控制每一步优化的步长。\"}}]}")
    ])
    let provider = DeepSeekTranslationProvider(
        settings: DeepSeekTranslationSettings(endpoint: URL(string: "https://example.invalid/chat/completions")!),
        apiKeyLoader: { "deepseek-test-key" },
        transport: transport
    )
    let translation = try await provider.translate(TranslationRequest(
        segmentID: UUID(),
        sourceText: "The learning rate controls the size of each optimization step.",
        recentContext: ["We optimize the objective."],
        courseName: "Machine Learning",
        topic: "Optimization",
        glossary: [GlossaryEntry(source: "learning rate", target: "学习率")],
        sourceLanguage: .english,
        targetLanguage: .simplifiedChinese
    ))

    #expect(translation == "学习率控制每一步优化的步长。")
    let request = try #require(await transport.requests.first)
    #expect(request.value(forHTTPHeaderField: "Authorization") == "Bearer deepseek-test-key")
    let body = try #require(request.httpBody)
    let root = try #require(JSONSerialization.jsonObject(with: body) as? [String: Any])
    #expect(root["model"] as? String == "deepseek-v4-flash")
    #expect(root["stream"] as? Bool == false)
    #expect((root["thinking"] as? [String: String])?["type"] == "disabled")
    let messages = try #require(root["messages"] as? [[String: String]])
    #expect(messages.count == 2)
    #expect(messages[1]["content"]?.contains("learning rate=学习率") == true)
    #expect(messages[1]["content"]?.contains("We optimize the objective.") == true)
}

@Test func deepSeekProviderRetriesWithoutCourseContextAfterContextRejection() async throws {
    let transport = FakeDeepSeekHTTPTransport(responses: [
        .failure(statusCode: 400),
        .success("{\"choices\":[{\"message\":{\"content\":\"课程上下文未随请求失败。\"}}]}")
    ])
    let provider = DeepSeekTranslationProvider(
        settings: DeepSeekTranslationSettings(endpoint: URL(string: "https://example.invalid/chat/completions")!),
        apiKeyLoader: { "deepseek-test-key" },
        transport: transport
    )

    let translation = try await provider.translate(TranslationRequest(
        segmentID: UUID(),
        sourceText: "Translate this sentence.",
        recentContext: ["Earlier sentence."],
        courseName: "A course title",
        topic: "A topic",
        glossary: [GlossaryEntry(source: "sentence", target: "句子")],
        sourceLanguage: .english,
        targetLanguage: .simplifiedChinese
    ))

    #expect(translation == "课程上下文未随请求失败。")
    let requests = await transport.requests
    #expect(requests.count == 2)
    let firstContent = try #require(messageContent(from: requests[0]))
    let retryContent = try #require(messageContent(from: requests[1]))
    #expect(firstContent.contains("课程：A course title"))
    #expect(retryContent == "待翻译：Translate this sentence.")
}

@Test func deepSeekProviderBoundsCourseContext() async throws {
    let transport = FakeDeepSeekHTTPTransport(responses: [
        .success("{\"choices\":[{\"message\":{\"content\":\"译文\"}}]}")
    ])
    let provider = DeepSeekTranslationProvider(
        settings: DeepSeekTranslationSettings(endpoint: URL(string: "https://example.invalid/chat/completions")!),
        apiKeyLoader: { "deepseek-test-key" },
        transport: transport
    )

    _ = try await provider.translate(TranslationRequest(
        segmentID: UUID(),
        sourceText: "Source",
        recentContext: [],
        courseName: String(repeating: "c", count: 200),
        topic: String(repeating: "t", count: 300),
        glossary: [],
        sourceLanguage: .english,
        targetLanguage: .simplifiedChinese
    ))

    let request = try #require(await transport.requests.first)
    let content = try #require(messageContent(from: request))
    #expect(content.contains("课程：" + String(repeating: "c", count: 160)))
    #expect(!content.contains(String(repeating: "c", count: 161)))
    #expect(content.contains("主题：" + String(repeating: "t", count: 240)))
    #expect(!content.contains(String(repeating: "t", count: 241)))
}

@Test func translationQueueContinuesInOrderAfterFailure() async throws {
    let provider = FakeTranslationProvider(results: [.failure, .success("第二句译文")])
    let queue = TranslationQueue(provider: provider)
    let firstID = UUID()
    let secondID = UUID()
    let events = queue.events()
    await queue.enqueue(translationRequest(id: firstID, source: "first"))
    await queue.enqueue(translationRequest(id: secondID, source: "second"))

    var iterator = events.makeAsyncIterator()
    #expect(await iterator.next() == .failed(segmentID: firstID))
    #expect(await iterator.next() == .translated(segmentID: secondID, text: "第二句译文"))
    #expect(await provider.receivedSegmentIDs == [firstID, secondID])
}

@Test func translationQueuePreservesOrderForAtomicBatch() async throws {
    let provider = FakeTranslationProvider(results: [.success("first translation"), .success("second translation")])
    let queue = TranslationQueue(provider: provider)
    let firstID = UUID()
    let secondID = UUID()
    let events = queue.events()

    await queue.enqueue([
        translationRequest(id: firstID, source: "first"),
        translationRequest(id: secondID, source: "second")
    ])

    var iterator = events.makeAsyncIterator()
    #expect(await iterator.next() == .translated(segmentID: firstID, text: "first translation"))
    #expect(await iterator.next() == .translated(segmentID: secondID, text: "second translation"))
    #expect(await provider.receivedSegmentIDs == [firstID, secondID])
}

@Test func aliyunDNSFailureHasActionableHandshakeError() async throws {
    let transport = FakeAliyunWebSocketTransport(connectError: URLError(.cannotFindHost))
    let provider = AliyunRealtimeSTTProvider(
        settings: AliyunRealtimeSettings(workspaceID: "workspace", region: .beijing),
        apiKeyLoader: { "test-key" },
        transport: transport
    )
    let configuration = SpeechConfiguration(
        provider: .aliyunRealtime,
        sourceLanguage: .automatic,
        sampleRate: 16_000,
        glossary: []
    )

    await #expect(throws: AliyunRealtimeProviderError.handshakeFailed(
        region: .beijing,
        underlying: URLError(.cannotFindHost)
    )) {
        try await provider.start(configuration: configuration)
    }
}

@Test func aliyunServerErrorDoesNotExposeServerMessage() {
    let error = AliyunServerError(code: "AUTH_ERROR", message: "Bearer secret-value")

    #expect(!error.localizedDescription.contains("secret-value"))
    #expect(!error.localizedDescription.contains("AUTH_ERROR"))
}

@Test func aliyunParserMapsLifecycleResultsAndIgnoresHeartbeats() throws {
    let ready = try AliyunRealtimeProtocol.parseServerEvent(
        "{\"header\":{\"task_id\":\"task-1\",\"event\":\"task-started\"},\"payload\":{}}",
        expectedTaskID: "task-1"
    )
    let partial = try AliyunRealtimeProtocol.parseServerEvent(
        "{\"header\":{\"task_id\":\"task-1\",\"event\":\"result-generated\"},\"payload\":{\"output\":{\"sentence\":{\"text\":\"hello world\",\"begin_time\":170,\"end_time\":920,\"sentence_end\":false,\"sentence_id\":1}}}}",
        expectedTaskID: "task-1"
    )
    let heartbeat = try AliyunRealtimeProtocol.parseServerEvent(
        "{\"header\":{\"task_id\":\"task-1\",\"event\":\"result-generated\"},\"payload\":{\"output\":{\"sentence\":{\"text\":\"\",\"sentence_end\":false,\"sentence_id\":0}}}}",
        expectedTaskID: "task-1"
    )
    let final = try AliyunRealtimeProtocol.parseServerEvent(
        "{\"header\":{\"task_id\":\"task-1\",\"event\":\"result-generated\"},\"payload\":{\"output\":{\"sentence\":{\"text\":\"hello world.\",\"begin_time\":170,\"end_time\":1000,\"sentence_end\":true,\"sentence_id\":1}}}}",
        expectedTaskID: "task-1"
    )

    #expect(ready == .ready)
    #expect(partial == .partial(providerSentenceID: "1", text: "hello world", startedAt: 0.17))
    #expect(heartbeat == nil)
    #expect(final == .final(providerSentenceID: "1", text: "hello world.", startedAt: 0.17, endedAt: 1))
}

@Test func transcriptStabilizerReplacesPartialThenCommitsFinalExactlyOnce() {
    var stabilizer = TranscriptStabilizer()

    _ = stabilizer.apply(.partial(providerSentenceID: "1", text: "The gradient", startedAt: 0))
    _ = stabilizer.apply(.partial(providerSentenceID: "1", text: "The gradient descent", startedAt: 0))
    _ = stabilizer.apply(.final(providerSentenceID: "1", text: "The gradient descent converges.", startedAt: 0, endedAt: 2))
    _ = stabilizer.apply(.final(providerSentenceID: "1", text: "The gradient descent converges.", startedAt: 0, endedAt: 2))

    #expect(stabilizer.segments.count == 1)
    #expect(stabilizer.segments[0].sourceText == "The gradient descent converges.")
    #expect(stabilizer.segments[0].state == .committed)
    #expect(stabilizer.segments[0].endedAt == 2)
}

@Test func transcriptStabilizerHandlesInterleavedSentenceIDs() {
    var stabilizer = TranscriptStabilizer()

    _ = stabilizer.apply(.partial(providerSentenceID: "1", text: "first partial", startedAt: 0))
    _ = stabilizer.apply(.partial(providerSentenceID: "2", text: "second partial", startedAt: 1))
    _ = stabilizer.apply(.final(providerSentenceID: "1", text: "first final", startedAt: 0, endedAt: 2))
    _ = stabilizer.apply(.partial(providerSentenceID: "2", text: "second revised", startedAt: 1))
    _ = stabilizer.apply(.final(providerSentenceID: "2", text: "second final", startedAt: 1, endedAt: 3))

    #expect(stabilizer.segments.count == 2)
    #expect(stabilizer.segments.map(\.sourceText) == ["first final", "second final"])
    #expect(stabilizer.segments.allSatisfy { $0.state == .committed })
}

@Test func aliyunProviderWaitsForTaskStartedBeforeSendingAudio() async throws {
    let transport = FakeAliyunWebSocketTransport()
    let provider = AliyunRealtimeSTTProvider(
        settings: AliyunRealtimeSettings(workspaceID: "workspace"),
        apiKeyLoader: { "test-key" },
        transport: transport
    )
    let configuration = SpeechConfiguration(
        provider: .aliyunRealtime,
        sourceLanguage: .automatic,
        sampleRate: 16_000,
        glossary: []
    )

    try await provider.start(configuration: configuration)
    await #expect(throws: AliyunRealtimeProviderError.taskNotReady) {
        try await provider.send(audio: Data([1, 2]))
    }

    await transport.enqueue("{\"header\":{\"event\":\"task-started\"},\"payload\":{}}")
    try await waitUntil { await transport.sentText.count == 1 }
    try await waitUntil { await provider.isReadyForAudio() }
    try await provider.send(audio: Data([1, 2]))

    #expect(await transport.sentData == [Data([1, 2])])
    await provider.stop()
}

@Test func aliyunProviderSendsFinishTaskOnlyOnce() async throws {
    let transport = FakeAliyunWebSocketTransport()
    let provider = AliyunRealtimeSTTProvider(
        settings: AliyunRealtimeSettings(workspaceID: "workspace"),
        apiKeyLoader: { "test-key" },
        transport: transport
    )
    let configuration = SpeechConfiguration(
        provider: .aliyunRealtime,
        sourceLanguage: .automatic,
        sampleRate: 16_000,
        glossary: []
    )

    try await provider.start(configuration: configuration)
    try await provider.flush()
    try await provider.flush()

    let sentText = await transport.sentText
    #expect(sentText.count == 2)
    #expect(sentText.contains(where: { $0.contains("\"action\":\"finish-task\"") }))
    await provider.stop()
}

@Test func aliyunProviderForwardsServerFailureToEvents() async throws {
    let transport = FakeAliyunWebSocketTransport()
    let provider = AliyunRealtimeSTTProvider(
        settings: AliyunRealtimeSettings(workspaceID: "workspace"),
        apiKeyLoader: { "test-key" },
        transport: transport
    )
    let configuration = SpeechConfiguration(
        provider: .aliyunRealtime,
        sourceLanguage: .automatic,
        sampleRate: 16_000,
        glossary: []
    )
    let stream = provider.events()
    try await provider.start(configuration: configuration)
    await transport.enqueue("{\"header\":{\"event\":\"task-failed\",\"error_code\":\"CLIENT_ERROR\",\"error_message\":\"timeout\"},\"payload\":{}}")

    var iterator = stream.makeAsyncIterator()
    let event = try await iterator.next()
    #expect(event == .failed(code: "CLIENT_ERROR", message: "timeout"))
    await provider.stop()
}

private func pcm16Data(sampleCount: Int, value: Int16) -> Data {
    let samples = Array(repeating: value.littleEndian, count: sampleCount)
    return samples.withUnsafeBytes { Data($0) }
}

private actor FakeAliyunWebSocketTransport: AliyunWebSocketTransport {
    private var messages: [String] = []
    private var connected = false
    private let connectError: URLError?
    private(set) var sentText: [String] = []
    private(set) var sentData: [Data] = []
    private(set) var receiveCallCount = 0

    init(connectError: URLError? = nil) {
        self.connectError = connectError
    }

    func connect(request: URLRequest) async throws {
        if let connectError { throw connectError }
        connected = true
        #expect(request.value(forHTTPHeaderField: "Authorization") == "Bearer test-key")
    }

    func send(text: String) async throws {
        sentText.append(text)
    }

    func send(data: Data) async throws {
        sentData.append(data)
    }

    func receive() async throws -> String {
        receiveCallCount += 1
        while messages.isEmpty {
            try await Task.sleep(for: .milliseconds(5))
        }
        return messages.removeFirst()
    }

    func close() async {
        connected = false
    }

    func enqueue(_ message: String) {
        messages.append(message)
    }
}

private actor FakeDeepSeekHTTPTransport: DeepSeekHTTPTransport {
    enum Response {
        case success(String)
        case failure(statusCode: Int)
    }

    private var responses: [Response]
    private(set) var requests: [URLRequest] = []

    init(responses: [Response]) {
        self.responses = responses
    }

    func perform(_ request: URLRequest) async throws -> (Data, URLResponse) {
        requests.append(request)
        let response = responses.removeFirst()
        let statusCode: Int
        let body: String
        switch response {
        case let .success(value):
            statusCode = 200
            body = value
        case let .failure(value):
            statusCode = value
            body = "{\"error\":\"context rejected\"}"
        }
        return (
            Data(body.utf8),
            HTTPURLResponse(url: request.url!, statusCode: statusCode, httpVersion: nil, headerFields: nil)!
        )
    }
}

private func messageContent(from request: URLRequest) -> String? {
    guard let body = request.httpBody,
          let root = try? JSONSerialization.jsonObject(with: body) as? [String: Any],
          let messages = root["messages"] as? [[String: String]],
          messages.count > 1 else {
        return nil
    }
    return messages[1]["content"]
}

private actor FakeTranslationProvider: TranslationProvider {
    enum Result {
        case success(String)
        case failure
    }

    private var results: [Result]
    private(set) var receivedSegmentIDs: [UUID] = []

    init(results: [Result]) {
        self.results = results
    }

    func translate(_ request: TranslationRequest) async throws -> String {
        receivedSegmentIDs.append(request.segmentID)
        switch results.removeFirst() {
        case let .success(text): return text
        case .failure: throw DeepSeekTranslationError.requestFailed(statusCode: 500)
        }
    }
}

private func translationRequest(id: UUID, source: String) -> TranslationRequest {
    TranslationRequest(
        segmentID: id,
        sourceText: source,
        recentContext: [],
        courseName: "",
        topic: "",
        glossary: [],
        sourceLanguage: .english,
        targetLanguage: .simplifiedChinese
    )
}

private func waitUntil(
    timeout: Duration = .seconds(1),
    predicate: @escaping @Sendable () async -> Bool
) async throws {
    let deadline = ContinuousClock.now + timeout
    while !(await predicate()) {
        guard ContinuousClock.now < deadline else {
            throw TimeoutError()
        }
        try await Task.sleep(for: .milliseconds(5))
    }
}

private struct TimeoutError: Error {}
