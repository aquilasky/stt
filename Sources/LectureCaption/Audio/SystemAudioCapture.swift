@preconcurrency import AVFoundation
@preconcurrency import CoreMedia
@preconcurrency import ScreenCaptureKit
import Foundation

typealias SystemAudioSampleHandler = (CMSampleBuffer) -> Void

final class SystemAudioCapture: NSObject, AudioCaptureService, @unchecked Sendable {
    private let lock = NSLock()
    private let sampleQueue = DispatchQueue(label: "com.aquilasky.LectureCaption.system-audio")
    private var stream: SCStream?
    private var sampleHandler: SystemAudioSampleHandler?
    private(set) var isRunning = false

    static func availableTargets() async throws -> [SystemAudioTarget] {
        let content = try await SCShareableContent.current
        let currentBundleIdentifier = Bundle.main.bundleIdentifier
        return content.applications
            .filter { $0.bundleIdentifier != currentBundleIdentifier }
            .map {
                SystemAudioTarget(
                    processID: $0.processID,
                    applicationName: $0.applicationName,
                    bundleIdentifier: $0.bundleIdentifier
                )
            }
            .sorted { $0.applicationName.localizedStandardCompare($1.applicationName) == .orderedAscending }
    }

    func start(
        target: SystemAudioTarget,
        shouldContinue: @escaping @Sendable () -> Bool,
        onSampleBuffer: @escaping SystemAudioSampleHandler
    ) async throws {
        stop()

        let content = try await SCShareableContent.current
        guard shouldContinue() else {
            throw AudioCaptureError.startCancelled
        }
        guard let display = content.displays.first else {
            throw AudioCaptureError.noShareableDisplay
        }
        guard let application = content.applications.first(where: { $0.processID == target.processID }) else {
            throw AudioCaptureError.systemAudioTargetUnavailable
        }

        let filter = SCContentFilter(
            display: display,
            including: [application],
            exceptingWindows: []
        )
        let configuration = SCStreamConfiguration()
        configuration.capturesAudio = true
        configuration.excludesCurrentProcessAudio = true
        configuration.sampleRate = 48_000
        configuration.channelCount = 2

        let newStream = SCStream(filter: filter, configuration: configuration, delegate: self)
        try newStream.addStreamOutput(self, type: .audio, sampleHandlerQueue: sampleQueue)

        lock.withLock {
            sampleHandler = onSampleBuffer
            stream = newStream
        }

        do {
            try await newStream.startCapture()
            isRunning = true
            guard shouldContinue() else {
                stopCurrentStream(newStream)
                throw AudioCaptureError.startCancelled
            }
        } catch {
            lock.withLock {
                sampleHandler = nil
                stream = nil
            }
            throw error
        }
    }

    func stop() {
        let activeStream = lock.withLock { () -> SCStream? in
            defer {
                stream = nil
                sampleHandler = nil
            }
            return stream
        }
        isRunning = false

        if let activeStream {
            stopCurrentStream(activeStream)
        }
    }

    private func stopCurrentStream(_ stream: SCStream) {
        Task {
            try? await stream.stopCapture()
        }
    }
}

extension SystemAudioCapture: SCStreamDelegate {
    func stream(_ stream: SCStream, didStopWithError error: Error) {
        let isCurrentStream = lock.withLock { () -> Bool in
            guard stream === self.stream else { return false }
            self.stream = nil
            sampleHandler = nil
            return true
        }
        if isCurrentStream {
            isRunning = false
        }
    }
}

extension SystemAudioCapture: SCStreamOutput {
    func stream(
        _ stream: SCStream,
        didOutputSampleBuffer sampleBuffer: CMSampleBuffer,
        of outputType: SCStreamOutputType
    ) {
        guard outputType == .audio, sampleBuffer.isValid else { return }
        let handler: SystemAudioSampleHandler? = lock.withLock {
            guard stream === self.stream else { return nil }
            return sampleHandler
        }
        handler?(sampleBuffer)
    }
}
