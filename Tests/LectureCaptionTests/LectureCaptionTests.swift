import Foundation
import ScreenCaptureKit
import Testing
@preconcurrency import AVFoundation
@testable import LectureCaption

@Test @MainActor func automaticPauseKeepsLocalMonitoringReady() {
    let appState = AppState()

    appState.phase = .monitoringLocal
    appState.receiveInputActivity(true)
    appState.receiveSilence(elapsed: 30)

    #expect(appState.phase == .autoPaused)
    #expect(appState.isInputActive == false)
}

@Test @MainActor func manualPauseDoesNotResumeFromInputActivity() {
    let appState = AppState()

    appState.phase = .monitoringLocal
    appState.receiveInputActivity(true)
    appState.pauseSession()
    appState.receiveInputActivity(true)

    #expect(appState.phase == .manuallyPaused)
}

@Test @MainActor func inputActivityResumesAnAutomaticallyPausedSession() {
    let appState = AppState()

    appState.phase = .monitoringLocal
    appState.receiveInputActivity(true)
    appState.receiveSilence(elapsed: 30)
    appState.receiveInputActivity(true)

    #expect(appState.phase == .recognizing)
}

@Test @MainActor func systemAudioRequiresAnApplicationTargetBeforeStarting() {
    let appState = AppState()

    appState.inputSource = .systemAudio
    #expect(!appState.canStart)

    appState.selectedSystemAudioTarget = SystemAudioTarget(
        processID: 42,
        applicationName: "Example Player",
        bundleIdentifier: "com.example.player"
    )
    #expect(appState.canStart)
}

@Test func allSystemAudioTargetIsDistinctAndRecognized() {
    #expect(SystemAudioTarget.allSystemAudio.capturesAllSystemAudio)
    #expect(SystemAudioTarget.allSystemAudio.processID == 0)
    #expect(SystemAudioTarget.allSystemAudio.captureScope == .allSystemAudio)

    let applicationTarget = SystemAudioTarget(
        processID: 42,
        applicationName: "Example Player",
        bundleIdentifier: "com.example.player"
    )
    #expect(!applicationTarget.capturesAllSystemAudio)
    #expect(applicationTarget.captureScope == .application(processID: 42))
}

@Test func captureGenerationInvalidatesAnOlderPendingStart() {
    var gate = CaptureGenerationGate()
    let firstStart = gate.begin()

    gate.invalidate()
    let secondStart = gate.begin()

    #expect(!gate.accepts(firstStart))
    #expect(gate.accepts(secondStart))
}

@Test func capturePermissionStatusMapsMicrophoneAndScreenAccess() {
    #expect(AudioCapturePermission.microphoneStatus(for: .authorized) == .authorized)
    #expect(AudioCapturePermission.microphoneStatus(for: .notDetermined) == .notDetermined)
    #expect(AudioCapturePermission.microphoneStatus(for: .denied) == .denied)
    #expect(AudioCapturePermission.microphoneStatus(for: .restricted) == .restricted)
    #expect(
        AudioCapturePermission.systemAudioStatus(
            hasLegacyScreenCaptureAccess: true,
            hasScreenCaptureKitAccess: false
        ) == .authorized
    )
    #expect(
        AudioCapturePermission.systemAudioStatus(
            hasLegacyScreenCaptureAccess: false,
            hasScreenCaptureKitAccess: true
        ) == .authorized
    )
    #expect(
        AudioCapturePermission.systemAudioStatus(
            hasLegacyScreenCaptureAccess: false,
            hasScreenCaptureKitAccess: false
        ) == .requiresSystemSettings
    )
}

@Test func systemAudioPermissionStatePreservesVerifiedAccessUntilDenied() {
    var state = SystemAudioPermissionState()

    #expect(state.refresh(legacyAccess: false) == .requiresSystemSettings)
    #expect(state.record(.authorized, legacyAccess: false) == .authorized)
    #expect(state.refresh(legacyAccess: false) == .authorized)
    #expect(state.record(.unavailable, legacyAccess: false) == .authorized)
    #expect(state.record(.permissionDenied, legacyAccess: true) == .requiresSystemSettings)
}

@Test func screenCaptureKitPermissionErrorsAreClassifiedSeparately() {
    let denied = NSError(domain: SCStreamErrorDomain, code: -3_801)
    let unavailable = NSError(domain: SCStreamErrorDomain, code: -3_802)

    #expect(AudioCapturePermission.screenCaptureKitAccessResult(for: denied) == .permissionDenied)
    #expect(AudioCapturePermission.screenCaptureKitAccessResult(for: unavailable) == .unavailable)
}

@Test func screenCaptureKitDiagnosticIncludesErrorDomainAndCode() {
    let error = NSError(domain: SCStreamErrorDomain, code: -3_801, userInfo: [
        NSLocalizedDescriptionKey: "Permission denied"
    ])

    let message = AudioCapturePermission.diagnosticMessage(for: error)

    #expect(message.contains(SCStreamErrorDomain))
    #expect(message.contains("-3801"))
}

@Test func chunkerEmitsFixedDurationFramesAndFlushesRemainder() {
    var chunker = PCM16Chunker(sampleRate: 16_000, chunkDuration: 0.04)
    let input = PCM16Frame(
        sequence: 0,
        data: pcm16Data(sampleCount: 960, value: 1_000),
        sampleRate: 16_000,
        startedAt: 5
    )

    let chunks = chunker.append(input)
    let remainder = chunker.flush()

    #expect(chunks.count == 1)
    #expect(chunks[0].data.count == 1_280)
    #expect(chunks[0].startedAt == 5)
    #expect(remainder?.data.count == 640)
    #expect(remainder?.startedAt == 5.04)
}

@Test func pcm16GainAppliesTwentyDecibelsAndSaturates() {
    let frame = PCM16Frame(
        sequence: 7,
        data: pcm16Data(samples: [1_000, -1_000, 4_000, -4_000]),
        sampleRate: 16_000,
        startedAt: 12.5
    )

    let amplified = PCM16Gain.applying(20, to: frame)
    let samples: [Int16] = amplified.data.withUnsafeBytes { rawBuffer in
        Array(rawBuffer.bindMemory(to: Int16.self))
    }

    #expect(samples == [10_000, -10_000, Int16.max, Int16.min])
    #expect(amplified.sequence == frame.sequence)
    #expect(amplified.sampleRate == frame.sampleRate)
    #expect(amplified.startedAt == frame.startedAt)
}

@Test func audioPipelineUsesGainForDetectionWithoutChangingOutgoingAudio() throws {
    let format = AVAudioFormat(
        commonFormat: .pcmFormatInt16,
        sampleRate: 16_000,
        channels: 1,
        interleaved: true
    )!
    let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: 320)!
    buffer.frameLength = 320
    buffer.int16ChannelData![0].initialize(repeating: 100, count: 320)

    let pipeline = AudioPipeline(
        chunkDuration: 0.02,
        activityConfiguration: LocalActivityConfiguration(activationHold: 0.02),
        detectionGainDB: 20
    )
    let output = try #require(try pipeline.process(buffer: buffer, startedAt: 0))
    let expectedData = pcm16Data(sampleCount: 320, value: 100)

    #expect(output.isInputActive)
    #expect(output.levelDBFS > -35)
    #expect(output.preRollData == expectedData)
    #expect(output.chunks.first?.data == expectedData)
}

@Test func preRollBufferKeepsOnlyTheMostRecentAudio() {
    var buffer = PreRollAudioBuffer(maximumDuration: 0.1, sampleRate: 16_000)
    let first = PCM16Frame(sequence: 0, data: pcm16Data(sampleCount: 960, value: 100), sampleRate: 16_000, startedAt: 0)
    let second = PCM16Frame(sequence: 1, data: pcm16Data(sampleCount: 960, value: 200), sampleRate: 16_000, startedAt: 0.06)

    buffer.append(first)
    buffer.append(second)

    #expect(buffer.data.count == 3_200)
    #expect(buffer.data == Data((first.data + second.data).suffix(3_200)))
}

@Test func localActivityDetectorUsesActivationAndReleaseHysteresis() {
    var detector = LocalActivityDetector(
        configuration: LocalActivityConfiguration(
            analysisWindow: 0.02,
            activationHold: 0.04,
            releaseHold: 0.04,
            preRoll: 0.8,
            activationAboveNoiseFloor: 12,
            releaseAboveNoiseFloor: 6
        )
    )
    let quiet = PCM16Frame(sequence: 0, data: pcm16Data(sampleCount: 320, value: 0), sampleRate: 16_000, startedAt: 0)
    let loud = PCM16Frame(sequence: 1, data: pcm16Data(sampleCount: 320, value: 16_000), sampleRate: 16_000, startedAt: 0.02)

    _ = detector.process(quiet)
    let beforeActivation = detector.process(loud)
    let activation = detector.process(loud)
    let beforeRelease = detector.process(quiet)
    let release = detector.process(quiet)

    #expect(beforeActivation.event == .none)
    #expect(activation.event == LocalActivityEvent.started)
    #expect(activation.isActive)
    #expect(beforeRelease.event == .none)
    #expect(release.event == LocalActivityEvent.stopped)
    #expect(!release.isActive)
}

@Test func localActivityDetectorReturnsToIdleForStableBackgroundNoise() {
    var detector = LocalActivityDetector(
        configuration: LocalActivityConfiguration(
            analysisWindow: 0.02,
            activationHold: 0.04,
            releaseHold: 0.04,
            preRoll: 0.8,
            activationAboveNoiseFloor: 12,
            releaseAboveNoiseFloor: 6,
            stableNoiseHold: 0.04,
            stableNoiseToleranceDB: 2,
            maximumAdaptiveNoiseDBFS: -35
        )
    )
    let steadyNoise = PCM16Frame(
        sequence: 0,
        data: pcm16Data(sampleCount: 320, value: 330),
        sampleRate: 16_000,
        startedAt: 0
    )

    var lastMeasurement: LocalActivityMeasurement?
    for _ in 0..<200 {
        lastMeasurement = detector.process(steadyNoise)
    }

    #expect(lastMeasurement?.isActive == false)
    #expect(lastMeasurement?.noiseFloorDBFS ?? -96 > -50)
}

private func pcm16Data(sampleCount: Int, value: Int16) -> Data {
    let samples = Array(repeating: value.littleEndian, count: sampleCount)
    return samples.withUnsafeBytes { Data($0) }
}

private func pcm16Data(samples: [Int16]) -> Data {
    samples.withUnsafeBytes { Data($0) }
}
