import Foundation

struct TranscriptStabilizer: Sendable {
    private(set) var segments: [CaptionSegment] = []
    private var provisionalIndexes: [String: Int] = [:]
    private var committedProviderIDs: Set<String> = []
    private var autoCommittedProviderIndexes: [String: Int] = [:]
    private var nextSequence = 0

    mutating func beginProviderTask() {
        provisionalIndexes.removeAll()
        committedProviderIDs.removeAll()
        autoCommittedProviderIndexes.removeAll()
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

        if let autoCommittedIndex = autoCommittedProviderIndexes[id],
           segments.indices.contains(autoCommittedIndex) {
            let previousText = segments[autoCommittedIndex].sourceText
            if text == previousText {
                return
            }
            committedProviderIDs.remove(id)
            let continuation = text.hasPrefix(previousText)
                ? String(text.dropFirst(previousText.count)).trimmingCharacters(in: .whitespacesAndNewlines)
                : text
            guard !continuation.isEmpty else { return }
            provisionalIndexes[id] = segments.endIndex
            segments.append(CaptionSegment(
                sequence: nextSequence,
                sourceText: continuation,
                startedAt: startedAt,
                state: .provisional
            ))
            nextSequence += 1
            return
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
        guard let text = normalized(text) else { return }
        if let autoCommittedIndex = autoCommittedProviderIndexes.removeValue(forKey: id),
           segments.indices.contains(autoCommittedIndex) {
            if let continuationIndex = provisionalIndexes.removeValue(forKey: id),
               segments.indices.contains(continuationIndex) {
                let prefix = segments[autoCommittedIndex].sourceText
                let continuation = text.hasPrefix(prefix)
                    ? String(text.dropFirst(prefix.count)).trimmingCharacters(in: .whitespacesAndNewlines)
                    : text
                if !continuation.isEmpty {
                    segments[continuationIndex].sourceText = continuation
                    segments[continuationIndex].startedAt = startedAt
                    segments[continuationIndex].endedAt = endedAt
                    segments[continuationIndex].state = .committed
                    committedProviderIDs.insert(id)
                    return
                }
            }
            segments[autoCommittedIndex].sourceText = text
            segments[autoCommittedIndex].startedAt = startedAt
            segments[autoCommittedIndex].endedAt = endedAt
            segments[autoCommittedIndex].state = .committed
            committedProviderIDs.insert(id)
            return
        }
        guard !committedProviderIDs.contains(id) else { return }
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
        autoCommittedProviderIndexes[providerSentenceID] = index
        return segments
    }

    private func normalized(_ text: String) -> String? {
        let result = text.trimmingCharacters(in: .whitespacesAndNewlines)
        return result.isEmpty ? nil : result
    }
}
