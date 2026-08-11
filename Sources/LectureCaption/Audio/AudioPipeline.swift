@preconcurrency import AVFoundation
import Foundation

struct AudioPipelineOutput: Sendable {
    let levelDBFS: Float
    let isInputActive: Bool
    let activityEvent: LocalActivityEvent
    let preRollData: Data?
    let chunks: [PCM16Frame]
    let endedAt: TimeInterval
}

final class AudioPipeline: @unchecked Sendable {
    private let lock = NSLock()
    private let converter: PCM16AudioConverter
    private var detector: LocalActivityDetector
    private var chunker: PCM16Chunker
    private var preRoll: PreRollAudioBuffer
    private var nextInputSequence = 0

    init(
        sampleRate: Double = 16_000,
        chunkDuration: TimeInterval = 0.04,
        activityConfiguration: LocalActivityConfiguration = .init()
    ) {
        converter = PCM16AudioConverter(sampleRate: sampleRate)
        detector = LocalActivityDetector(configuration: activityConfiguration)
        chunker = PCM16Chunker(sampleRate: sampleRate, chunkDuration: chunkDuration)
        preRoll = PreRollAudioBuffer(maximumDuration: activityConfiguration.preRoll, sampleRate: sampleRate)
    }

    func process(
        buffer: AVAudioPCMBuffer,
        startedAt: TimeInterval
    ) throws -> AudioPipelineOutput? {
        try lock.withLock {
            let frame = try converter.convert(buffer, sequence: nextInputSequence, startedAt: startedAt)
            nextInputSequence += 1
            guard !frame.data.isEmpty else { return nil }

            preRoll.append(frame)
            let measurement = detector.process(frame)
            let chunks = chunker.append(frame)
            let endedAt = frame.startedAt + frame.duration

            return AudioPipelineOutput(
                levelDBFS: measurement.levelDBFS,
                isInputActive: measurement.isActive,
                activityEvent: measurement.event,
                preRollData: measurement.event == .started ? preRoll.data : nil,
                chunks: chunks,
                endedAt: endedAt
            )
        }
    }

    func flush() -> PCM16Frame? {
        lock.withLock {
            chunker.flush()
        }
    }
}
