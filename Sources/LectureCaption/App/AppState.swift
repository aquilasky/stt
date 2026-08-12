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
    var deepSeekAPIKey = ""
    var autoPauseInterval: TimeInterval? = 30
    var phase: SessionPhase = .idle
    var isInputActive = false
    var inputLevelDBFS: Float = -96
    var captureError: String?
    var activeSession: LectureSession?
    var captionSegments: [CaptionSegment] = []
    var captionFontSize: CGFloat = 18
    var savedSessions: [SavedLectureSession] = []

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
    @ObservationIgnored private let translationQueue = TranslationQueue(
        provider: DeepSeekTranslationProvider.localCredentialsBacked()
    )
    @ObservationIgnored private var translationEventsTask: Task<Void, Never>?
    @ObservationIgnored private var translatedSegmentIDs: Set<UUID> = []
    @ObservationIgnored private let sessionHistoryStore: LocalSessionHistoryStore
    @ObservationIgnored private let sessionHistoryWriter: LocalSessionHistoryWriter
    @ObservationIgnored private var sessionHistoryEventsTask: Task<Void, Never>?
    @ObservationIgnored private var sessionHistoryRevision = 0

    init(sessionHistoryStore: LocalSessionHistoryStore = .default) {
        self.sessionHistoryStore = sessionHistoryStore
        sessionHistoryWriter = LocalSessionHistoryWriter(store: sessionHistoryStore)
        do {
            savedSessions = try sessionHistoryStore.load()
        } catch {
            captureError = "无法读取本地课堂记录。\n\(error.localizedDescription)"
        }
        startSessionHistoryEventHandling()
    }

    var canStart: Bool {
        phase == .idle || phase == .completed
    }

    var canPause: Bool {
        phase == .monitoringLocal || phase == .activatingProvider || phase == .recognizing || phase == .autoPaused
    }

    var canDecreaseCaptionFontSize: Bool {
        captionFontSize > Self.minimumCaptionFontSize
    }

    var canIncreaseCaptionFontSize: Bool {
        captionFontSize < Self.maximumCaptionFontSize
    }

    func decreaseCaptionFontSize() {
        captionFontSize = max(Self.minimumCaptionFontSize, captionFontSize - Self.captionFontSizeStep)
    }

    func increaseCaptionFontSize() {
        captionFontSize = min(Self.maximumCaptionFontSize, captionFontSize + Self.captionFontSizeStep)
    }

    func startSession() async {
        guard canStart else { return }

        if !aliyunAPIKey.isEmpty {
            do {
                try LocalCredentialsStore.default.saveDashScopeAPIKey(aliyunAPIKey)
                aliyunAPIKey = ""
            } catch {
                captureError = "无法保存阿里云 API Key。\n\(error.localizedDescription)"
                return
            }
        }
        if !deepSeekAPIKey.isEmpty {
            do {
                try LocalCredentialsStore.default.saveDeepSeekAPIKey(deepSeekAPIKey)
                deepSeekAPIKey = ""
            } catch {
                captureError = "无法保存 DeepSeek API Key。\n\(error.localizedDescription)"
                return
            }
        }

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
        translatedSegmentIDs = []
        await translationQueue.cancelAll()
        startTranslationEventHandling(generation: generation)
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

    func stopSession() async {
        guard phase != .idle && phase != .completed else { return }
        sessionGeneration += 1
        audioCaptureController.stop()
        requestProviderFinish()
        Task { await translationQueue.cancelAll() }
        translationEventsTask?.cancel()
        translationEventsTask = nil
        activeSession?.endedAt = .now
        if let pendingSave = makeCurrentSessionSave() {
            do {
                await sessionHistoryWriter.submit(pendingSave.record, revision: pendingSave.revision)
                try await sessionHistoryWriter.flush()
            } catch {
                captureError = "无法保存本地课堂记录。\n\(error.localizedDescription)"
            }
        }
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
        let workspaceID = aliyunWorkspaceID.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !workspaceID.isEmpty else {
            captureError = "请先填写阿里云 Workspace ID。"
            phase = .monitoringLocal
            return
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
            applyTranscriptUpdate(transcriptStabilizer.apply(event))
            await enqueueCommittedSegmentsForTranslation()
            if case .final = event {
                saveCurrentSession()
            }
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

    func saveCurrentSession() {
        guard let pendingSave = makeCurrentSessionSave() else { return }
        Task { [sessionHistoryWriter] in
            await sessionHistoryWriter.submit(pendingSave.record, revision: pendingSave.revision)
        }
    }

    private func makeCurrentSessionSave() -> (record: SavedLectureSession, revision: Int)? {
        guard let session = activeSession else { return nil }

        let savedSegments = captionSegments
            .filter { $0.state != .provisional }
            .sorted { $0.sequence < $1.sequence }
        guard !savedSegments.isEmpty else { return nil }

        let record = SavedLectureSession(session: session, segments: savedSegments)
        savedSessions.removeAll { $0.id == record.id }
        savedSessions.append(record)
        savedSessions.sort { $0.startedAt > $1.startedAt }
        sessionHistoryRevision += 1
        return (record, sessionHistoryRevision)
    }

    func removeSavedSession(id: UUID) {
        savedSessions.removeAll { $0.id == id }
        Task { [weak self, sessionHistoryWriter] in
            do {
                try await sessionHistoryWriter.remove(id: id)
            } catch {
                self?.showSessionHistoryWriteError(error)
            }
        }
    }

    private func startSessionHistoryEventHandling() {
        let events = sessionHistoryWriter.events()
        sessionHistoryEventsTask = Task { [weak self] in
            for await event in events {
                guard let self else { return }
                if case let .failed(message) = event {
                    captureError = "无法保存本地课堂记录。\n\(message)"
                }
            }
        }
    }

    private func showSessionHistoryWriteError(_ error: Error) {
        captureError = "无法删除本地课堂记录。\n\(error.localizedDescription)"
    }

    private static let minimumCaptionFontSize: CGFloat = 14
    private static let maximumCaptionFontSize: CGFloat = 30
    private static let captionFontSizeStep: CGFloat = 2

    private func startTranslationEventHandling(generation: Int) {
        translationEventsTask?.cancel()
        let events = translationQueue.events()
        translationEventsTask = Task { [weak self] in
            for await event in events {
                guard let self, self.sessionGeneration == generation else { return }
                self.applyTranslationEvent(event)
            }
        }
    }

    private func enqueueCommittedSegmentsForTranslation() async {
        guard !isDeepSeekTranslationDisabled else { return }
        let confirmedSegments = captionSegments.filter { $0.state != .provisional }
        let segmentsToTranslate = confirmedSegments
            .filter { $0.state == .committed && !translatedSegmentIDs.contains($0.id) }
            .sorted { $0.sequence < $1.sequence }
        var requests: [TranslationRequest] = []

        for segment in segmentsToTranslate {
            translatedSegmentIDs.insert(segment.id)
            guard let index = captionSegments.firstIndex(where: { $0.id == segment.id }) else { continue }
            captionSegments[index].state = .translating
            let recentContext = confirmedSegments
                .filter { $0.sequence < segment.sequence }
                .suffix(4)
                .map(\.sourceText)
            requests.append(TranslationRequest(
                segmentID: segment.id,
                sourceText: segment.sourceText,
                recentContext: recentContext,
                courseName: courseName,
                topic: topic,
                glossary: glossary,
                sourceLanguage: sourceLanguage,
                targetLanguage: targetLanguage
            ))
        }
        if !requests.isEmpty {
            await translationQueue.enqueue(requests)
        }
    }

    private func applyTranscriptUpdate(_ updatedSegments: [CaptionSegment]) {
        let translations = Dictionary(
            uniqueKeysWithValues: captionSegments.map { ($0.id, ($0.translatedText, $0.state)) }
        )
        captionSegments = updatedSegments.map { segment in
            guard let (translation, state) = translations[segment.id] else { return segment }
            var merged = segment
            merged.translatedText = translation
            if state == .translating || state == .completed || state == .translationFailed {
                merged.state = state
            }
            return merged
        }
    }

    private var isDeepSeekTranslationDisabled: Bool {
        let enteredKey = deepSeekAPIKey.trimmingCharacters(in: .whitespacesAndNewlines)
        if !enteredKey.isEmpty { return false }
        return (try? LocalCredentialsStore.default.loadDeepSeekAPIKey())?.isEmpty != false
    }

    private func applyTranslationEvent(_ event: TranslationQueueEvent) {
        switch event {
        case let .translated(segmentID, text):
            guard let index = captionSegments.firstIndex(where: { $0.id == segmentID }) else { return }
            captionSegments[index].translatedText = text
            captionSegments[index].state = .completed
            saveCurrentSession()
        case let .failed(segmentID):
            guard let index = captionSegments.firstIndex(where: { $0.id == segmentID }) else { return }
            captionSegments[index].state = .translationFailed
            saveCurrentSession()
        }
    }
}
