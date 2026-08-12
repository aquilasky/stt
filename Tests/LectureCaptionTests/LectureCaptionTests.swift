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
