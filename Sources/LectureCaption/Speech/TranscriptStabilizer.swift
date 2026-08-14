import Foundation

struct TranscriptStabilizer: Sendable {
    private(set) var segments: [CaptionSegment] = []
    private var provisionalIndexes: [String: Int] = [:]
    private var committedProviderIDs: Set<String> = []
    private var autoCommittedProviderIndexes: [String: Int] = [:]
    private var autoCommittedProviderPrefixes: [String: String] = [:]
    private var nextSequence = 0

    mutating func beginProviderTask() {
        provisionalIndexes.removeAll()
        committedProviderIDs.removeAll()
        autoCommittedProviderIndexes.removeAll()
        autoCommittedProviderPrefixes.removeAll()
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
            let prefix = autoCommittedProviderPrefixes[id]
            let currentText = prefix.flatMap { text.hasPrefix($0) ? String(text.dropFirst($0.count)) : nil }
                ?? text
            guard !currentText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }
            segments[index].sourceText = currentText.trimmingCharacters(in: .whitespacesAndNewlines)
            segments[index].startedAt = startedAt
            return
        }

        if let autoCommittedIndex = autoCommittedProviderIndexes[id],
           segments.indices.contains(autoCommittedIndex) {
            let prefix = autoCommittedProviderPrefixes[id] ?? segments[autoCommittedIndex].sourceText
            if text == prefix {
                return
            }
            committedProviderIDs.remove(id)
            let continuation = text.hasPrefix(prefix)
                ? String(text.dropFirst(prefix.count)).trimmingCharacters(in: .whitespacesAndNewlines)
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
            let prefix = autoCommittedProviderPrefixes.removeValue(forKey: id)
            if let continuationIndex = provisionalIndexes.removeValue(forKey: id),
               segments.indices.contains(continuationIndex) {
                let continuation = prefix.flatMap { text.hasPrefix($0) ? String(text.dropFirst($0.count)) : nil }
                    ?? text
                let normalizedContinuation = continuation.trimmingCharacters(in: .whitespacesAndNewlines)
                if !normalizedContinuation.isEmpty {
                    segments[continuationIndex].sourceText = normalizedContinuation
                    segments[continuationIndex].startedAt = startedAt
                    segments[continuationIndex].endedAt = endedAt
                    segments[continuationIndex].state = .committed
                    committedProviderIDs.insert(id)
                    return
                }
            }
            if let prefix, text == prefix {
                segments[autoCommittedIndex].startedAt = startedAt
                segments[autoCommittedIndex].endedAt = endedAt
                segments[autoCommittedIndex].state = .committed
                committedProviderIDs.insert(id)
                return
            }
            if let prefix, text.hasPrefix(prefix) {
                let continuation = String(text.dropFirst(prefix.count)).trimmingCharacters(in: .whitespacesAndNewlines)
                if !continuation.isEmpty {
                    segments.append(CaptionSegment(
                        sequence: nextSequence,
                        sourceText: continuation,
                        startedAt: startedAt,
                        endedAt: endedAt,
                        state: .committed
                    ))
                    nextSequence += 1
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
        guard var index = provisionalIndexes[providerSentenceID],
              segments.indices.contains(index) else {
            return segments
        }

        while segments.indices.contains(index),
              let boundary = SentenceBoundaryDetector.split(atFirstBoundaryIn: segments[index].sourceText) {
            provisionalIndexes.removeValue(forKey: providerSentenceID)
            segments[index].sourceText = boundary.committed
            segments[index].state = .committed
            committedProviderIDs.insert(providerSentenceID)
            autoCommittedProviderIndexes[providerSentenceID] = index
            let priorPrefix = autoCommittedProviderPrefixes[providerSentenceID]
            autoCommittedProviderPrefixes[providerSentenceID] = priorPrefix.map { "\($0) \(boundary.committed)" } ?? boundary.committed

            guard !boundary.remainder.isEmpty else { break }
            provisionalIndexes[providerSentenceID] = segments.endIndex
            segments.append(CaptionSegment(
                sequence: nextSequence,
                sourceText: boundary.remainder,
                startedAt: segments[index].startedAt,
                state: .provisional
            ))
            nextSequence += 1
            index = segments.index(before: segments.endIndex)
        }
        return segments
    }

    private func normalized(_ text: String) -> String? {
        let result = text.trimmingCharacters(in: .whitespacesAndNewlines)
        return result.isEmpty ? nil : result
    }
}
