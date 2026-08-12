import Foundation

struct SavedLectureSession: Identifiable, Codable, Sendable {
    let session: LectureSession
    let segments: [CaptionSegment]

    var id: UUID { session.id }
    var startedAt: Date { session.startedAt }
    var endedAt: Date? { session.endedAt }
}

enum LocalSessionHistoryStoreError: LocalizedError {
    case invalidFile

    var errorDescription: String? {
        switch self {
        case .invalidFile:
            "本地课堂记录文件格式无效。"
        }
    }
}

struct LocalSessionHistoryStore: Sendable {
    static let `default` = LocalSessionHistoryStore()

    private let fileURL: URL

    init(fileURL: URL? = nil) {
        if let fileURL {
            self.fileURL = fileURL
            return
        }
        let directory = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? URL(fileURLWithPath: NSTemporaryDirectory(), isDirectory: true)
        self.fileURL = directory
            .appendingPathComponent("LectureCaption", isDirectory: true)
            .appendingPathComponent("Sessions.json", isDirectory: false)
    }

    func load() throws -> [SavedLectureSession] {
        guard FileManager.default.fileExists(atPath: fileURL.path) else { return [] }
        let data = try Data(contentsOf: fileURL)
        do {
            return try decoder.decode([SavedLectureSession].self, from: data)
                .sorted { $0.startedAt > $1.startedAt }
        } catch {
            throw LocalSessionHistoryStoreError.invalidFile
        }
    }

    func save(_ record: SavedLectureSession) throws -> [SavedLectureSession] {
        var records = try load()
        records.removeAll { $0.id == record.id }
        records.append(record)
        records.sort { $0.startedAt > $1.startedAt }
        try write(records)
        return records
    }

    func remove(id: UUID) throws -> [SavedLectureSession] {
        var records = try load()
        records.removeAll { $0.id == id }
        try write(records)
        return records
    }

    private func write(_ records: [SavedLectureSession]) throws {
        try FileManager.default.createDirectory(
            at: fileURL.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        let data = try encoder.encode(records)
        try data.write(to: fileURL, options: .atomic)
    }

    private var encoder: JSONEncoder {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        return encoder
    }

    private var decoder: JSONDecoder {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return decoder
    }
}

enum LocalSessionHistoryWriteEvent: Sendable {
    case failed(String)
}

actor LocalSessionHistoryWriter {
    private struct PendingSave: Sendable {
        let record: SavedLectureSession
        let revision: Int
    }

    private let store: LocalSessionHistoryStore
    private let eventChannel = LocalSessionHistoryWriteEventChannel()
    private var pendingSaves: [UUID: PendingSave] = [:]
    private var latestRevisionByID: [UUID: Int] = [:]
    private var worker: Task<Void, Never>?

    init(store: LocalSessionHistoryStore) {
        self.store = store
    }

    nonisolated func events() -> AsyncStream<LocalSessionHistoryWriteEvent> {
        eventChannel.stream
    }

    func submit(_ record: SavedLectureSession, revision: Int) {
        guard revision >= latestRevisionByID[record.id, default: 0] else { return }
        latestRevisionByID[record.id] = revision
        pendingSaves[record.id] = PendingSave(record: record, revision: revision)
        guard worker == nil else { return }

        worker = Task { [weak self] in
            await self?.writePendingSavesAfterDelay()
        }
    }

    func remove(id: UUID) throws {
        pendingSaves[id] = nil
        latestRevisionByID[id] = nil
        _ = try store.remove(id: id)
    }

    func flush() throws {
        worker?.cancel()
        worker = nil
        try writePendingSaves()
    }

    private func writePendingSaves() throws {
        let saves = pendingSaves.values.sorted { $0.revision < $1.revision }
        pendingSaves.removeAll(keepingCapacity: true)
        worker = nil

        for pendingSave in saves {
            guard pendingSave.revision == latestRevisionByID[pendingSave.record.id] else { continue }
            _ = try store.save(pendingSave.record)
        }
    }

    private func writePendingSavesAfterDelay() async {
        do {
            try await Task.sleep(for: .milliseconds(250))
            try writePendingSaves()
        } catch is CancellationError {
            return
        } catch {
            eventChannel.yield(.failed(error.localizedDescription))
        }
    }
}

private final class LocalSessionHistoryWriteEventChannel: @unchecked Sendable {
    let stream: AsyncStream<LocalSessionHistoryWriteEvent>
    private let continuation: AsyncStream<LocalSessionHistoryWriteEvent>.Continuation

    init() {
        var capturedContinuation: AsyncStream<LocalSessionHistoryWriteEvent>.Continuation?
        stream = AsyncStream { continuation in
            capturedContinuation = continuation
        }
        continuation = capturedContinuation!
    }

    func yield(_ event: LocalSessionHistoryWriteEvent) {
        continuation.yield(event)
    }
}
