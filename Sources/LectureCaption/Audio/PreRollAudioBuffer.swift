import Foundation

struct PreRollAudioBuffer {
    let maximumDuration: TimeInterval
    let sampleRate: Double

    private var storage = Data()

    init(maximumDuration: TimeInterval = 0.8, sampleRate: Double = 16_000) {
        precondition(maximumDuration > 0)
        precondition(sampleRate > 0)
        self.maximumDuration = maximumDuration
        self.sampleRate = sampleRate
    }

    var duration: TimeInterval {
        Double(storage.count) / (sampleRate * 2)
    }

    var data: Data {
        storage
    }

    mutating func append(_ frame: PCM16Frame) {
        precondition(frame.sampleRate == sampleRate)
        storage.append(frame.data)

        let capacity = Int((maximumDuration * sampleRate).rounded(.down)) * 2
        if storage.count > capacity {
            storage = Data(storage.suffix(capacity))
        }
    }

    mutating func removeAll() {
        storage = Data()
    }
}
