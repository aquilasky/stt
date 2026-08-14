import Foundation

struct TranscriptStabilizer: Sendable {
    private(set) var segments: [CaptionSegment] = []
    private var provisionalIndexes: [String: Int] = [:]
    private var committedProviderIDs: Set<String> = []
    private var committedFinalSignatures: Set<String> = []
    private var autoCommittedProviderIndexes: [String: [Int]] = [:]
    private var autoCommittedProviderPrefixes: [String: String] = [:]
    private var nextSequence = 0

    mutating func beginProviderTask() {
        provisionalIndexes.removeAll()
        committedProviderIDs.removeAll()
        committedFinalSignatures.removeAll()
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

        if let autoCommittedIndex = autoCommittedProviderIndexes[id]?.last,
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
        let finalSignature = "\(text)|\(startedAt)|\(endedAt)"
        guard !committedFinalSignatures.contains(finalSignature) else { return }
        defer { committedFinalSignatures.insert(finalSignature) }
        if let autoCommittedIndexes = autoCommittedProviderIndexes.removeValue(forKey: id),
           let autoCommittedIndex = autoCommittedIndexes.last,
           segments.indices.contains(autoCommittedIndex) {
            let prefix = autoCommittedProviderPrefixes.removeValue(forKey: id)
            let continuationIndex = provisionalIndexes.removeValue(forKey: id)
            guard let prefix, text.hasPrefix(prefix) else {
                replaceSegments(
                    at: autoCommittedIndexes + (continuationIndex.map { [$0] } ?? []),
                    withFinalText: text,
                    startedAt: startedAt,
                    endedAt: endedAt
                )
                committedProviderIDs.insert(id)
                return
            }
            if let continuationIndex,
               segments.indices.contains(continuationIndex) {
                let continuation = String(text.dropFirst(prefix.count))
                let normalizedContinuation = continuation.trimmingCharacters(in: .whitespacesAndNewlines)
                if !normalizedContinuation.isEmpty {
                    for index in autoCommittedIndexes where segments.indices.contains(index) {
                        segments[index].state = .committed
                    }
                    segments[continuationIndex].sourceText = normalizedContinuation
                    segments[continuationIndex].startedAt = startedAt
                    segments[continuationIndex].endedAt = endedAt
                    segments[continuationIndex].state = .committed
                    committedProviderIDs.insert(id)
                    return
                }
            }
            if text == prefix {
                for index in autoCommittedIndexes where segments.indices.contains(index) {
                    segments[index].state = .committed
                }
                segments[autoCommittedIndex].startedAt = startedAt
                segments[autoCommittedIndex].endedAt = endedAt
                segments[autoCommittedIndex].state = .committed
                committedProviderIDs.insert(id)
                return
            }
            let continuation = String(text.dropFirst(prefix.count)).trimmingCharacters(in: .whitespacesAndNewlines)
            if !continuation.isEmpty {
                for index in autoCommittedIndexes where segments.indices.contains(index) {
                    segments[index].state = .committed
                }
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
            segments[index].state = .autoCommitted
            committedProviderIDs.insert(providerSentenceID)
            autoCommittedProviderIndexes[providerSentenceID, default: []].append(index)
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

    private mutating func replaceSegments(
        at indexes: [Int],
        withFinalText text: String,
        startedAt: TimeInterval,
        endedAt: TimeInterval
    ) {
        let uniqueIndexes = Array(Set(indexes)).sorted()
        guard let first = uniqueIndexes.first, segments.indices.contains(first) else { return }

        segments[first].sourceText = text
        segments[first].startedAt = startedAt
        segments[first].endedAt = endedAt
        segments[first].state = .committed
        removeSegments(at: Set(uniqueIndexes.dropFirst()))
    }

    private mutating func removeSegments(at removedIndexes: Set<Int>) {
        guard !removedIndexes.isEmpty else { return }
        let sortedIndexes = removedIndexes.sorted()

        func remappedIndex(_ index: Int) -> Int? {
            guard !removedIndexes.contains(index) else { return nil }
            return index - sortedIndexes.filter { $0 < index }.count
        }

        for index in sortedIndexes.reversed() where segments.indices.contains(index) {
            segments.remove(at: index)
        }
        provisionalIndexes = provisionalIndexes.reduce(into: [:]) { result, element in
            if let index = remappedIndex(element.value) {
                result[element.key] = index
            }
        }
        autoCommittedProviderIndexes = autoCommittedProviderIndexes.reduce(into: [:]) { result, element in
            let indexes = element.value.compactMap(remappedIndex)
            if !indexes.isEmpty {
                result[element.key] = indexes
            } else {
                autoCommittedProviderPrefixes.removeValue(forKey: element.key)
            }
        }
    }
}
