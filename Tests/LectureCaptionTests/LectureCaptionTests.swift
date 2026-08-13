import AppKit
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

@Test func mainWindowDoesNotUseMoveToActiveSpaceBehavior() {
    let behavior: NSWindow.CollectionBehavior = [.managed, .moveToActiveSpace]
    let standardized = MainWindowSpaceBehavior.standardized(behavior)

    #expect(standardized.contains(.managed))
    #expect(!standardized.contains(.moveToActiveSpace))
}

@Test func mainWindowRestoresAfterActivationOnlyWithoutAnExistingKeyWindow() {
    #expect(MainWindowSpaceBehavior.shouldRestoreAfterActivation(
        hasKeyWindow: false,
        mainWindowIsVisible: true
    ))
    #expect(!MainWindowSpaceBehavior.shouldRestoreAfterActivation(
        hasKeyWindow: true,
        mainWindowIsVisible: true
    ))
    #expect(!MainWindowSpaceBehavior.shouldRestoreAfterActivation(
        hasKeyWindow: false,
        mainWindowIsVisible: false
    ))
}

@Test func floatingCaptionDisplayModesKeepTheLatestRelevantSegments() {
    let segments = (0..<6).map { index in
        CaptionSegment(
            sequence: index,
            sourceText: "source \(index)",
            translatedText: index.isMultiple(of: 2) ? "translation \(index)" : nil,
            startedAt: TimeInterval(index),
            state: index == 5 ? .provisional : .completed
        )
    }

    #expect(FloatingCaptionDisplayMode.bilingual.visibleSegments(from: segments).map(\.sequence) == [3, 4, 5])
    #expect(FloatingCaptionDisplayMode.sourceOnly.visibleSegments(from: segments).map(\.sequence) == [3, 4, 5])
    #expect(FloatingCaptionDisplayMode.translationOnly.visibleSegments(from: segments).map(\.sequence) == [0, 2, 4])
}

@Test func floatingCaptionCollectionBehaviorUsesCompatibleSpaceOptions() {
    let behavior = FloatingCaptionWindowBehavior.collectionBehavior

    #expect(behavior.contains(.canJoinAllSpaces))
    #expect(behavior.contains(.fullScreenAuxiliary))
    #expect(!behavior.contains(.moveToActiveSpace))
}

@Test @MainActor func floatingCaptionOpacityButtonsClampToSupportedRange() {
    let appState = AppState()
    appState.floatingCaptionBackgroundOpacity = 0.35
    #expect(!appState.canDecreaseFloatingCaptionBackgroundOpacity)
    #expect(appState.canIncreaseFloatingCaptionBackgroundOpacity)
    appState.decreaseFloatingCaptionBackgroundOpacity()
    #expect(appState.floatingCaptionBackgroundOpacity == 0.35)

    appState.floatingCaptionBackgroundOpacity = 0.95
    #expect(appState.canDecreaseFloatingCaptionBackgroundOpacity)
    #expect(!appState.canIncreaseFloatingCaptionBackgroundOpacity)
    appState.increaseFloatingCaptionBackgroundOpacity()
    #expect(appState.floatingCaptionBackgroundOpacity == 0.95)
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

@Test func localSessionHistoryStorePersistsCompleteSessionAndReplacesSameID() throws {
    let directory = URL(fileURLWithPath: NSTemporaryDirectory(), isDirectory: true)
        .appendingPathComponent(UUID().uuidString, isDirectory: true)
    let store = LocalSessionHistoryStore(fileURL: directory.appendingPathComponent("Sessions.json"))
    defer { try? FileManager.default.removeItem(at: directory) }

    let session = LectureSession(
        context: LectureContext(
            courseName: "Machine Learning",
            topic: "Optimization",
            sourceLanguage: .english,
            targetLanguage: .simplifiedChinese,
            glossary: []
        ),
        provider: .aliyunRealtime
    )
    let first = CaptionSegment(
        sequence: 0,
        sourceText: "The learning rate controls the step size.",
        translatedText: "学习率控制步长。",
        startedAt: 2,
        endedAt: 5,
        state: .completed
    )
    let second = CaptionSegment(
        sequence: 1,
        sourceText: "We will now optimize the objective.",
        startedAt: 6,
        endedAt: 8,
        state: .translationFailed
    )

    let initial = try store.save(SavedLectureSession(session: session, segments: [first, second]))
    #expect(initial.count == 1)
    let reloaded = try store.load()
    #expect(reloaded.count == 1)
    #expect(reloaded[0].id == session.id)
    #expect(reloaded[0].segments.map(\.sourceText) == [first.sourceText, second.sourceText])
    #expect(reloaded[0].segments[0].translatedText == first.translatedText)

    let replacement = try store.save(SavedLectureSession(session: session, segments: [first]))
    #expect(replacement.count == 1)
    #expect(replacement[0].segments.count == 1)
    #expect(try store.remove(id: session.id).isEmpty)
}

@Test func localSessionHistoryWriterCoalescesRapidSessionSnapshots() async throws {
    let directory = URL(fileURLWithPath: NSTemporaryDirectory(), isDirectory: true)
        .appendingPathComponent(UUID().uuidString, isDirectory: true)
    let store = LocalSessionHistoryStore(fileURL: directory.appendingPathComponent("Sessions.json"))
    let writer = LocalSessionHistoryWriter(store: store)
    defer { try? FileManager.default.removeItem(at: directory) }

    let session = LectureSession(
        context: LectureContext(
            courseName: "Algorithms",
            topic: "Sorting",
            sourceLanguage: .english,
            targetLanguage: .simplifiedChinese,
            glossary: []
        ),
        provider: .aliyunRealtime
    )
    let first = CaptionSegment(sequence: 0, sourceText: "First", startedAt: 0, state: .committed)
    let second = CaptionSegment(sequence: 1, sourceText: "Second", startedAt: 1, state: .completed)

    await writer.submit(SavedLectureSession(session: session, segments: [first]), revision: 1)
    await writer.submit(SavedLectureSession(session: session, segments: [first, second]), revision: 2)
    try await waitUntil(timeout: .seconds(2)) {
        (try? store.load().count) == 1
    }

    let records = try store.load()
    let record = try #require(records.first)
    #expect(records.count == 1)
    #expect(record.segments.map(\.sourceText) == ["First", "Second"])
}

@Test func localSessionHistoryWriterFlushesPendingSnapshotImmediately() async throws {
    let directory = URL(fileURLWithPath: NSTemporaryDirectory(), isDirectory: true)
        .appendingPathComponent(UUID().uuidString, isDirectory: true)
    let store = LocalSessionHistoryStore(fileURL: directory.appendingPathComponent("Sessions.json"))
    let writer = LocalSessionHistoryWriter(store: store)
    defer { try? FileManager.default.removeItem(at: directory) }

    let session = LectureSession(
        context: LectureContext(
            courseName: "Databases",
            topic: "Indexes",
            sourceLanguage: .english,
            targetLanguage: .simplifiedChinese,
            glossary: []
        ),
        provider: .aliyunRealtime
    )
    let segment = CaptionSegment(sequence: 0, sourceText: "Final record", startedAt: 0, state: .committed)

    await writer.submit(SavedLectureSession(session: session, segments: [segment]), revision: 1)
    try await writer.flush()

    let records = try store.load()
    #expect(records.count == 1)
    #expect(records[0].id == session.id)
    #expect(records[0].segments.first?.sourceText == "Final record")
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
        recentContext: [TranslationContextSegment(
            sourceText: "We optimize the objective.",
            translatedText: "我们优化目标函数。"
        )],
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
    #expect(messages.count == 4)
    #expect(messages[0]["content"]?.contains("learning rate=学习率") == true)
    #expect(messages[1]["content"] == "上文原文：We optimize the objective.")
    #expect(messages[2]["role"] == "assistant")
    #expect(messages[2]["content"] == "我们优化目标函数。")
    #expect(messages[3]["content"] == "当前原文：The learning rate controls the size of each optimization step.")
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
        recentContext: [TranslationContextSegment(sourceText: "Earlier sentence.", translatedText: nil)],
        courseName: "A course title",
        topic: "A topic",
        glossary: [GlossaryEntry(source: "sentence", target: "句子")],
        sourceLanguage: .english,
        targetLanguage: .simplifiedChinese
    ))

    #expect(translation == "课程上下文未随请求失败。")
    let requests = await transport.requests
    #expect(requests.count == 2)
    let firstMessages = try #require(messages(from: requests[0]))
    let retryMessages = try #require(messages(from: requests[1]))
    #expect(firstMessages[0]["content"]?.contains("课程：A course title") == true)
    #expect(retryMessages.count == 2)
    #expect(retryMessages[1]["content"] == "当前原文：Translate this sentence.")
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
    let requestMessages = try #require(messages(from: request))
    let content = try #require(requestMessages.first?["content"])
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

@Test func replacementTranslationQueueDeliversEventsToNewSessionListener() async throws {
    let oldQueue = TranslationQueue(provider: FakeTranslationProvider(results: [.success("old")]))
    let oldEvents = oldQueue.events()
    let oldListener = Task {
        var iterator = oldEvents.makeAsyncIterator()
        return await iterator.next()
    }
    await oldQueue.cancelAll()
    oldListener.cancel()

    let newQueue = TranslationQueue(provider: FakeTranslationProvider(results: [.success("new")]))
    let newEvents = newQueue.events()
    let segmentID = UUID()
    await newQueue.enqueue(translationRequest(id: segmentID, source: "new source"))

    var iterator = newEvents.makeAsyncIterator()
    #expect(await iterator.next() == .translated(segmentID: segmentID, text: "new"))
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
        #expect(request.value(forHTTPHeaderField: "User-Agent") == "LectureCaption/1.0.0")
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

private func messages(from request: URLRequest) -> [[String: String]]? {
    guard let body = request.httpBody,
          let root = try? JSONSerialization.jsonObject(with: body) as? [String: Any],
          let messages = root["messages"] as? [[String: String]] else {
        return nil
    }
    return messages
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
