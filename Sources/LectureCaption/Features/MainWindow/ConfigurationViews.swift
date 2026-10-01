import SwiftUI

enum ConfigurationDestination: String, CaseIterable, Identifiable {
    case course
    case api

    var id: Self { self }
    var title: String { self == .course ? "课程配置" : "API 配置" }
    var symbolName: String { self == .course ? "book.closed" : "key" }
}

private struct ConfigurationSheet<Content: View>: View {
    let title: String
    @ViewBuilder var content: Content
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 12) {
                Button(action: dismiss.callAsFunction) {
                    Image(systemName: "chevron.left")
                }
                .help("返回实时字幕")
                .accessibilityLabel("返回实时字幕")
                Text(title)
                    .font(.headline)
                Spacer()
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 12)
            .background(.bar)
            Divider()
            content
                .formStyle(.grouped)
                .padding(.horizontal, 12)
        }
        .frame(width: 500, height: 680)
    }
}

struct APIConfigurationView: View {
    @Bindable var appState: AppState

    var body: some View {
        ConfigurationSheet(title: ConfigurationDestination.api.title) {
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
        }
    }
}

struct CourseConfigurationView: View {
    @Bindable var appState: AppState
    @State private var newTerm = ""
    @State private var newTranslation = ""

    var body: some View {
        ConfigurationSheet(title: ConfigurationDestination.course.title) {
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
        }
    }
}
