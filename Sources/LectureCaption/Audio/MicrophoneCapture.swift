@preconcurrency import AVFoundation
import Foundation

final class MicrophoneCapture: AudioCaptureService, @unchecked Sendable {
    private let engine = AVAudioEngine()
    private let lock = NSLock()
    private var bufferHandler: MicrophoneBufferHandler?
    private(set) var isRunning = false

    func start(
        shouldContinue: @escaping @Sendable () -> Bool,
        onBuffer: @escaping MicrophoneBufferHandler
    ) async throws {
        guard await MicrophoneAuthorization.requestAccess() else {
            throw AudioCaptureError.microphonePermissionDenied
        }
        guard shouldContinue() else {
            throw AudioCaptureError.startCancelled
        }

        let inputNode = engine.inputNode
        let inputFormat = inputNode.outputFormat(forBus: 0)
        guard inputFormat.sampleRate > 0, inputFormat.channelCount > 0 else {
            throw AudioCaptureError.noInputDevice
        }

        stop()

        lock.withLock {
            bufferHandler = onBuffer
        }

        inputNode.installTap(onBus: 0, bufferSize: 1_024, format: nil) { [weak self] buffer, time in
            guard let self else { return }

            let handler = self.lock.withLock { self.bufferHandler }
            handler?(buffer, time)
        }

        engine.prepare()
        do {
            try engine.start()
            isRunning = true
        } catch {
            stop()
            throw error
        }

        guard shouldContinue() else {
            stop()
            throw AudioCaptureError.startCancelled
        }
    }

    func stop() {
        guard isRunning || bufferHandler != nil else { return }

        engine.inputNode.removeTap(onBus: 0)
        engine.stop()

        lock.withLock {
            bufferHandler = nil
        }
        isRunning = false
    }

    deinit {
        stop()
    }
}
