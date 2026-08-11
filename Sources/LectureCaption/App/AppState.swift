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
    var autoPauseInterval: TimeInterval? = 30
    var phase: SessionPhase = .idle
    var isInputActive = false
    var activeSession: LectureSession?
    var captionSegments: [CaptionSegment] = []

    var canStart: Bool {
        phase == .idle || phase == .completed
    }

    var canPause: Bool {
        phase == .monitoringLocal || phase == .activatingProvider || phase == .recognizing || phase == .autoPaused
    }

    func startSession() {
        guard canStart else { return }

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
        phase = .monitoringLocal
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
        activeSession?.endedAt = .now
        isInputActive = false
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

    func removeGlossaryEntry(id: UUID) {
        glossary.removeAll { $0.id == id }
    }
}
