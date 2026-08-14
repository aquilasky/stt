import Foundation

struct TranscriptStabilizer: Sendable {
    private(set) var segments: [CaptionSegment] = []
    private var provisionalIndexes: [String: Int] = [:]
    private var committedProviderIDs: Set<String> = []
    private var autoCommittedProviderIDs: Set<String> = []
    private var nextSequence = 0

    mutating func beginProviderTask() {
        provisionalIndexes.removeAll()
        committedProviderIDs.removeAll()
        autoCommittedProviderIDs.removeAll()
    }

    mutating func apply(_ event: TranscriptEvent) -> [CaptionSegment] {
        switch event {
        case let .partial(providerSentenceID, text, startedAt):
            applyPartial(id: providerSentenceID, text: text, startedAt: startedAt)
        case let .final(providerSentenceID, text, startedAt, endedAt):
            applyFinal(id: providerSentenceID, text: text, startedAt: startedAt, endedAt: endedAt)
        default:
            break
        }
        return segments
    }

    private mutating func applyPartial(id: String, text: String, startedAt: TimeInterval) {
        guard let text = normalized(text) else { return }
        if let index = provisionalIndexes[id], segments.indices.contains(index) {
            segments[index].sourceText = text
            segments[index].startedAt = startedAt
            return
        }

        if autoCommittedProviderIDs.remove(id) != nil {
            committedProviderIDs.remove(id)
        }
        guard !committedProviderIDs.contains(id) else { return }
        provisionalIndexes[id] = segments.endIndex
        segments.append(CaptionSegment(
            sequence: nextSequence,
            sourceText: text,
            startedAt: startedAt,
            state: .provisional
        ))
        nextSequence += 1
    }

    private mutating func applyFinal(id: String, text: String, startedAt: TimeInterval, endedAt: TimeInterval) {
        guard let text = normalized(text), !committedProviderIDs.contains(id) else { return }
        if let index = provisionalIndexes.removeValue(forKey: id), segments.indices.contains(index) {
            segments[index].sourceText = text
            segments[index].startedAt = startedAt
            segments[index].endedAt = endedAt
            segments[index].state = .committed
        } else {
            segments.append(CaptionSegment(
                sequence: nextSequence,
                sourceText: text,
                startedAt: startedAt,
                endedAt: endedAt,
                state: .committed
            ))
            nextSequence += 1
        }
        committedProviderIDs.insert(id)
    }

    mutating func autoCommitPunctuatedPartial(providerSentenceID: String) -> [CaptionSegment] {
        guard let index = provisionalIndexes[providerSentenceID],
              segments.indices.contains(index),
              SentenceBoundaryDetector.shouldAutoCommit(segments[index].sourceText) else {
            return segments
        }

        provisionalIndexes.removeValue(forKey: providerSentenceID)
        segments[index].state = .committed
        committedProviderIDs.insert(providerSentenceID)
        autoCommittedProviderIDs.insert(providerSentenceID)
        return segments
    }

    private func normalized(_ text: String) -> String? {
        let result = text.trimmingCharacters(in: .whitespacesAndNewlines)
        return result.isEmpty ? nil : result
    }
}
