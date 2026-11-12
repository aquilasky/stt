import Foundation
import Testing
@testable import LectureCaption

private let usageUTC = TimeZone(secondsFromGMT: 0)!
private func usageDate(_ text: String) -> Date { ISO8601DateFormatter().date(from: text)! }
private func usageDirectory() throws -> URL {
    let url = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent("usage-tests-\(UUID())")
    try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
    return url
}
private func usageAudio(task: String = "task", bytes: Int64 = 32_000, at: String = "2026-08-21T02:00:00Z",
                        region: AliyunRealtimeSettings.Region = .beijing) -> APIUsageRecord {
    var record = APIUsageRecord.audio(taskID: task, sessionID: UUID(), model: "qwen-audio-3.0-asr-flash-streaming",
                                     region: region, at: usageDate(at), timeZone: usageUTC)
    record.metrics = .audio(bytes: bytes, region: region)
    return record
}
private let usageTokens = DeepSeekTokenUsage(promptTokens: 1000, cacheHitTokens: 600,
    cacheMissTokens: 400, completionTokens: 100, totalTokens: 1100)

@Test func usageAccumulatorSplitsMidnightAndCountsPreRollOnlyOnce() {
    let accumulator = AudioUsageAccumulator(taskID: "task", sessionID: nil,
        settings: AliyunRealtimeSettings(workspaceID: "fixture"))
    accumulator.add(bytes: 25_600, at: usageDate("2026-08-20T23:59:59Z"), timeZone: usageUTC)
    accumulator.add(bytes: 3200, at: usageDate("2026-08-21T00:00:01Z"), timeZone: usageUTC)
    accumulator.add(bytes: 3200, at: usageDate("2026-08-21T00:00:02Z"), timeZone: usageUTC)
    let snapshots = accumulator.snapshots.sorted { $0.localDay < $1.localDay }
    #expect(snapshots.count == 2)
    #expect(snapshots[0].audioSeconds == 0.8)
    #expect(snapshots[1].audioSeconds == 0.2)
    let summary = APIUsageSummary(records: snapshots, range: .all)
    #expect(summary.speechTaskCount == 1)
    #expect(summary.speechSeconds == 1)
}

@Test func usagePriceHonorsExactPeakBoundariesWeekendsAndChinaHolidays() {
    #expect(UsagePriceSnapshot.isDeepSeekPeak(at: usageDate("2026-08-21T00:59:59Z")) == false)
    #expect(UsagePriceSnapshot.isDeepSeekPeak(at: usageDate("2026-08-21T01:00:00Z")) == true)
    #expect(UsagePriceSnapshot.isDeepSeekPeak(at: usageDate("2026-08-21T03:59:59Z")) == true)
    #expect(UsagePriceSnapshot.isDeepSeekPeak(at: usageDate("2026-08-21T04:00:00Z")) == false)
    #expect(UsagePriceSnapshot.isDeepSeekPeak(at: usageDate("2026-08-21T06:00:00Z")) == true)
    #expect(UsagePriceSnapshot.isDeepSeekPeak(at: usageDate("2026-08-21T10:00:00Z")) == false)
    #expect(UsagePriceSnapshot.isDeepSeekPeak(at: usageDate("2026-08-22T02:00:00Z")) == false)
    #expect(UsagePriceSnapshot.isDeepSeekPeak(at: usageDate("2026-10-05T02:00:00Z")) == false)
    #expect(UsagePriceSnapshot.isDeepSeekPeak(at: usageDate("2027-01-01T02:00:00Z")) == nil)
}

@Test func usagePricesAndSummaryKeepCurrenciesSeparate() {
    let beijing = usageAudio(bytes: 32_000_000)
    let singapore = usageAudio(task: "second", bytes: 32_000_000, region: .singapore)
    let peak = APIUsageRecord.translation(TranslationUsage(tokens: usageTokens, model: "deepseek-v4-flash",
        completedAt: usageDate("2026-08-21T02:00:00Z")), sessionID: nil, timeZone: usageUTC)
    let offPeak = APIUsageRecord.translation(TranslationUsage(tokens: usageTokens, model: "deepseek-v4-flash",
        completedAt: usageDate("2026-08-21T05:00:00Z")), sessionID: nil, timeZone: usageUTC)
    #expect(beijing.estimatedCost == Decimal(33) / 100)
    #expect(singapore.estimatedCost == Decimal(66) / 100)
    #expect(peak.estimatedCost == Decimal(string: "0.0002436"))
    #expect(offPeak.estimatedCost == Decimal(string: "0.0001218"))
    let summary = APIUsageSummary(records: [beijing, singapore, peak, offPeak], range: .all)
    #expect(summary.speechCost == Decimal(99) / 100)
    #expect(summary.translations.count == 2)
    #expect(summary.tokens(\.totalTokens) == 2200)
    #expect(summary.speechGroups.count == 2)
    #expect(summary.unpricedCount == 0)
    #expect(UsagePriceSnapshot.translation(model: "unknown", at: .now) == nil)
}

@Test func usageFiltersUseStoredLocalDateAndInclusiveSevenThirtyDayBoundaries() {
    let now = usageDate("2026-08-21T12:00:00Z")
    let record = usageAudio(at: "2026-08-15T00:00:00Z")
    let old = usageAudio(at: "2026-08-14T23:59:59Z")
    #expect(APIUsageTimeRange.week.contains(record, now: now, timeZone: usageUTC))
    #expect(!APIUsageTimeRange.week.contains(old, now: now, timeZone: usageUTC))
    #expect(APIUsageTimeRange.month.contains(usageAudio(at: "2026-07-23T00:00:00Z"), now: now, timeZone: usageUTC))
    #expect(!APIUsageTimeRange.month.contains(usageAudio(at: "2026-07-22T23:59:59Z"), now: now, timeZone: usageUTC))
    let china = TimeZone(identifier: "Asia/Shanghai")!
    let localRecord = APIUsageRecord.audio(taskID: "local", sessionID: nil, model: "fixture", region: .beijing,
        at: usageDate("2026-08-20T16:01:00Z"), timeZone: china)
    #expect(localRecord.localDay == "2026-08-21")
    #expect(APIUsageTimeRange.today.contains(localRecord, now: now, timeZone: usageUTC))
    #expect(APIUsageTimeRange.all.contains(old, now: now))
}

@Test func usageStoreOverwritesCumulativeSnapshotsAndPersistsOriginalPrice() async throws {
    let directory = try usageDirectory()
    defer { try! FileManager.default.removeItem(at: directory) }
    let file = directory.appendingPathComponent("APIUsage.json")
    let store = APIUsageStore(fileURL: file)
    let first = usageAudio(bytes: 32_000)
    await store.enqueue(first)
    await store.enqueue(usageAudio(bytes: 64_000))
    await store.enqueue(first) // Late older snapshot must not reduce the total.
    await store.flush()
    #expect(try await store.snapshot().count == 1)
    #expect(try await store.snapshot()[0].audioSeconds == 2)
    let reopened = APIUsageStore(fileURL: file)
    let saved = try #require(try await reopened.snapshot().first)
    #expect(saved.price == first.price)
    #expect(saved.estimatedCost == Decimal(66) / 100_000)
    let contents = try String(contentsOf: file, encoding: .utf8)
    #expect(!contents.contains("workspace"))
    #expect(!contents.contains("sourceText"))
    #expect(!contents.contains("APIKey"))
}

@Test func usageStorePreservesInvalidFileAndReportsFullPath() async throws {
    let directory = try usageDirectory()
    defer { try! FileManager.default.removeItem(at: directory) }
    let file = directory.appendingPathComponent("APIUsage.json")
    let original = Data("{invalid-json-evidence}".utf8)
    try original.write(to: file)
    let store = APIUsageStore(fileURL: file)
    var events = store.events.makeAsyncIterator()
    await store.enqueue(usageAudio())
    await store.flush()
    guard case let .failed(message) = await events.next() else { Issue.record("Expected file error"); return }
    #expect(message.contains(file.path))
    #expect(try Data(contentsOf: file) == original)
    await #expect(throws: APIUsageStoreError.self) { try await store.snapshot() }
}

@Test func usageStoreRejectsInconsistentMetricsWithoutCreatingAFile() async throws {
    let directory = try usageDirectory()
    defer { try! FileManager.default.removeItem(at: directory) }
    let file = directory.appendingPathComponent("APIUsage.json")
    let store = APIUsageStore(fileURL: file)
    var events = store.events.makeAsyncIterator()
    await store.enqueue(usageAudio(bytes: -2))
    guard case .failed = await events.next() else { Issue.record("Expected invalid metric error"); return }
    await store.flush()
    #expect(!FileManager.default.fileExists(atPath: file.path))
    #expect(!DeepSeekTokenUsage(promptTokens: 10, cacheHitTokens: 11, cacheMissTokens: 0,
        completionTokens: 1, totalTokens: 11).isValid)
}

@Test func usageHistoryKeepsStoredRatesInsteadOfRepricing() async throws {
    let directory = try usageDirectory()
    defer { try! FileManager.default.removeItem(at: directory) }
    let file = directory.appendingPathComponent("APIUsage.json")
    let original = usageAudio()
    let oldPrice = UsagePriceSnapshot(version: "historical-fixture", effectiveDate: "2026-08-21",
        model: original.model, currency: "CNY", source: UsagePriceSnapshot.aliyunSource,
        period: "每音频秒", inputRate: Decimal(1) / 1000, cacheHitRate: 0, outputRate: 0)
    let historical = APIUsageRecord(id: original.id, taskID: original.taskID, sessionID: nil,
        occurredAt: original.occurredAt, localDay: original.localDay, timeZoneID: original.timeZoneID,
        model: original.model, metrics: original.metrics, price: oldPrice, priceUnavailableReason: nil)
    let store = APIUsageStore(fileURL: file)
    await store.enqueue(historical)
    await store.flush()
    let reopened = APIUsageStore(fileURL: file)
    let saved = try #require(try await reopened.snapshot().first)
    #expect(saved.price?.version == "historical-fixture")
    #expect(saved.estimatedCost == Decimal(1) / 1000)
    #expect(saved.estimatedCost != original.estimatedCost)
}

private struct CancelledUsageHTTPTransport: DeepSeekHTTPTransport {
    func perform(_ request: URLRequest) async throws -> (Data, URLResponse) {
        withUnsafeCurrentTask { $0?.cancel() }
        return try await UsageHTTPTransport().perform(request)
    }
}

@Test func cancelledTranslationDoesNotReportUsageEvenIfTransportReturnsSuccess() async throws {
    // Separate task so cancellation does not cancel the test itself.
    let result = await Task {
        let provider = DeepSeekTranslationProvider(apiKeyLoader: { "fixture-key" }, transport: CancelledUsageHTTPTransport())
        do { _ = try await provider.translate(usageRequest()); return false }
        catch is CancellationError { return true }
        catch { return false }
    }.value
    #expect(result)
}

private let usageResponse = """
{"choices":[{"message":{"content":"测试译文"}}],"usage":{"prompt_tokens":1000,"prompt_cache_hit_tokens":600,"prompt_cache_miss_tokens":400,"completion_tokens":100,"total_tokens":1100}}
"""
private struct UsageHTTPTransport: DeepSeekHTTPTransport {
    var body = usageResponse
    var status = 200
    func perform(_ request: URLRequest) async throws -> (Data, URLResponse) {
        (Data(body.utf8), HTTPURLResponse(url: request.url!, statusCode: status, httpVersion: nil, headerFields: nil)!)
    }
}
private func usageRequest() -> TranslationRequest {
    TranslationRequest(segmentID: UUID(), sourceText: "fixture only", recentContext: [], courseName: "",
        topic: "", glossary: [], sourceLanguage: .english, targetLanguage: .simplifiedChinese)
}

@Test func deepSeekUsageParsesActualResponseAndDoesNotInventMissingTokens() async throws {
    let provider = DeepSeekTranslationProvider(apiKeyLoader: { "fixture-key" }, transport: UsageHTTPTransport())
    let result = try await provider.translate(usageRequest())
    #expect(result.text == "测试译文")
    #expect(result.usage?.tokens == usageTokens)
    #expect(result.usageError == nil)
    let missing = DeepSeekTranslationProvider(apiKeyLoader: { "fixture-key" },
        transport: UsageHTTPTransport(body: "{\"choices\":[{\"message\":{\"content\":\"仍显示译文\"}}]}"))
    let missingResult = try await missing.translate(usageRequest())
    #expect(missingResult.text == "仍显示译文")
    #expect(missingResult.usage == nil)
    #expect(missingResult.usageError != nil)
    let failure = DeepSeekTranslationProvider(apiKeyLoader: { "fixture-key" }, transport: UsageHTTPTransport(status: 500))
    await #expect(throws: DeepSeekTranslationError.self) { try await failure.translate(usageRequest()) }
}

@Test func translationStillReturnsWhenUsageDiskWriteFails() async throws {
    let directory = try usageDirectory()
    defer { try! FileManager.default.removeItem(at: directory) }
    let blocker = directory.appendingPathComponent("not-a-directory")
    try Data("evidence".utf8).write(to: blocker)
    let store = APIUsageStore(fileURL: blocker.appendingPathComponent("APIUsage.json"))
    var usageEvents = store.events.makeAsyncIterator()
    let queue = TranslationQueue(provider: DeepSeekTranslationProvider(apiKeyLoader: { "fixture-key" },
        transport: UsageHTTPTransport()), usageStore: store)
    var translated = queue.events().makeAsyncIterator()
    let request = usageRequest()
    await queue.enqueue(request)
    #expect(await translated.next() == .translated(segmentID: request.segmentID, text: "测试译文"))
    guard case let .failed(message) = await usageEvents.next() else { Issue.record("Expected write failure"); return }
    #expect(message.contains("APIUsage.json"))
    #expect(try String(contentsOf: blocker, encoding: .utf8) == "evidence")
}

private actor UsageWebSocketTransport: AliyunWebSocketTransport {
    private let channel = AsyncThrowingStream<String, Error>.makeStream()
    private var failsSend = false
    private var pendingSend: CheckedContinuation<Void, Never>?
    private var suspendSend = false
    func connect(request: URLRequest) async throws {}
    func send(text: String) async throws {
        let root = try JSONSerialization.jsonObject(with: Data(text.utf8)) as! [String: Any]
        let header = root["header"] as! [String: String]
        let event = header["action"] == "run-task" ? "task-started" : "task-finished"
        channel.continuation.yield("{\"header\":{\"event\":\"\(event)\",\"task_id\":\"\(header["task_id"]!)\"}}")
    }
    func send(data: Data) async throws {
        if failsSend { throw URLError(.networkConnectionLost) }
        if suspendSend { await withCheckedContinuation { pendingSend = $0 } }
    }
    func receive() async throws -> String {
        for try await value in channel.stream { return value }
        throw CancellationError()
    }
    func close() async { channel.continuation.finish() }
    func failNextSend() { failsSend = true }
    func suspendNextSend() { suspendSend = true }
    func hasPendingSend() -> Bool { pendingSend != nil }
    func completeSend() { pendingSend?.resume(); pendingSend = nil }
}

@Test func asrUsageCountsOnlySuccessfulSendsAndFlushesOnStop() async throws {
    let directory = try usageDirectory()
    defer { try! FileManager.default.removeItem(at: directory) }
    let store = APIUsageStore(fileURL: directory.appendingPathComponent("APIUsage.json"))
    let transport = UsageWebSocketTransport()
    let session = UUID()
    let provider = AliyunRealtimeSTTProvider(settings: .init(workspaceID: "fixture"),
        apiKeyLoader: { "fixture-key" }, transport: transport, usageStore: store, sessionID: session)
    var events = provider.events().makeAsyncIterator()
    try await provider.start(configuration: SpeechConfiguration(provider: .aliyunRealtime, sourceLanguage: .english,
        sampleRate: 16_000, glossary: []))
    #expect(try await events.next() == .ready)
    try await provider.send(audio: Data(repeating: 0, count: 25_600))
    try await provider.send(audio: Data(repeating: 0, count: 6400))
    await transport.failNextSend()
    await #expect(throws: URLError.self) { try await provider.send(audio: Data(repeating: 0, count: 3200)) }
    await provider.stop()
    var usageEvents = store.events.makeAsyncIterator()
    guard case let .updated(records) = await usageEvents.next() else { Issue.record("Expected final snapshot"); return }
    #expect(records.count == 1)
    #expect(records[0].audioSeconds == 1)
    #expect(records[0].sessionID == session)
}

@Test func asrUsagePeriodicSnapshotAndLateSendAfterStopAreNotLost() async throws {
    let directory = try usageDirectory()
    defer { try! FileManager.default.removeItem(at: directory) }
    let store = APIUsageStore(fileURL: directory.appendingPathComponent("APIUsage.json"))
    let transport = UsageWebSocketTransport()
    let provider = AliyunRealtimeSTTProvider(settings: .init(workspaceID: "fixture"),
        apiKeyLoader: { "fixture-key" }, transport: transport, usageStore: store, usageSnapshotInterval: .milliseconds(10))
    var events = provider.events().makeAsyncIterator()
    var usageEvents = store.events.makeAsyncIterator()
    try await provider.start(configuration: SpeechConfiguration(provider: .aliyunRealtime, sourceLanguage: .english,
        sampleRate: 16_000, glossary: []))
    #expect(try await events.next() == .ready)
    try await provider.send(audio: Data(repeating: 0, count: 3200))
    guard case let .updated(first) = await usageEvents.next() else { Issue.record("Expected periodic snapshot"); return }
    #expect(first[0].audioSeconds == 0.1)
    await transport.suspendNextSend()
    let sendTask = Task { try await provider.send(audio: Data(repeating: 0, count: 3200)) }
    while !(await transport.hasPendingSend()) { await Task.yield() }
    await provider.stop()
    await transport.completeSend()
    try await sendTask.value
    guard case let .updated(final) = await usageEvents.next() else { Issue.record("Expected late success"); return }
    #expect(final.count == 1)
    #expect(final[0].audioSeconds == 0.2)
}
