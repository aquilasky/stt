import Foundation
import OSLog

enum RecognitionMetric: String, CaseIterable, Sendable {
    case captureConversionMS, captureDeliveryMS, captureOverwrittenBatches, captureConversionFailures
    case queuedAudioAgeMS, queuedChunks, droppedChunks, audioSendMS
    case taskReadyMS, asrEventGapMS, asrDecodeMS, mainActorSchedulingMS, transcriptApplyMS
}

struct RecognitionMetricBucket: Equatable {
    private(set) var count = 0
    private(set) var total = 0.0
    private(set) var maximum = 0.0
    mutating func add(_ value: Double) {
        count += 1
        total += value
        maximum = max(maximum, value)
    }
    var mean: Double { count == 0 ? 0 : total / Double(count) }
}

/// Numeric-only, opt-in diagnostics. No request, error or transcript strings are accepted.
final class RecognitionDiagnostics: @unchecked Sendable {
    static let shared = RecognitionDiagnostics()
    let isEnabled: Bool
    private let lock = NSLock()
    private var buckets: [RecognitionMetric: RecognitionMetricBucket] = [:]
    private var emittedAt: [RecognitionMetric: TimeInterval] = [:]
    private let logger = Logger(subsystem: Bundle.main.bundleIdentifier ?? "LectureCaption", category: "RecognitionLatency")

    private init() {
        isEnabled = ProcessInfo.processInfo.environment["LECTURE_CAPTION_DIAGNOSTICS"] == "1"
            || UserDefaults.standard.bool(forKey: "recognition-diagnostics-enabled")
        if isEnabled { logger.notice("Recognition latency diagnostics enabled; numeric aggregates only") }
    }

    static var now: TimeInterval { ProcessInfo.processInfo.systemUptime }

    func record(_ metric: RecognitionMetric, _ value: Double) {
        guard isEnabled, value.isFinite, value >= 0 else { return }
        let time = Self.now
        let snapshot: RecognitionMetricBucket? = lock.withLock {
            buckets[metric, default: RecognitionMetricBucket()].add(value)
            guard time - (emittedAt[metric] ?? 0) >= 2 else { return nil }
            emittedAt[metric] = time
            // Cumulative aggregates retain rare spikes even between log emissions.
            return buckets[metric]
        }
        if let snapshot {
            logger.notice("metric=\(metric.rawValue, privacy: .public) samples=\(snapshot.count) mean=\(snapshot.mean) max=\(snapshot.maximum) total=\(snapshot.total)")
        }
    }
}
