import SwiftUI

struct MainWindowView: View {
    @Bindable var appState: AppState
    @State private var configurationDestination: ConfigurationDestination?
    @State private var showsHistory = false
    @State private var startInFlight = false

    var body: some View {
        VStack(spacing: 0) {
            controlStrip
            Divider()

            CaptionPreviewView(
                segments: appState.captionSegments,
                fontSize: appState.captionFontSize,
                sessionStartedAt: appState.activeSession?.startedAt,
                showsTimestamps: appState.isCaptionTimestampVisible
            )
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .alert(
            "无法开始采集",
            isPresented: Binding(
                get: { appState.captureError != nil },
                set: { if !$0 { appState.captureError = nil } }
            )
        ) {
            Button("好", role: .cancel) {
                appState.captureError = nil
            }
        } message: {
            Text(appState.captureError ?? "")
        }
        .frame(minWidth: 900, minHeight: 620)
        .toolbar {
            ToolbarItemGroup(placement: .primaryAction) {
                Button {
                    let action = appState.phase.primaryAction
                    guard action.canTrigger(startInFlight: startInFlight) else { return }
                    switch action {
                    case .start:
                        startInFlight = true
                        Task {
                            await appState.startSession()
                            startInFlight = false
                        }
                    case .resume:
                        appState.resumeSession()
                    case .unavailable:
                        break
                    }
                } label: {
                    Label(appState.phase.primaryAction.title, systemImage: appState.phase.primaryAction.symbolName)
                }
                .disabled(!appState.phase.primaryAction.canTrigger(startInFlight: startInFlight))
                .help(appState.phase.primaryAction.helpText)
                .accessibilityLabel(appState.phase.primaryAction.title)

                Button(action: appState.pauseSession) {
                    Label("暂停", systemImage: "pause.fill")
                }
                .disabled(!appState.canPause)

                Button {
                    Task { await appState.stopSession() }
                } label: {
                    Label("结束", systemImage: "stop.fill")
                }
                .disabled(appState.phase == .idle || appState.phase == .completed)

                Button(action: appState.saveCurrentSession) {
                    Label("保存记录", systemImage: "tray.and.arrow.down")
                }
                .disabled(appState.captionSegments.allSatisfy { $0.state == .provisional })

                Toggle(isOn: $appState.isFloatingCaptionVisible) {
                    Label("悬浮字幕", systemImage: "rectangle.on.rectangle")
                }
                .help("显示或隐藏悬浮字幕")

                Toggle(isOn: $appState.isCaptionTimestampVisible) {
                    Image(systemName: "clock")
                }
                .toggleStyle(.button)
                .help(appState.isCaptionTimestampVisible ? "隐藏时间戳" : "显示时间戳")
                .accessibilityLabel("显示时间戳")

                Toggle(isOn: Binding(
                    get: { appState.isDisplaySleepPreventionEnabled },
                    set: { appState.setDisplaySleepPreventionEnabled($0) }
                )) {
                    Image(systemName: "display")
                }
                .toggleStyle(.button)
                .help(appState.isDisplaySleepPreventionEnabled ? "允许系统自动息屏" : "防止系统自动息屏")
                .accessibilityLabel("防止系统自动息屏")

                ForEach(ConfigurationDestination.allCases) { destination in
                    Button {
                        configurationDestination = destination
                    } label: {
                        Image(systemName: destination.symbolName)
                    }
                    .help(destination.title)
                    .accessibilityLabel(destination.title)
                    .accessibilityIdentifier("configuration.\(destination.rawValue)")
                }

                Button {
                    showsHistory = true
                } label: {
                    Image(systemName: "clock.arrow.circlepath")
                }
                .help("本地课堂记录")
                .accessibilityLabel("本地课堂记录")

                Button(action: appState.decreaseCaptionFontSize) {
                    Label("减小字幕字号", systemImage: "textformat.size.smaller")
                }
                .disabled(!appState.canDecreaseCaptionFontSize)

                Button(action: appState.increaseCaptionFontSize) {
                    Label("增大字幕字号", systemImage: "textformat.size.larger")
                }
                .disabled(!appState.canIncreaseCaptionFontSize)
            }
        }
        .sheet(item: $configurationDestination) { destination in
            switch destination {
            case .course: CourseConfigurationView(appState: appState)
            case .api: APIConfigurationView(appState: appState)
            }
        }
        .sheet(isPresented: $showsHistory) {
            SessionHistoryView(appState: appState)
        }
    }

    private var controlStrip: some View {
        HStack(spacing: 18) {
            Label(appState.phase.title, systemImage: appState.phase.symbolName)
                .foregroundStyle(appState.phase.tint)

            Divider()
                .frame(height: 16)

            Label(appState.isInputActive ? "检测到输入" : "本地监听", systemImage: appState.isInputActive ? "waveform" : "ear")
                .foregroundStyle(.secondary)

            Text("\(Int(appState.inputLevelDBFS.rounded())) dBFS")
                .monospacedDigit()
                .foregroundStyle(.secondary)

            Spacer()

            Label(appState.speechProvider.title, systemImage: appState.speechProvider.symbolName)
                .foregroundStyle(.secondary)
        }
        .font(.callout)
        .padding(.horizontal, 18)
        .frame(height: 44)
        .help(appState.captureError ?? "")
    }

}
