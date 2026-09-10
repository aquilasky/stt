import AppKit
import AVFoundation
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

@Test func captionFocusLevelEmphasizesConfirmedLineWithoutDimmingHistory() {
    #expect(CaptionFocusLevel.forSegment(at: 3, focusedIndex: 3, isProvisional: false) == .focused)
    #expect(CaptionFocusLevel.forSegment(at: 2, focusedIndex: 3, isProvisional: false) == .standard)
    #expect(CaptionFocusLevel.forSegment(at: 4, focusedIndex: 3, isProvisional: true) == .provisional)
    #expect(CaptionFocusLevel.focused.sourceScale > CaptionFocusLevel.standard.sourceScale)
    #expect(CaptionFocusLevel.standard.opacity == 1)
}

@Test func captionFocusOrderKeepsOnlyTheLatestProvisionalSegmentBelowConfirmedContent() {
    let firstProvisional = CaptionSegment(sequence: 0, sourceText: "first partial", startedAt: 0, state: .provisional)
    let confirmed = CaptionSegment(sequence: 1, sourceText: "confirmed", startedAt: 1, state: .completed)
    let secondProvisional = CaptionSegment(sequence: 2, sourceText: "second partial", startedAt: 2, state: .provisional)

    let displayed = CaptionFocusLevel.orderedSegments([firstProvisional, confirmed, secondProvisional])

    #expect(displayed.map(\.id) == [confirmed.id, secondProvisional.id])
}

@Test func captionFocusAnchorTracksLatestContentAndLayout() {
    let segmentID = UUID()
    let provisional = CaptionSegment(
        id: segmentID,
        sequence: 0,
        sourceText: "partial",
        startedAt: 0,
        state: .provisional
    )
    let priorConfirmed = CaptionSegment(
        sequence: 0,
        sourceText: "confirmed sentence",
        startedAt: 0,
        state: .completed
    )
    let initialAnchor = CaptionFocusAnchor(
        segments: [priorConfirmed, provisional],
        fontSize: 18,
        viewportSize: CGSize(width: 900, height: 620)
    )

    var committed = provisional
    committed.sourceText = "final sentence"
    committed.translatedText = "最终句子"
    committed.state = .completed
    let updatedAnchor = CaptionFocusAnchor(
        segments: [priorConfirmed, committed],
        fontSize: 20,
        viewportSize: CGSize(width: 900, height: 720)
    )

    #expect(initialAnchor.scrollTargetSegmentID == priorConfirmed.id)
    #expect(updatedAnchor.scrollTargetSegmentID == committed.id)
    #expect(initialAnchor != updatedAnchor)
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

@Test @MainActor func captionTimestampVisibilityDefaultsToVisibleAndCanBeToggled() {
    let appState = AppState()

    #expect(appState.isCaptionTimestampVisible)
    appState.isCaptionTimestampVisible = false
    #expect(!appState.isCaptionTimestampVisible)
}

@Test @MainActor func displaySleepPreventionDefaultsOffAndCanBeToggledRepeatedly() {
    let appState = AppState()

    #expect(!appState.isDisplaySleepPreventionEnabled)
    appState.setDisplaySleepPreventionEnabled(true)
    #expect(appState.isDisplaySleepPreventionEnabled)
    appState.setDisplaySleepPreventionEnabled(true)
    #expect(appState.isDisplaySleepPreventionEnabled)
    appState.setDisplaySleepPreventionEnabled(false)
    #expect(!appState.isDisplaySleepPreventionEnabled)
}

@Test @MainActor func continuationCopiesSelectedHistoryInTimeOrderAndPreservesSources() throws {
    let directory = URL(fileURLWithPath: NSTemporaryDirectory(), isDirectory: true)
        .appendingPathComponent(UUID().uuidString, isDirectory: true)
    let store = LocalSessionHistoryStore(fileURL: directory.appendingPathComponent("Sessions.json"))
    defer { try? FileManager.default.removeItem(at: directory) }

    let earlier = makeSavedSession(
        startedAt: Date(timeIntervalSinceReferenceDate: 100),
        courseName: "Algorithms",
        topic: "Graphs",
        segments: [CaptionSegment(sequence: 3, sourceText: "Earlier", translatedText: "较早", startedAt: 4, endedAt: 5, state: .completed)]
    )
    let later = makeSavedSession(
        startedAt: Date(timeIntervalSinceReferenceDate: 200),
        courseName: "Databases",
        topic: "Indexes",
        segments: [CaptionSegment(sequence: 7, sourceText: "Later", translatedText: "较晚", startedAt: 8, endedAt: 9, state: .completed)]
    )
    _ = try store.save(later)
    _ = try store.save(earlier)
    let appState = AppState(sessionHistoryStore: store)

    appState.prepareContinuation(from: [earlier.id, later.id])

    #expect(appState.captionSegments.map(\.sourceText) == ["Earlier", "Later"])
    #expect(appState.captionSegments.map(\.sequence) == [0, 1])
    #expect(appState.captionSegments.map(\.translatedText) == ["较早", "较晚"])
    #expect(appState.captionSegments.map(\.startedAt) == [4, 8])
    #expect(appState.captionSegments.map(\.endedAt) == [5, 9])
    #expect(appState.captionSegments.map(\.state.rawValue) == ["completed", "completed"])
    #expect(Set(appState.captionSegments.map(\.id)).isDisjoint(with: Set([earlier.segments[0].id, later.segments[0].id])))
    #expect(appState.courseName == "Databases")
    #expect(appState.topic == "Indexes")
    let loadedSources = try store.load()
    #expect(loadedSources.map(\.id) == [later.id, earlier.id])
    #expect(loadedSources[0].segments.map(\.sourceText) == ["Later"])
    #expect(loadedSources[1].segments.map(\.sourceText) == ["Earlier"])
}

@Test func continuationTimelineStartsAtOrAfterCopiedHistory() {
    var timeline = SessionTimeline(audioSessionStartedAt: 100, initialMappedTime: 9)
    timeline.beginProviderTask(audioStartedAt: 100)

    let mapped = timeline.map(.partial(providerSentenceID: "new", text: "New", startedAt: 0))

    guard case let .partial(_, _, startedAt) = mapped else {
        Issue.record("Expected a mapped partial event")
        return
    }
    #expect(startedAt >= 9)
}

@Test func transcriptStabilizerAppendsToCopiedContinuationSegments() {
    let copiedSegment = CaptionSegment(
        sequence: 0,
        sourceText: "Copied history",
        translatedText: "已载入历史",
        startedAt: 5,
        endedAt: 6,
        state: .completed
    )
    var stabilizer = TranscriptStabilizer(segments: [copiedSegment])
    stabilizer.beginProviderTask()

    _ = stabilizer.apply(.partial(providerSentenceID: "new", text: "New segment", startedAt: 6))
    let updated = stabilizer.apply(.final(providerSentenceID: "new", text: "New segment", startedAt: 6, endedAt: 7))

    #expect(updated.map(\.sourceText) == ["Copied history", "New segment"])
    #expect(updated.map(\.sequence) == [0, 1])
    #expect(updated[0].translatedText == "已载入历史")
    #expect(updated[0].state.rawValue == "completed")
    #expect(updated[1].state.rawValue == "committed")
}

@Test @MainActor func continuationDoesNotCreatePartialSessionForUnavailableSelection() throws {
    let directory = URL(fileURLWithPath: NSTemporaryDirectory(), isDirectory: true)
        .appendingPathComponent(UUID().uuidString, isDirectory: true)
    let store = LocalSessionHistoryStore(fileURL: directory.appendingPathComponent("Sessions.json"))
    defer { try? FileManager.default.removeItem(at: directory) }

    let record = makeSavedSession(
        startedAt: Date(timeIntervalSinceReferenceDate: 100),
        courseName: "Algorithms",
        topic: "Graphs",
        segments: [CaptionSegment(sequence: 0, sourceText: "Source", startedAt: 1, state: .completed)]
    )
    _ = try store.save(record)
    let appState = AppState(sessionHistoryStore: store)

    appState.prepareContinuation(from: [record.id, UUID()])

    #expect(appState.activeSession == nil)
    #expect(appState.captionSegments.isEmpty)
    #expect(appState.captureError == "无法续录课堂记录。所选记录已不可用。")
}

@Test @MainActor func continuationSaveMarksSourcesWithoutChangingTheirSubtitles() async throws {
    let directory = URL(fileURLWithPath: NSTemporaryDirectory(), isDirectory: true)
        .appendingPathComponent(UUID().uuidString, isDirectory: true)
    let store = LocalSessionHistoryStore(fileURL: directory.appendingPathComponent("Sessions.json"))
    defer { try? FileManager.default.removeItem(at: directory) }

    let source = makeSavedSession(
        startedAt: Date(timeIntervalSinceReferenceDate: 100),
        courseName: "Algorithms",
        topic: "Graphs",
        segments: [CaptionSegment(sequence: 0, sourceText: "Copied source", translatedText: "已载入来源", startedAt: 1, endedAt: 2, state: .completed)]
    )
    _ = try store.save(source)
    let appState = AppState(sessionHistoryStore: store)

    appState.prepareContinuation(from: [source.id])
    let targetID = try #require(appState.activeSession?.id)
    appState.captionSegments.append(CaptionSegment(
        sequence: 1,
        sourceText: "New continuation",
        translatedText: "新的续录",
        startedAt: 3,
        endedAt: 4,
        state: .completed
    ))
    appState.saveCurrentSession()

    try await waitUntil(timeout: .seconds(2)) {
        (try? store.load().first(where: { $0.id == source.id })?.mergedIntoStartedAt) != nil
    }
    try await waitUntil(timeout: .seconds(2)) { @MainActor in
        appState.savedSessions.first(where: { $0.id == source.id })?.mergedIntoStartedAt != nil
    }

    let records = try store.load()
    let markedSource = try #require(records.first(where: { $0.id == source.id }))
    let target = try #require(records.first(where: { $0.id == targetID }))
    #expect(markedSource.mergedIntoStartedAt == target.startedAt)
    #expect(markedSource.segments.map(\.sourceText) == ["Copied source"])
    #expect(markedSource.segments.map(\.translatedText) == ["已载入来源"])
    #expect(markedSource.segments.map(\.startedAt) == [1])
    #expect(target.mergedIntoStartedAt == nil)
    #expect(target.segments.map(\.sourceText) == ["Copied source", "New continuation"])
    #expect(LocalSessionRecordName.string(for: markedSource).contains("已合并到"))
}

@Test func historyStoreDecodesRecordsWithoutMergeMarker() throws {
    let directory = URL(fileURLWithPath: NSTemporaryDirectory(), isDirectory: true)
        .appendingPathComponent(UUID().uuidString, isDirectory: true)
    let fileURL = directory.appendingPathComponent("Sessions.json")
    let store = LocalSessionHistoryStore(fileURL: fileURL)
    defer { try? FileManager.default.removeItem(at: directory) }

    var record = makeSavedSession(
        startedAt: Date(timeIntervalSinceReferenceDate: 100),
        courseName: "Algorithms",
        topic: "Graphs",
        segments: [CaptionSegment(sequence: 0, sourceText: "Legacy", startedAt: 1, state: .completed)]
    )
    record.mergedIntoStartedAt = Date(timeIntervalSinceReferenceDate: 200)
    let encoder = JSONEncoder()
    encoder.dateEncodingStrategy = .iso8601
    let encoded = try encoder.encode([record])
    var legacyRecords = try #require(JSONSerialization.jsonObject(with: encoded) as? [[String: Any]])
    legacyRecords[0].removeValue(forKey: "mergedIntoStartedAt")
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    try JSONSerialization.data(withJSONObject: legacyRecords).write(to: fileURL)

    let loaded = try store.load()

    #expect(loaded.count == 1)
    #expect(loaded[0].id == record.id)
    #expect(loaded[0].mergedIntoStartedAt == nil)
    _ = try store.save(makeSavedSession(
        startedAt: Date(timeIntervalSinceReferenceDate: 300),
        courseName: "New record",
        topic: "Unrelated",
        segments: [CaptionSegment(sequence: 0, sourceText: "New", startedAt: 1, state: .completed)]
    ))
    let reloadedData = try Data(contentsOf: fileURL)
    let reloadedRecords = try #require(JSONSerialization.jsonObject(with: reloadedData) as? [[String: Any]])
    let legacyRecord = try #require(reloadedRecords.first { record in
        let segments = record["segments"] as? [[String: Any]]
        return segments?.first?["sourceText"] as? String == "Legacy"
    })
    #expect(legacyRecord["mergedIntoStartedAt"] == nil)
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

@Test func audioPipelineProvidesCurrentPreRollBeforeLocalActivityStarts() throws {
    let pipeline = AudioPipeline(
        activityConfiguration: LocalActivityConfiguration(
            activationHold: 5,
            preRoll: 0.8
        )
    )
    let processedOutput = try pipeline.process(
        buffer: pcmBuffer(sampleCount: 320, value: 12_000),
        startedAt: 4
    )
    let output = try #require(processedOutput)

    #expect(output.activityEvent == .none)
    #expect(output.preRollData?.isEmpty == false)
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

    #expect(singapore.url.absoluteString == "wss://workspace.ap-southeast-1.maas.aliyuncs.com/api-ws/v1/inference")
    #expect(beijing.url.absoluteString == "wss://workspace.cn-beijing.maas.aliyuncs.com/api-ws/v1/inference")
    #expect(singapore.workspaceID == "workspace")
    #expect(beijing.workspaceID == "workspace")
    #expect(AliyunRealtimeSettings.Region.beijing.displayName == "北京")
}

@Test func aliyunSettingsRejectWorkspaceIDsThatCouldChangeTheEndpoint() {
    let invalidWorkspaceIDs = [
        "attacker.example/x",
        "user@host",
        "workspace%2Fpath",
        "workspace。example",
        "workspace／path",
        "workspace\nattacker",
        "workspace id",
        "-workspace",
        "workspace-",
        String(repeating: "a", count: 64)
    ]

    for workspaceID in invalidWorkspaceIDs {
        #expect(AliyunRealtimeSettings(workspaceID: workspaceID).endpoint == nil)
    }
}

@Test func aliyunSettingsNormalizeValidatedWorkspaceIDsBeforeBuildingEndpoints() throws {
    let endpoint = try #require(AliyunRealtimeSettings(workspaceID: "  Workspace-42  ", region: .beijing).endpoint)

    #expect(endpoint.workspaceID == "workspace-42")
    #expect(endpoint.url.scheme == "wss")
    #expect(endpoint.url.host == "workspace-42.cn-beijing.maas.aliyuncs.com")
    #expect(endpoint.url.path == "/api-ws/v1/inference")
    #expect(endpoint.url.user == nil)
    #expect(endpoint.url.password == nil)
    #expect(endpoint.url.port == nil)
    #expect(endpoint.url.query == nil)
    #expect(endpoint.url.fragment == nil)
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

@Test func applicationStorageUsesConfiguredDirectoryAndDebugFallback() {
    #expect(ApplicationStorage.directoryName(configuredName: "LectureCaption-Release") == "LectureCaption-Release")
    #if DEBUG
    #expect(ApplicationStorage.directoryName(configuredName: nil) == "LectureCaption-Debug")
    #else
    #expect(ApplicationStorage.directoryName(configuredName: nil) == "LectureCaption")
    #endif
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

@Test func localSessionRecordNameUsesEnglishAbbreviationsAnd24HourTime() {
    var calendar = Calendar(identifier: .gregorian)
    calendar.timeZone = TimeZone(secondsFromGMT: 0)!
    let startedAt = calendar.date(from: DateComponents(
        year: 2026,
        month: 8,
        day: 19,
        hour: 18,
        minute: 7
    ))!

    #expect(
        LocalSessionRecordName.string(
            startedAt: startedAt,
            timeZone: TimeZone(secondsFromGMT: 0)!
        ) == "Wed_19_Aug_26_18:07"
    )
}

@Test func savedSessionTextExportKeepsCaptionOrderAndOptionallyIncludesTimestamps() throws {
    let record = makeExportRecord()

    let withTimestamps = SavedSessionExporter.text(for: record, includesTimestamps: true)
    let withoutTimestamps = SavedSessionExporter.text(for: record, includesTimestamps: false)
    let timestamp = CaptionTimestampFormatter.string(sessionStartedAt: record.startedAt, offset: 2)

    #expect(withTimestamps.contains("课程：Machine Learning"))
    #expect(withTimestamps.contains("[\(timestamp)] Gradient descent converges."))
    #expect(withTimestamps.contains("[\(timestamp)] 梯度下降会收敛。"))
    let firstCaption = try #require(withTimestamps.firstRange(of: "Gradient descent"))
    let secondCaption = try #require(withTimestamps.firstRange(of: "A \"quote\""))
    #expect(firstCaption.lowerBound < secondCaption.lowerBound)
    #expect(!withoutTimestamps.contains("[\(timestamp)]"))
    #expect(withoutTimestamps.contains("A \"quote\"\n中文"))
}

@Test func savedSessionJSONExportUsesPublicFieldsAndOmitsTimesWhenDisabled() throws {
    let record = makeExportRecord()
    let withTimestamps = try SavedSessionExporter.document(
        for: record,
        format: .json,
        includesTimestamps: true
    )
    let withoutTimestamps = try SavedSessionExporter.document(
        for: record,
        format: .json,
        includesTimestamps: false
    )

    let timedRoot = try #require(JSONSerialization.jsonObject(with: withTimestamps.data) as? [String: Any])
    let untimedRoot = try #require(JSONSerialization.jsonObject(with: withoutTimestamps.data) as? [String: Any])
    let timedSegments = try #require(timedRoot["segments"] as? [[String: Any]])
    let untimedSegments = try #require(untimedRoot["segments"] as? [[String: Any]])

    #expect(timedRoot["formatVersion"] as? Int == 1)
    #expect(timedRoot["sessionStartedAt"] != nil)
    #expect(timedSegments.map { $0["sequence"] as? Int } == [0, 1])
    #expect(timedSegments[0]["startedAtMilliseconds"] as? Int == 2_000)
    #expect(timedSegments[1]["sourceText"] as? String == "A \"quote\"\n中文")
    #expect(untimedRoot["sessionStartedAt"] == nil)
    #expect(untimedRoot["sessionEndedAt"] == nil)
    #expect(untimedSegments.allSatisfy { $0["startedAtMilliseconds"] == nil && $0["endedAtMilliseconds"] == nil })
}

@Test func savedSessionExportUsesSafeDefaultFilenameAndExpectedContentTypes() {
    let record = makeExportRecord(courseName: "Machine/Learning")

    #expect(SavedSessionExporter.defaultFilename(for: record).contains("Machine-Learning"))
    #expect(SavedSessionExportFormat.text.contentType == .plainText)
    #expect(SavedSessionExportFormat.json.contentType == .json)
}

@Test func localSessionHistoryStoreKeepsAnInvalidFileForManualInvestigation() throws {
    let directory = URL(fileURLWithPath: NSTemporaryDirectory(), isDirectory: true)
        .appendingPathComponent(UUID().uuidString, isDirectory: true)
    let fileURL = directory.appendingPathComponent("Sessions.json")
    let store = LocalSessionHistoryStore(fileURL: fileURL)
    defer { try? FileManager.default.removeItem(at: directory) }

    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    let invalidData = Data("not valid JSON".utf8)
    try invalidData.write(to: fileURL)

    let error = #expect(throws: LocalSessionHistoryStoreError.self) { try store.load() }
    #expect(try #require(error).localizedDescription.contains(fileURL.path))

    let record = SavedLectureSession(
        session: LectureSession(
            context: LectureContext(
                courseName: "Investigation",
                topic: "Invalid history file",
                sourceLanguage: .english,
                targetLanguage: .simplifiedChinese,
                glossary: []
            ),
            provider: .aliyunRealtime
        ),
        segments: []
    )
    #expect(throws: LocalSessionHistoryStoreError.self) { try store.save(record) }
    #expect(throws: LocalSessionHistoryStoreError.self) { try store.remove(id: record.id) }
    #expect(FileManager.default.fileExists(atPath: fileURL.path))
    #expect(try Data(contentsOf: fileURL) == invalidData)
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

@Test func aliyunProviderRejectsInvalidEndpointBeforeLoadingCredentialsOrConnecting() async {
    let credentialLoads = SynchronousCallCounter()
    let transport = FakeAliyunWebSocketTransport()
    let provider = AliyunRealtimeSTTProvider(
        settings: AliyunRealtimeSettings(workspaceID: "attacker.example/x", region: .beijing),
        apiKeyLoader: {
            credentialLoads.increment()
            return "test-key"
        },
        transport: transport
    )
    let configuration = SpeechConfiguration(
        provider: .aliyunRealtime,
        sourceLanguage: .automatic,
        sampleRate: 16_000,
        glossary: []
    )

    await #expect(throws: AliyunRealtimeProviderError.invalidEndpoint) {
        try await provider.start(configuration: configuration)
    }

    #expect(credentialLoads.count == 0)
    #expect(await transport.connectRequests.isEmpty)
    #expect(await transport.sentText.isEmpty)
    #expect(await transport.sentData.isEmpty)
}

@Test func aliyunProviderUsesTheValidatedWorkspaceIDForTheRequestHeader() async throws {
    let transport = FakeAliyunWebSocketTransport()
    let provider = AliyunRealtimeSTTProvider(
        settings: AliyunRealtimeSettings(workspaceID: " Workspace-42 ", region: .singapore),
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

    let requests = await transport.connectRequests
    let request = try #require(requests.first)
    #expect(request.url?.host == "workspace-42.ap-southeast-1.maas.aliyuncs.com")
    #expect(request.value(forHTTPHeaderField: "X-DashScope-WorkSpace") == "workspace-42")
    await provider.stop()
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
    _ = stabilizer.apply(.partial(providerSentenceID: "1", text: "The gradient descent", startedAt: 0.4))
    _ = stabilizer.apply(.final(providerSentenceID: "1", text: "The gradient descent converges.", startedAt: 0.8, endedAt: 2))
    _ = stabilizer.apply(.final(providerSentenceID: "1", text: "The gradient descent converges.", startedAt: 0, endedAt: 2))

    #expect(stabilizer.segments.count == 1)
    #expect(stabilizer.segments[0].sourceText == "The gradient descent converges.")
    #expect(stabilizer.segments[0].state == .committed)
    #expect(stabilizer.segments[0].startedAt == 0)
    #expect(stabilizer.segments[0].endedAt == 2)
}

@Test func transcriptStabilizerDoesNotPersistAFinalEndBeforeItsStableStart() {
    var stabilizer = TranscriptStabilizer()

    _ = stabilizer.apply(.partial(providerSentenceID: "1", text: "first", startedAt: 2))
    _ = stabilizer.apply(.final(providerSentenceID: "1", text: "first.", startedAt: 1, endedAt: 1.5))

    #expect(stabilizer.segments[0].startedAt == 2)
    #expect(stabilizer.segments[0].endedAt == 2)
}

@Test func sessionTimelineMapsProviderTimesFromTheActualPreRollStart() {
    var timeline = SessionTimeline(audioSessionStartedAt: 100)
    timeline.beginProviderTask(audioStartedAt: 100.2)

    let partial = timeline.map(.partial(
        providerSentenceID: "1",
        text: "first",
        startedAt: 0.17
    ))
    let final = timeline.map(.final(
        providerSentenceID: "1",
        text: "first.",
        startedAt: 0.17,
        endedAt: 1
    ))

    guard case let .partial(_, _, partialStartedAt)? = partial else {
        Issue.record("Expected a partial transcript event.")
        return
    }
    guard case let .final(_, _, finalStartedAt, finalEndedAt)? = final else {
        Issue.record("Expected a final transcript event.")
        return
    }
    #expect(abs(partialStartedAt - 0.37) < 0.000_001)
    #expect(abs(finalStartedAt - 0.37) < 0.000_001)
    #expect(abs(finalEndedAt - 1.2) < 0.000_001)
}

@Test func sessionTimelineDoesNotRegressWhenANewProviderTaskOverlapsPreRollAudio() {
    var timeline = SessionTimeline(audioSessionStartedAt: 100)
    timeline.beginProviderTask(audioStartedAt: 100)
    _ = timeline.map(.final(
        providerSentenceID: "1",
        text: "first.",
        startedAt: 4,
        endedAt: 6
    ))

    timeline.beginProviderTask(audioStartedAt: 105.2)
    let restartedPartial = timeline.map(.partial(
        providerSentenceID: "1",
        text: "second",
        startedAt: 0.1
    ))
    let restartedFinal = timeline.map(.final(
        providerSentenceID: "1",
        text: "second.",
        startedAt: 0.1,
        endedAt: 1
    ))

    #expect(restartedPartial == .partial(providerSentenceID: "1", text: "second", startedAt: 6.1))
    #expect(restartedFinal == .final(providerSentenceID: "1", text: "second.", startedAt: 6.1, endedAt: 7))
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

private func makeExportRecord(courseName: String = "Machine Learning") -> SavedLectureSession {
    let session = LectureSession(
        context: LectureContext(
            courseName: courseName,
            topic: "Optimization",
            sourceLanguage: .english,
            targetLanguage: .simplifiedChinese,
            glossary: []
        ),
        provider: .aliyunRealtime
    )
    let first = CaptionSegment(
        sequence: 0,
        sourceText: "Gradient descent converges.",
        translatedText: "梯度下降会收敛。",
        startedAt: 2,
        endedAt: 4,
        state: .completed
    )
    let second = CaptionSegment(
        sequence: 1,
        sourceText: "A \"quote\"\n中文",
        startedAt: 6,
        state: .translationFailed
    )
    return SavedLectureSession(session: session, segments: [second, first])
}

private func pcm16Data(sampleCount: Int, value: Int16) -> Data {
    let samples = Array(repeating: value.littleEndian, count: sampleCount)
    return samples.withUnsafeBytes { Data($0) }
}

private func pcmBuffer(sampleCount: Int, value: Int16) -> AVAudioPCMBuffer {
    let format = AVAudioFormat(
        commonFormat: .pcmFormatInt16,
        sampleRate: 16_000,
        channels: 1,
        interleaved: false
    )!
    let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: AVAudioFrameCount(sampleCount))!
    buffer.frameLength = AVAudioFrameCount(sampleCount)
    for index in 0..<sampleCount {
        buffer.int16ChannelData![0][index] = value
    }
    return buffer
}

private actor FakeAliyunWebSocketTransport: AliyunWebSocketTransport {
    private var messages: [String] = []
    private var connected = false
    private let connectError: URLError?
    private(set) var connectRequests: [URLRequest] = []
    private(set) var sentText: [String] = []
    private(set) var sentData: [Data] = []
    private(set) var receiveCallCount = 0

    init(connectError: URLError? = nil) {
        self.connectError = connectError
    }

    func connect(request: URLRequest) async throws {
        connectRequests.append(request)
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

private final class SynchronousCallCounter: @unchecked Sendable {
    private let lock = NSLock()
    private var storedCount = 0

    func increment() {
        lock.lock()
        storedCount += 1
        lock.unlock()
    }

    var count: Int {
        lock.lock()
        defer { lock.unlock() }
        return storedCount
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

private func makeSavedSession(
    startedAt: Date,
    courseName: String,
    topic: String,
    segments: [CaptionSegment]
) -> SavedLectureSession {
    SavedLectureSession(
        session: LectureSession(
            startedAt: startedAt,
            context: LectureContext(
                courseName: courseName,
                topic: topic,
                sourceLanguage: .english,
                targetLanguage: .simplifiedChinese,
                glossary: []
            ),
            provider: .aliyunRealtime
        ),
        segments: segments
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
