import Accelerate
import Foundation

enum LocalActivityEvent: Equatable, Sendable {
    case none
    case started
    case stopped
}

struct LocalActivityMeasurement: Equatable, Sendable {
    let levelDBFS: Float
    let noiseFloorDBFS: Float
    let isActive: Bool
    let event: LocalActivityEvent
}

struct LocalActivityDetector {
    private let configuration: LocalActivityConfiguration
    private let minimumActivationDBFS: Float
    private let floorDBFS: Float

    private(set) var isActive = false
    private(set) var noiseFloorDBFS: Float
    private var activationDuration: TimeInterval = 0
    private var releaseDuration: TimeInterval = 0
    private var stableActiveDuration: TimeInterval = 0
    private var activeLevelEstimate: Float?

    init(
        configuration: LocalActivityConfiguration = .init(),
        initialNoiseFloorDBFS: Float = -60,
        minimumActivationDBFS: Float = -45,
        floorDBFS: Float = -96
    ) {
        self.configuration = configuration
        self.minimumActivationDBFS = minimumActivationDBFS
        self.floorDBFS = floorDBFS
        noiseFloorDBFS = initialNoiseFloorDBFS
    }

    mutating func process(_ frame: PCM16Frame) -> LocalActivityMeasurement {
        let level = calculateLevelDBFS(frame.data)
        let duration = frame.duration
        let activationThreshold = max(noiseFloorDBFS + configuration.activationAboveNoiseFloor, minimumActivationDBFS)
        let releaseThreshold = noiseFloorDBFS + configuration.releaseAboveNoiseFloor

        var event: LocalActivityEvent = .none

        if isActive {
            if level < releaseThreshold {
                releaseDuration += duration
                if releaseDuration >= configuration.releaseHold {
                    isActive = false
                    releaseDuration = 0
                    stableActiveDuration = 0
                    activeLevelEstimate = nil
                    event = .stopped
                }
            } else {
                releaseDuration = 0
                updateStableNoiseFloor(level: level, duration: duration)
            }
        } else if level >= activationThreshold {
            activationDuration += duration
            if activationDuration >= configuration.activationHold {
                isActive = true
                activationDuration = 0
                stableActiveDuration = 0
                activeLevelEstimate = level
                event = .started
            }
        } else {
            activationDuration = 0
            // The detector learns the acoustic floor only while inactive.
            noiseFloorDBFS = (noiseFloorDBFS * 0.95) + (level * 0.05)
            noiseFloorDBFS = min(max(noiseFloorDBFS, floorDBFS), -20)
        }

        return LocalActivityMeasurement(
            levelDBFS: level,
            noiseFloorDBFS: noiseFloorDBFS,
            isActive: isActive,
            event: event
        )
    }

    private mutating func updateStableNoiseFloor(level: Float, duration: TimeInterval) {
        guard level <= configuration.maximumAdaptiveNoiseDBFS else {
            stableActiveDuration = 0
            activeLevelEstimate = level
            return
        }

        let estimate = activeLevelEstimate ?? level
        if abs(level - estimate) <= configuration.stableNoiseToleranceDB {
            stableActiveDuration += duration
        } else {
            stableActiveDuration = 0
        }
        activeLevelEstimate = (estimate * 0.9) + (level * 0.1)

        guard stableActiveDuration >= configuration.stableNoiseHold else { return }
        noiseFloorDBFS = (noiseFloorDBFS * 0.98) + (level * 0.02)
        noiseFloorDBFS = min(max(noiseFloorDBFS, floorDBFS), configuration.maximumAdaptiveNoiseDBFS)
    }

    private func calculateLevelDBFS(_ data: Data) -> Float {
        guard !data.isEmpty else { return floorDBFS }

        let normalized: [Float] = data.withUnsafeBytes { rawBuffer in
            let samples = rawBuffer.bindMemory(to: Int16.self)
            return samples.map { Float($0) / Float(Int16.max) }
        }
        guard !normalized.isEmpty else { return floorDBFS }

        var meanSquare: Float = 0
        vDSP_measqv(normalized, 1, &meanSquare, vDSP_Length(normalized.count))
        let rms = sqrt(meanSquare)
        guard rms > 0 else { return floorDBFS }
        return max(20 * log10(rms), floorDBFS)
    }
}
