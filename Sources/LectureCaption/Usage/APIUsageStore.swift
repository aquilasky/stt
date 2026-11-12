import Foundation

enum APIUsageStoreError: LocalizedError {
    case invalidFile(String)
    case invalidRecord
    case io(path: String, message: String)

    var errorDescription: String? {
        switch self {
        case let .invalidFile(path): "API 用量文件格式无效，请手动检查：\(path)"
        case .invalidRecord: "API 用量指标无效，该记录未写入。"
        case let .io(path, message): "无法读写 API 用量文件：\(path)\n\(message)"
        }
    }
}

enum APIUsageStoreEvent: Sendable {
    case updated([APIUsageRecord])
    case failed(String)
}

actor APIUsageStore {
    let fileURL: URL
    nonisolated let events: AsyncStream<APIUsageStoreEvent>
    nonisolated private let continuation: AsyncStream<APIUsageStoreEvent>.Continuation
    private var records: [String: APIUsageRecord] = [:]
    private var pending: [String: APIUsageRecord] = [:]
    private var hasLoaded = false
    private var storageFailure: String?
    private var writeTask: Task<Void, Never>?

    init(fileURL: URL? = nil) {
        self.fileURL = fileURL ?? ApplicationStorage.applicationSupportDirectory().appendingPathComponent("APIUsage.json")
        let channel = AsyncStream<APIUsageStoreEvent>.makeStream()
        events = channel.stream
        continuation = channel.continuation
    }

    // Synchronous submission schedules only an actor message; no disk access or
    // awaiting a writer occurs on the audio / translation path.
    nonisolated func submit(_ record: APIUsageRecord) {
        Task { await enqueue(record) }
    }

    nonisolated func report(_ message: String) {
        continuation.yield(.failed(message))
    }

    func loadAndPublish() {
        do {
            try loadOnce()
            publish()
        } catch {
            fail(error)
        }
    }

    func enqueue(_ record: APIUsageRecord) {
        guard storageFailure == nil else { return }
        guard record.isValid else {
            report(APIUsageStoreError.invalidRecord.localizedDescription)
            return
        }
        do { try loadOnce() } catch { fail(error); return }
        let previous = pending[record.id] ?? records[record.id]
        if case let .audio(bytes, _) = record.metrics,
           let previous, case let .audio(oldBytes, _) = previous.metrics,
           bytes <= oldBytes { return }
        pending[record.id] = record
        guard writeTask == nil else { return }
        writeTask = Task { [weak self] in
            do { try await Task.sleep(for: .milliseconds(100)) }
            catch { return } // The only failure of this sleep is cancellation.
            await self?.flush()
        }
    }

    func flush() {
        writeTask?.cancel()
        writeTask = nil
        guard storageFailure == nil, !pending.isEmpty else { return }
        var updated = records
        updated.merge(pending) { _, new in new }
        do {
            let encoder = JSONEncoder()
            encoder.dateEncodingStrategy = .iso8601
            encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
            let data = try encoder.encode(updated.values.sorted { $0.id < $1.id })
            try FileManager.default.createDirectory(at: fileURL.deletingLastPathComponent(), withIntermediateDirectories: true)
            try data.write(to: fileURL, options: .atomic)
            records = updated
            pending.removeAll()
            publish()
        } catch {
            fail(APIUsageStoreError.io(path: fileURL.path, message: error.localizedDescription))
        }
    }

    func snapshot() throws -> [APIUsageRecord] {
        try loadOnce()
        return records.values.sorted { $0.occurredAt > $1.occurredAt }
    }

    private func loadOnce() throws {
        guard !hasLoaded else { return }
        guard FileManager.default.fileExists(atPath: fileURL.path) else {
            hasLoaded = true
            return
        }
        let data: Data
        do { data = try Data(contentsOf: fileURL) }
        catch { throw APIUsageStoreError.io(path: fileURL.path, message: error.localizedDescription) }
        do {
            let decoder = JSONDecoder()
            decoder.dateDecodingStrategy = .iso8601
            let decoded = try decoder.decode([APIUsageRecord].self, from: data)
            guard decoded.allSatisfy(\.isValid), Set(decoded.map(\.id)).count == decoded.count else {
                throw APIUsageStoreError.invalidRecord
            }
            records = Dictionary(uniqueKeysWithValues: decoded.map { ($0.id, $0) })
            hasLoaded = true
        } catch { throw APIUsageStoreError.invalidFile(fileURL.path) }
    }

    private func publish() {
        continuation.yield(.updated(records.values.sorted { $0.occurredAt > $1.occurredAt }))
    }

    private func fail(_ error: Error) {
        storageFailure = error.localizedDescription
        report(error.localizedDescription)
    }
}
