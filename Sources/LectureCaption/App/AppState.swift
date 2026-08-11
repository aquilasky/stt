import CoreGraphics
import Foundation
import Observation

@MainActor
@Observable
final class AppState {
    var inputSource: AudioInputSource = .microphone
    var speechProvider: SpeechProviderKind = .aliyunRealtime
    var sourceLanguage: RecognitionLanguage = .english
    var targetLanguage: TargetLanguage = .simplifiedChinese
    var courseName = ""
    var topic = ""
    var glossary: [GlossaryEntry] = []
    var systemAudioTargets: [SystemAudioTarget] = []
    var selectedSystemAudioTarget: SystemAudioTarget?
    var isRefreshingSystemAudioTargets = false
    var microphonePermission = AudioCapturePermission.microphoneStatus()
    var systemAudioPermission = AudioCapturePermission.systemAudioStatus()
    var systemAudioPermissionDetail: String?
    var autoPauseInterval: TimeInterval? = 30
    var phase: SessionPhase = .idle
    var isInputActive = false
    var inputLevelDBFS: Float = -96
    var captureError: String?
    var activeSession: LectureSession?
    var captionSegments: [CaptionSegment] = []

    @ObservationIgnored private let audioCaptureController = AudioCaptureController()
    @ObservationIgnored private var silenceStartedAt: TimeInterval?
    @ObservationIgnored private var sessionGeneration = 0
    @ObservationIgnored private var systemAudioPermissionState = SystemAudioPermissionState()

    var canStart: Bool {
        (phase == .idle || phase == .completed)
            && (inputSource != .systemAudio || selectedSystemAudioTarget != nil)
    }

    var canPause: Bool {
        phase == .monitoringLocal || phase == .activatingProvider || phase == .recognizing || phase == .autoPaused
    }

    func startSession() async {
        guard canStart else { return }

        sessionGeneration += 1
        let generation = sessionGeneration

        activeSession = LectureSession(
            context: LectureContext(
                courseName: courseName,
                topic: topic,
                sourceLanguage: sourceLanguage,
                targetLanguage: targetLanguage,
                glossary: glossary
            ),
            inputSource: inputSource,
            provider: speechProvider
        )
        captionSegments = []
        isInputActive = false
        inputLevelDBFS = -96
        captureError = nil
        silenceStartedAt = nil
        phase = .monitoringLocal

        do {
            let outputHandler: AudioCaptureController.OutputHandler = { [weak self] output in
                guard let self, self.sessionGeneration == generation else { return }
                self.receiveAudioPipelineOutput(output)
            }
            switch inputSource {
            case .microphone:
                try await audioCaptureController.startMicrophone(onOutput: outputHandler)
            case .systemAudio:
                guard let selectedSystemAudioTarget else { return }
                try await audioCaptureController.startSystemAudio(
                    target: selectedSystemAudioTarget,
                    onOutput: outputHandler
                )
            }

            guard generation == sessionGeneration, phase != .completed else {
                audioCaptureController.stop()
                return
            }
        } catch {
            guard generation == sessionGeneration else { return }
            if inputSource == .systemAudio {
                updateSystemAudioPermission(for: error)
                let message = AudioCapturePermission.diagnosticMessage(for: error)
                systemAudioPermissionDetail = message
                captureError = message
            } else {
                captureError = error.localizedDescription
            }
            phase = .idle
            activeSession = nil
        }
        refreshPermissions()
    }

    func pauseSession() {
        guard canPause else { return }
        isInputActive = false
        phase = .manuallyPaused
    }

    func resumeSession() {
        guard phase == .manuallyPaused else { return }
        phase = .monitoringLocal
    }

    func stopSession() {
        guard phase != .idle && phase != .completed else { return }
        sessionGeneration += 1
        audioCaptureController.stop()
        activeSession?.endedAt = .now
        isInputActive = false
        silenceStartedAt = nil
        phase = .completed
    }

    // The audio pipeline calls this after local activity detection, before cloud audio is sent.
    func receiveInputActivity(_ active: Bool) {
        isInputActive = active

        switch phase {
        case .monitoringLocal, .autoPaused:
            if active {
                phase = .recognizing
            }
        case .manuallyPaused:
            break
        default:
            break
        }
    }

    func receiveSilence(elapsed: TimeInterval) {
        guard phase == .recognizing,
              let autoPauseInterval,
              elapsed >= autoPauseInterval else {
            return
        }

        isInputActive = false
        phase = .autoPaused
    }

    func refreshSystemAudioTargets() async {
        guard !isRefreshingSystemAudioTargets else { return }
        isRefreshingSystemAudioTargets = true
        defer { isRefreshingSystemAudioTargets = false }

        do {
            let targets = [SystemAudioTarget.allSystemAudio] + (try await SystemAudioCapture.availableTargets())
            systemAudioPermission = systemAudioPermissionState.record(
                .authorized,
                legacyAccess: CGPreflightScreenCaptureAccess()
            )
            systemAudioPermissionDetail = nil
            systemAudioTargets = targets
            if let selectedSystemAudioTarget,
               !targets.contains(selectedSystemAudioTarget) {
                self.selectedSystemAudioTarget = nil
            }
        } catch {
            updateSystemAudioPermission(for: error)
            let message = AudioCapturePermission.diagnosticMessage(for: error)
            systemAudioPermissionDetail = message
            captureError = message
        }
        microphonePermission = AudioCapturePermission.microphoneStatus()
    }

    func refreshPermissions() {
        microphonePermission = AudioCapturePermission.microphoneStatus()
        systemAudioPermission = systemAudioPermissionState.refresh(
            legacyAccess: CGPreflightScreenCaptureAccess()
        )
    }

    func revalidateSystemAudioPermission() async {
        do {
            try await SystemAudioCapture.verifyAccess()
            systemAudioPermission = systemAudioPermissionState.record(
                .authorized,
                legacyAccess: CGPreflightScreenCaptureAccess()
            )
            systemAudioPermissionDetail = nil
        } catch {
            updateSystemAudioPermission(for: error)
            systemAudioPermissionDetail = AudioCapturePermission.diagnosticMessage(for: error)
        }
    }

    func requestSystemAudioPermission() {
        guard !CGPreflightScreenCaptureAccess() else {
            refreshPermissions()
            return
        }

        _ = AudioCapturePermission.requestSystemAudioAccess()
        Task { await revalidateSystemAudioPermission() }
    }

    func openPrivacySettings(for inputSource: AudioInputSource) {
        switch inputSource {
        case .microphone:
            AudioCapturePermission.openMicrophonePrivacySettings()
        case .systemAudio:
            AudioCapturePermission.openSystemAudioPrivacySettings()
        }
    }

    private func receiveAudioPipelineOutput(_ output: AudioCaptureUpdate) {
        inputLevelDBFS = output.levelDBFS
        receiveInputActivity(output.isInputActive)

        guard phase == .recognizing else {
            silenceStartedAt = nil
            return
        }

        if output.isInputActive {
            silenceStartedAt = nil
            return
        }

        if silenceStartedAt == nil {
            silenceStartedAt = output.endedAt
        }
        if let silenceStartedAt {
            receiveSilence(elapsed: output.endedAt - silenceStartedAt)
        }
    }

    private func updateSystemAudioPermission(for error: Error) {
        systemAudioPermission = systemAudioPermissionState.record(
            AudioCapturePermission.screenCaptureKitAccessResult(for: error),
            legacyAccess: CGPreflightScreenCaptureAccess()
        )
    }

    func removeGlossaryEntry(id: UUID) {
        glossary.removeAll { $0.id == id }
    }
}
