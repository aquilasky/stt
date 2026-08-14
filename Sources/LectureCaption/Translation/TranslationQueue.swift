import Foundation

enum TranslationQueueEvent: Sendable, Equatable {
    case translated(segmentID: UUID, sourceText: String, text: String)
    case failed(segmentID: UUID, sourceText: String)
}

actor TranslationQueue {
    private let provider: any TranslationProvider
    private let eventChannel = TranslationQueueEventChannel()
    private var pending: [TranslationRequest] = []
    private var worker: Task<Void, Never>?
    private var generation = 0

    init(provider: any TranslationProvider) {
        self.provider = provider
    }

    nonisolated func events() -> AsyncStream<TranslationQueueEvent> {
        eventChannel.stream
    }

    func enqueue(_ request: TranslationRequest) {
        enqueue([request])
    }

    func enqueue(_ requests: [TranslationRequest]) {
        guard !requests.isEmpty else { return }
        pending.append(contentsOf: requests)
        guard worker == nil else { return }
        let activeGeneration = generation
        worker = Task { [weak self] in
            await self?.process(generation: activeGeneration)
        }
    }

    func cancelAll() {
        generation += 1
        pending.removeAll(keepingCapacity: false)
        worker?.cancel()
        worker = nil
    }

    private func process(generation: Int) async {
        while !Task.isCancelled, generation == self.generation, !pending.isEmpty {
            let request = pending.removeFirst()
            do {
                let translation = try await provider.translate(request)
                guard !Task.isCancelled, generation == self.generation else { return }
                eventChannel.yield(.translated(
                    segmentID: request.segmentID,
                    sourceText: request.sourceText,
                    text: translation
                ))
            } catch {
                guard !Task.isCancelled, generation == self.generation else { return }
                eventChannel.yield(.failed(segmentID: request.segmentID, sourceText: request.sourceText))
            }
        }
        if generation == self.generation {
            worker = nil
        }
    }
}

private final class TranslationQueueEventChannel: @unchecked Sendable {
    let stream: AsyncStream<TranslationQueueEvent>
    private let continuation: AsyncStream<TranslationQueueEvent>.Continuation

    init() {
        var capturedContinuation: AsyncStream<TranslationQueueEvent>.Continuation?
        stream = AsyncStream { continuation in
            capturedContinuation = continuation
        }
        continuation = capturedContinuation!
    }

    func yield(_ event: TranslationQueueEvent) {
        continuation.yield(event)
    }
}
