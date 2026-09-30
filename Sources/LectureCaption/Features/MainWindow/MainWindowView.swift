import SwiftUI

struct MainWindowView: View {
    @Bindable var appState: AppState
    @State private var showsConfiguration = false
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

                Button {
                    showsConfiguration = true
                } label: {
                    Image(systemName: "slider.horizontal.3")
                }
                .help("课程与识别配置")
                .accessibilityLabel("课程与识别配置")

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
        .sheet(isPresented: $showsConfiguration) {
            ConfigurationView(appState: appState)
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

private struct ConfigurationView: View {
    @Bindable var appState: AppState
    @Environment(\.dismiss) private var dismiss
    @State private var newTerm = ""
    @State private var newTranslation = ""

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text("课程与识别配置")
                    .font(.headline)
                Spacer()
                Button("完成") { dismiss() }
            }
            .padding()
            Divider()

            configurationForm
        }
        .frame(width: 500, height: 680)
    }

    private var configurationForm: some View {
        Form {
            Section("会话") {
                Picker("识别", selection: $appState.speechProvider) {
                    ForEach(SpeechProviderKind.allCases) { provider in
                        Text(provider.title).tag(provider)
                    }
                }

                Picker("自动待机", selection: Binding(
                    get: { AutoPauseOption.option(for: appState.autoPauseInterval) },
                    set: { appState.autoPauseInterval = $0.interval }
                )) {
                    ForEach(AutoPauseOption.allCases) { option in
                        Text(option.title).tag(option)
                    }
                }
            }

            Section("阿里云识别") {
                TextField("Workspace ID", text: $appState.aliyunWorkspaceID)
                Picker("地域", selection: $appState.aliyunRegion) {
                    ForEach(AliyunRealtimeSettings.Region.allCases, id: \.self) { region in
                        Text(region.displayName).tag(region)
                    }
                }
                SecureField("API Key（仅在填写或替换时输入）", text: $appState.aliyunAPIKey)
            }

            Section("DeepSeek 翻译") {
                SecureField("API Key（留空则仅显示原文）", text: $appState.deepSeekAPIKey)
            }

            Section("课程") {
                TextField("课程名称", text: $appState.courseName)
                TextField("本节主题", text: $appState.topic)

                Picker("原文语言", selection: $appState.sourceLanguage) {
                    ForEach(RecognitionLanguage.allCases) { language in
                        Text(language.title).tag(language)
                    }
                }

                Picker("译文语言", selection: $appState.targetLanguage) {
                    ForEach(TargetLanguage.allCases) { language in
                        Text(language.title).tag(language)
                    }
                }
            }

            Section("术语表") {
                ForEach($appState.glossary) { $entry in
                    HStack {
                        TextField("原文", text: $entry.source)
                        TextField("译文", text: $entry.target)
                        Button("删除", systemImage: "minus.circle") {
                            appState.removeGlossaryEntry(id: entry.id)
                        }
                        .labelStyle(.iconOnly)
                        .buttonStyle(.borderless)
                    }
                }

                HStack {
                    TextField("原文", text: $newTerm)
                    TextField("译文", text: $newTranslation)
                    Button("添加", systemImage: "plus") {
                        let source = newTerm.trimmingCharacters(in: .whitespacesAndNewlines)
                        let target = newTranslation.trimmingCharacters(in: .whitespacesAndNewlines)
                        guard !source.isEmpty, !target.isEmpty else { return }
                        appState.glossary.append(GlossaryEntry(source: source, target: target))
                        newTerm = ""
                        newTranslation = ""
                    }
                    .labelStyle(.iconOnly)
                }
            }
        }
        .formStyle(.grouped)
        .padding(.horizontal, 12)
    }
}
