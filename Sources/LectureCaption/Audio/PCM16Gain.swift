import Foundation

enum PCM16Gain {
    static func applying(_ gainDB: Float, to frame: PCM16Frame) -> PCM16Frame {
        guard gainDB != 0, !frame.data.isEmpty else { return frame }

        let multiplier = pow(10, gainDB / 20)
        let samples: [Int16] = frame.data.withUnsafeBytes { rawBuffer in
            rawBuffer.bindMemory(to: Int16.self).map { sample in
                Int16(clamping: Int((Float(sample) * multiplier).rounded()))
            }
        }

        return PCM16Frame(
            sequence: frame.sequence,
            data: samples.withUnsafeBytes { Data($0) },
            sampleRate: frame.sampleRate,
            startedAt: frame.startedAt
        )
    }
}
