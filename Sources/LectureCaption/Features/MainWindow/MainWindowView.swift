import SwiftUI

struct MainWindowView: View {
    @Bindable var appState: AppState

    @State private var newTerm = ""
    @State private var newTranslation = ""

    var body: some View {
        VStack(spacing: 0) {
            controlStrip
            Divider()

            HSplitView {
                setupPane
                    .frame(minWidth: 330, idealWidth: 360, maxWidth: 420)

                CaptionPreviewView(segments: appState.captionSegments)
                    .frame(minWidth: 500, maxWidth: .infinity, maxHeight: .infinity)
            }
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
                    Task { await appState.startSession() }
                } label: {
                    Label("开始", systemImage: "play.fill")
                }
                .disabled(!appState.canStart)

                Button(action: appState.pauseSession) {
                    Label("暂停", systemImage: "pause.fill")
                }
                .disabled(!appState.canPause)

                Button(action: appState.resumeSession) {
                    Label("继续", systemImage: "playpause.fill")
                }
                .disabled(appState.phase != .manuallyPaused)

                Button(action: appState.stopSession) {
                    Label("结束", systemImage: "stop.fill")
                }
                .disabled(appState.phase == .idle || appState.phase == .completed)
            }
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

    private var setupPane: some View {
        Form {
            Section("会话") {
                Picker("输入", selection: $appState.inputSource) {
                    ForEach(AudioInputSource.allCases) { source in
                        Text(source.title).tag(source)
                    }
                }

                if appState.inputSource == .systemAudio {
                    Picker("目标应用", selection: $appState.selectedSystemAudioTarget) {
                        Text("选择应用").tag(nil as SystemAudioTarget?)
                        ForEach(appState.systemAudioTargets) { target in
                            Text(target.applicationName).tag(Optional(target))
                        }
                    }
                    .disabled(appState.isRefreshingSystemAudioTargets)

                    Button("刷新应用列表", systemImage: "arrow.clockwise") {
                        Task { await appState.refreshSystemAudioTargets() }
                    }
                    .disabled(appState.isRefreshingSystemAudioTargets)
                }

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
