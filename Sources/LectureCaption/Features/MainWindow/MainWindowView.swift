import SwiftUI

struct MainWindowView: View {
    @Bindable var appState: AppState
    @State private var sidebarState = MainWindowSidebarState()
    @State private var sidebarWidth = MainWindowSidebarLayout.defaultWidth
    @State private var selectedSavedSessionID: UUID?
    @State private var floatingCaptionController = FloatingCaptionWindowController()

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 0) {
                activityBar
                sidebarContainer
                workspace
            }

            Divider()
            statusBar
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
        .onChange(of: appState.isFloatingCaptionVisible, initial: true) { _, isVisible in
            floatingCaptionController.setVisible(isVisible, appState: appState)
        }
    }

    private var activityBar: some View {
        VStack(spacing: 4) {
            ForEach(MainWindowSidebarSection.allCases) { section in
                Button {
                    withAnimation(.easeInOut(duration: 0.18)) {
                        sidebarState.activate(section)
                    }
                } label: {
                    ZStack {
                        RoundedRectangle(cornerRadius: 5)
                            .fill(sidebarState.selectedSection == section ? Color.accentColor.opacity(0.18) : .clear)

                        Image(systemName: section.symbolName)
                    }
                    .frame(width: 44, height: 64)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .foregroundStyle(sidebarState.selectedSection == section ? Color.accentColor : .secondary)
                .help(section.title)
                .accessibilityLabel(section.title)
            }

            Spacer()
        }
        .padding(.vertical, 8)
        .frame(width: 44)
        .background(.bar)
    }

    private var sidebarContainer: some View {
        HStack(spacing: 0) {
            sidebarContent
                .frame(width: sidebarWidth)

            SidebarResizeHandle(width: $sidebarWidth)
        }
        .frame(
            width: sidebarState.isVisible ? sidebarWidth + MainWindowSidebarLayout.resizeHandleWidth : 0,
            alignment: .leading
        )
        .opacity(sidebarState.isVisible ? 1 : 0)
        .allowsHitTesting(sidebarState.isVisible)
        .clipped()
        .animation(.easeInOut(duration: 0.18), value: sidebarState.isVisible)
    }

    @ViewBuilder
    private var sidebarContent: some View {
        switch sidebarState.selectedSection {
        case .apiConfiguration:
            APIConfigurationSidebar(appState: appState) {
                withAnimation(.easeInOut(duration: 0.18)) {
                    sidebarState.hide()
                }
            }
        case .courseConfiguration:
            CourseConfigurationSidebar(appState: appState) {
                withAnimation(.easeInOut(duration: 0.18)) {
                    sidebarState.hide()
                }
            }
        case .history:
            SessionHistorySidebar(
                appState: appState,
                selectedSessionID: $selectedSavedSessionID,
                onClose: {
                    withAnimation(.easeInOut(duration: 0.18)) {
                        sidebarState.hide()
                    }
                }
            )
        case nil:
            EmptyView()
        }
    }

    private var workspace: some View {
        ZStack {
            CaptionPreviewView(
                segments: appState.captionSegments,
                fontSize: appState.captionFontSize
            )

            if let selectedSavedSession {
                SavedSessionDetailWorkspace(record: selectedSavedSession, fontSize: appState.captionFontSize) {
                    selectedSavedSessionID = nil
                }
                .transition(.opacity)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var selectedSavedSession: SavedLectureSession? {
        guard let selectedSavedSessionID else { return nil }
        return appState.savedSessions.first { $0.id == selectedSavedSessionID }
    }

    private var statusBar: some View {
        HStack(spacing: 10) {
            Label(appState.phase.title, systemImage: appState.phase.symbolName)
                .foregroundStyle(appState.phase.tint)

            Divider()
                .frame(height: 16)

            Label(appState.isInputActive ? "检测到输入" : "本地监听", systemImage: appState.isInputActive ? "waveform" : "ear")
                .foregroundStyle(.secondary)

            Text("\(Int(appState.inputLevelDBFS.rounded())) dBFS")
                .monospacedDigit()
                .foregroundStyle(.secondary)

            Label(appState.speechProvider.title, systemImage: appState.speechProvider.symbolName)
                .foregroundStyle(.secondary)
        }
        .font(.caption)
        .labelStyle(.titleAndIcon)
        .padding(.horizontal, 14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .frame(height: 30)
        .background(.bar)
        .help(appState.captureError ?? "")
    }

}

struct APIConfigurationSidebar: View {
    @Bindable var appState: AppState
    let onClose: () -> Void

    var body: some View {
        VStack(spacing: 0) {
            SidebarHeader(title: "API 与识别", onClose: onClose)

            configurationForm
        }
        .background(.regularMaterial)
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

        }
        .formStyle(.grouped)
        .padding(.horizontal, 12)
    }
}

struct CourseConfigurationSidebar: View {
    @Bindable var appState: AppState
    let onClose: () -> Void
    @State private var newTerm = ""
    @State private var newTranslation = ""

    var body: some View {
        VStack(spacing: 0) {
            SidebarHeader(title: "课程", onClose: onClose)

            Form {
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
        .background(.regularMaterial)
    }
}

private struct SidebarResizeHandle: View {
    @Binding var width: CGFloat
    @State private var dragOrigin: CGFloat?

    var body: some View {
        Rectangle()
            .fill(.separator.opacity(0.55))
            .frame(width: MainWindowSidebarLayout.resizeHandleWidth)
            .contentShape(Rectangle())
            .help("拖动调整侧栏宽度")
            .gesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { value in
                        if dragOrigin == nil {
                            dragOrigin = width
                        }
                        guard let dragOrigin else { return }
                        width = MainWindowSidebarLayout.clampedWidth(dragOrigin + value.translation.width)
                    }
                    .onEnded { _ in
                        dragOrigin = nil
                    }
            )
    }
}

struct SidebarHeader: View {
    let title: String
    let onClose: () -> Void

    var body: some View {
        HStack {
            Text(title)
                .font(.headline)
            Spacer()
            Button(action: onClose) {
                Image(systemName: "sidebar.left")
            }
            .buttonStyle(.borderless)
            .help("收起侧栏")
            .accessibilityLabel("收起侧栏")
        }
        .padding(.horizontal, 14)
        .frame(height: 44)
        Divider()
    }
}
