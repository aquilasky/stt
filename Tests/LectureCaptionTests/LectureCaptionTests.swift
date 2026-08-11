import Testing
@testable import LectureCaption

@Test @MainActor func automaticPauseKeepsLocalMonitoringReady() {
    let appState = AppState()

    appState.startSession()
    appState.receiveInputActivity(true)
    appState.receiveSilence(elapsed: 30)

    #expect(appState.phase == .autoPaused)
    #expect(appState.isInputActive == false)
}

@Test @MainActor func manualPauseDoesNotResumeFromInputActivity() {
    let appState = AppState()

    appState.startSession()
    appState.receiveInputActivity(true)
    appState.pauseSession()
    appState.receiveInputActivity(true)

    #expect(appState.phase == .manuallyPaused)
}

@Test @MainActor func inputActivityResumesAnAutomaticallyPausedSession() {
    let appState = AppState()

    appState.startSession()
    appState.receiveInputActivity(true)
    appState.receiveSilence(elapsed: 30)
    appState.receiveInputActivity(true)

    #expect(appState.phase == .recognizing)
}
