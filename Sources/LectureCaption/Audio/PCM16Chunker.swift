import Foundation

struct PCM16Frame: Equatable, Sendable {
    let sequence: Int
    let data: Data
    let sampleRate: Double
    let startedAt: TimeInterval

    var duration: TimeInterval {
        Double(data.count) / (sampleRate * 2)
    }
}

struct PCM16Chunker {
    let sampleRate: Double
    let chunkDuration: TimeInterval

    private var pending = Data()
    private var pendingStartedAt: TimeInterval?
    private var nextSequence = 0

    init(sampleRate: Double = 16_000, chunkDuration: TimeInterval = 0.04) {
        precondition(sampleRate > 0)
        precondition(chunkDuration > 0)
        self.sampleRate = sampleRate
        self.chunkDuration = chunkDuration
    }

    mutating func append(_ frame: PCM16Frame) -> [PCM16Frame] {
        precondition(frame.sampleRate == sampleRate)

        if pendingStartedAt == nil {
            pendingStartedAt = frame.startedAt
        }
        pending.append(frame.data)

        var chunks: [PCM16Frame] = []
        let bytesPerChunk = Int((sampleRate * chunkDuration).rounded(.toNearestOrAwayFromZero)) * 2

        while pending.count >= bytesPerChunk {
            let data = pending.prefix(bytesPerChunk)
            let startedAt = pendingStartedAt ?? frame.startedAt
            chunks.append(
                PCM16Frame(
                    sequence: nextSequence,
                    data: Data(data),
                    sampleRate: sampleRate,
                    startedAt: startedAt
                )
            )
            nextSequence += 1
            pending.removeFirst(bytesPerChunk)
            pendingStartedAt = startedAt + chunkDuration
        }

        return chunks
    }

    mutating func flush() -> PCM16Frame? {
        guard !pending.isEmpty else { return nil }

        let frame = PCM16Frame(
            sequence: nextSequence,
            data: pending,
            sampleRate: sampleRate,
            startedAt: pendingStartedAt ?? 0
        )
        nextSequence += 1
        pending = Data()
        pendingStartedAt = nil
        return frame
    }
}
