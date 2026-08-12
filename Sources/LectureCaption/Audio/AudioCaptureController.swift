import Foundation

final class AudioCaptureController: @unchecked Sendable {
    typealias OutputHandler = @MainActor @Sendable (AudioCaptureUpdate) -> Void

    private let lock = NSLock()
    private var pipeline = AudioPipeline()
    private var generationGate = CaptureGenerationGate()
    private var microphoneCapture: MicrophoneCapture?
    private var pendingDelivery: PendingDelivery?
    private var isDeliveryScheduled = false

    func startMicrophone(onOutput: @escaping OutputHandler) async throws {
        let (generation, activePipeline) = prepareStart()
        let capture = MicrophoneCapture()
        install(capture, for: generation)

        try await capture.start(shouldContinue: { [weak self] in
            self?.isCurrent(generation) == true
        }) { [weak self] buffer, _ in
            guard let self, self.isCurrent(generation) else { return }
            let timestamp = ProcessInfo.processInfo.systemUptime
            guard let output = try? activePipeline.process(buffer: buffer, startedAt: timestamp) else {
                return
            }
            self.publish(AudioCaptureUpdate(output), generation: generation, to: onOutput)
        }

        guard isCurrent(generation) else {
            capture.stop()
            return
        }
    }

    func stop() {
        let capture = lock.withLock { () -> MicrophoneCapture? in
            generationGate.invalidate()
            pendingDelivery = nil
            defer {
                microphoneCapture = nil
            }
            return microphoneCapture
        }
        capture?.stop()
        lock.withLock {
            _ = pipeline.flush()
        }
    }

    private func prepareStart() -> (generation: Int, pipeline: AudioPipeline) {
        lock.withLock {
            let generation = generationGate.begin()
            pipeline = AudioPipeline()
            pendingDelivery = nil
            return (generation, pipeline)
        }
    }

    private func install(_ capture: MicrophoneCapture, for generation: Int) {
        lock.withLock {
            guard generationGate.accepts(generation) else { return }
            microphoneCapture = capture
        }
    }

    private func isCurrent(_ generation: Int) -> Bool {
        lock.withLock { generationGate.accepts(generation) }
    }

    private func publish(
        _ update: AudioCaptureUpdate,
        generation: Int,
        to handler: @escaping OutputHandler
    ) {
        let shouldSchedule = lock.withLock { () -> Bool in
            guard generationGate.accepts(generation) else { return false }
            pendingDelivery = PendingDelivery(generation: generation, update: update, handler: handler)
            guard !isDeliveryScheduled else { return false }
            isDeliveryScheduled = true
            return true
        }

        guard shouldSchedule else { return }
        Task { @MainActor [weak self] in
            guard let self else { return }
            let delivery = self.lock.withLock { () -> PendingDelivery? in
                defer { self.isDeliveryScheduled = false }
                guard let pendingDelivery,
                      self.generationGate.accepts(pendingDelivery.generation) else {
                    self.pendingDelivery = nil
                    return nil
                }
                self.pendingDelivery = nil
                return pendingDelivery
            }
            if let delivery {
                delivery.handler(delivery.update)
            }
        }
    }
}

private struct PendingDelivery: @unchecked Sendable {
    let generation: Int
    let update: AudioCaptureUpdate
    let handler: AudioCaptureController.OutputHandler
}

struct AudioCaptureUpdate: Sendable {
    let levelDBFS: Float
    let isInputActive: Bool
    let activityEvent: LocalActivityEvent
    let preRollData: Data?
    let chunks: [PCM16Frame]
    let endedAt: TimeInterval

    init(_ output: AudioPipelineOutput) {
        levelDBFS = output.levelDBFS
        isInputActive = output.isInputActive
        activityEvent = output.activityEvent
        preRollData = output.preRollData
        chunks = output.chunks
        endedAt = output.endedAt
    }
}
