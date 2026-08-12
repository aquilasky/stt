import Foundation
import Observation

@MainActor
@Observable
final class AppState {
    var speechProvider: SpeechProviderKind = .aliyunRealtime
    var sourceLanguage: RecognitionLanguage = .english
    var targetLanguage: TargetLanguage = .simplifiedChinese
    var courseName = ""
    var topic = ""
    var glossary: [GlossaryEntry] = []
    var aliyunWorkspaceID = UserDefaults.standard.string(forKey: "aliyun-workspace-id") ?? ""
    var aliyunRegion: AliyunRealtimeSettings.Region = {
        guard let raw = UserDefaults.standard.string(forKey: "aliyun-region"),
              let region = AliyunRealtimeSettings.Region(rawValue: raw) else {
            return .singapore
        }
        return region
    }()
    var aliyunAPIKey = ""
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
    @ObservationIgnored private var provider: AliyunRealtimeSTTProvider?
    @ObservationIgnored private var providerEventsTask: Task<Void, Never>?
    @ObservationIgnored private var transcriptStabilizer = TranscriptStabilizer()
    @ObservationIgnored private var providerIsReady = false
    @ObservationIgnored private var isFinishingProvider = false
    @ObservationIgnored private var pendingProviderAudio: [PCM16Frame] = []
    @ObservationIgnored private var isSendingProviderAudio = false
    @ObservationIgnored private var restartProviderAfterFinish = false
    @ObservationIgnored private var restartPreRollData: Data?
    @ObservationIgnored private var restartPreRollEndedAt: TimeInterval?
    @ObservationIgnored private var preRollEndedAt: TimeInterval?

    var canStart: Bool {
        phase == .idle || phase == .completed
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
            provider: speechProvider
        )
        captionSegments = []
        transcriptStabilizer = TranscriptStabilizer()
        clearPendingProviderAudio()
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
            try await audioCaptureController.startMicrophone(onOutput: outputHandler)

            guard generation == sessionGeneration, phase != .completed else {
                audioCaptureController.stop()
                return
            }
        } catch {
            guard generation == sessionGeneration else { return }
            captureError = error.localizedDescription
            phase = .idle
            activeSession = nil
        }
    }

    func pauseSession() {
        guard canPause else { return }
        isInputActive = false
        phase = .manuallyPaused
        requestProviderFinish()
    }

    func resumeSession() {
        guard phase == .manuallyPaused else { return }
        phase = .monitoringLocal
        if isInputActive {
            startProviderIfNeeded(preRollData: nil, preRollEndedAt: nil)
        }
    }

    func stopSession() {
        guard phase != .idle && phase != .completed else { return }
        sessionGeneration += 1
        audioCaptureController.stop()
        requestProviderFinish()
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
        requestProviderFinish()
    }

    private func receiveAudioPipelineOutput(_ output: AudioCaptureUpdate) {
        inputLevelDBFS = output.levelDBFS
        receiveInputActivity(output.isInputActive)

        if output.isInputActive,
           phase == .recognizing || phase == .monitoringLocal || phase == .autoPaused {
            startProviderIfNeeded(preRollData: output.preRollData, preRollEndedAt: output.endedAt)
        }

        if (phase == .activatingProvider || phase == .recognizing),
           !output.chunks.isEmpty,
           provider != nil,
           !isFinishingProvider {
            enqueueProviderAudio(output.chunks)
        }

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

    private func startProviderIfNeeded(preRollData: Data?, preRollEndedAt: TimeInterval?) {
        if provider != nil {
            if isFinishingProvider {
                restartProviderAfterFinish = true
                restartPreRollData = preRollData
                restartPreRollEndedAt = preRollEndedAt
            }
            return
        }
        guard speechProvider == .aliyunRealtime else {
            captureError = "MiMo 分块识别将在后续功能中接入。"
            phase = .monitoringLocal
            return
        }

        let workspaceID = aliyunWorkspaceID.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !workspaceID.isEmpty else {
            captureError = "请先填写阿里云 Workspace ID。"
            phase = .monitoringLocal
            return
        }
        if !aliyunAPIKey.isEmpty {
            do {
                try KeychainStore.save(
                    aliyunAPIKey,
                    service: "com.aquilasky.LectureCaption",
                    account: "dashscope-api-key"
                )
                aliyunAPIKey = ""
            } catch {
                captureError = "无法保存阿里云 API Key。"
                phase = .monitoringLocal
                return
            }
        }
        UserDefaults.standard.set(workspaceID, forKey: "aliyun-workspace-id")
        UserDefaults.standard.set(aliyunRegion.rawValue, forKey: "aliyun-region")

        let provider = AliyunRealtimeSTTProvider.keychainBacked(
            settings: AliyunRealtimeSettings(workspaceID: workspaceID, region: aliyunRegion)
        )
        self.provider = provider
        transcriptStabilizer.beginProviderTask()
        providerIsReady = false
        isFinishingProvider = false
        self.preRollEndedAt = preRollEndedAt
        phase = .activatingProvider
        let configuration = SpeechConfiguration(
            provider: .aliyunRealtime,
            sourceLanguage: sourceLanguage,
            sampleRate: 16_000,
            glossary: glossary
        )
        let events = provider.events()
        providerEventsTask = Task { [weak self] in
            do {
                try await provider.start(configuration: configuration)
                for try await event in events {
                    await self?.receiveTranscriptEvent(event, from: provider, preRollData: preRollData)
                }
            } catch {
                await self?.handleProviderError(error, from: provider)
            }
        }
    }

    private func receiveTranscriptEvent(
        _ event: TranscriptEvent,
        from provider: AliyunRealtimeSTTProvider,
        preRollData: Data?
    ) async {
        guard self.provider === provider else { return }
        switch event {
        case .ready:
            phase = .recognizing
            if let preRollData, !preRollData.isEmpty {
                discardBufferedAudio(through: preRollEndedAt)
                pendingProviderAudio.insert(
                    PCM16Frame(
                        sequence: -1,
                        data: preRollData,
                        sampleRate: 16_000,
                        startedAt: preRollEndedAt ?? 0
                    ),
                    at: 0
                )
            }
            providerIsReady = true
            drainProviderAudio()
        case .partial, .final:
            captionSegments = transcriptStabilizer.apply(event)
        case let .failed(code, message):
            captureError = AliyunServerError(code: code, message: message).localizedDescription
            await clearProvider(provider)
            phase = .monitoringLocal
        case .finished:
            await clearProvider(provider)
            if phase != .completed && phase != .manuallyPaused {
                phase = .monitoringLocal
            }
            if restartProviderAfterFinish {
                restartProviderAfterFinish = false
                let preRollData = restartPreRollData
                restartPreRollData = nil
                startProviderIfNeeded(preRollData: preRollData, preRollEndedAt: restartPreRollEndedAt)
            }
        }
    }

    private func handleProviderError(_ error: Error, from provider: AliyunRealtimeSTTProvider) async {
        guard self.provider === provider else { return }
        captureError = error.localizedDescription
        await clearProvider(provider)
        if phase != .completed && phase != .manuallyPaused {
            phase = .monitoringLocal
        }
    }

    private func requestProviderFinish() {
        guard provider != nil else { return }
        guard !isFinishingProvider else { return }
        isFinishingProvider = true
        drainProviderAudio()
    }

    private func clearProvider(_ provider: AliyunRealtimeSTTProvider) async {
        guard self.provider === provider else { return }
        self.provider = nil
        providerEventsTask = nil
        clearPendingProviderAudio()
        providerIsReady = false
        isFinishingProvider = false
        preRollEndedAt = nil
        await provider.stop()
    }

    private func enqueueProviderAudio(_ audio: [PCM16Frame]) {
        pendingProviderAudio.append(contentsOf: audio.filter { !$0.data.isEmpty })
        let maximumQueuedChunks = 250
        if pendingProviderAudio.count > maximumQueuedChunks {
            pendingProviderAudio.removeFirst(pendingProviderAudio.count - maximumQueuedChunks)
        }
        drainProviderAudio()
    }

    private func drainProviderAudio() {
        guard providerIsReady,
              !isSendingProviderAudio,
              let provider else {
            return
        }
        isSendingProviderAudio = true
        Task { [weak self] in
            while let self,
                  self.provider === provider,
                  self.providerIsReady,
                  !self.pendingProviderAudio.isEmpty {
                let audio = self.pendingProviderAudio.removeFirst().data
                do {
                    try await provider.send(audio: audio)
                } catch {
                    await self.handleProviderError(error, from: provider)
                    break
                }
            }
            self?.isSendingProviderAudio = false
            guard let self,
                  self.provider === provider,
                  self.isFinishingProvider,
                  self.pendingProviderAudio.isEmpty else {
                return
            }
            do {
                try await provider.flush()
            } catch {
                await self.handleProviderError(error, from: provider)
            }
        }
    }

    private func clearPendingProviderAudio() {
        pendingProviderAudio.removeAll(keepingCapacity: false)
        isSendingProviderAudio = false
    }

    private func discardBufferedAudio(through endTime: TimeInterval?) {
        guard let endTime else { return }
        while let first = pendingProviderAudio.first {
            let firstEnd = first.startedAt + first.duration
            if firstEnd <= endTime {
                pendingProviderAudio.removeFirst()
                continue
            }
            if first.startedAt < endTime {
                let overlapDuration = endTime - first.startedAt
                let overlapBytes = Int((overlapDuration * first.sampleRate).rounded(.down)) * 2
                let trimmedData = Data(first.data.dropFirst(min(overlapBytes, first.data.count)))
                pendingProviderAudio[0] = PCM16Frame(
                    sequence: first.sequence,
                    data: trimmedData,
                    sampleRate: first.sampleRate,
                    startedAt: endTime
                )
            }
            break
        }
    }

    func removeGlossaryEntry(id: UUID) {
        glossary.removeAll { $0.id == id }
    }
}
