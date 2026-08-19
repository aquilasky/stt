import SwiftUI

struct SessionHistoryView: View {
    @Bindable var appState: AppState
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            Group {
                if appState.savedSessions.isEmpty {
                    ContentUnavailableView(
                        "暂无本地记录",
                        systemImage: "clock.arrow.circlepath",
                        description: Text("结束课堂或点击保存记录后，会在这里保留完整双语字幕。")
                    )
                } else {
                    List {
                        ForEach(appState.savedSessions) { record in
                            NavigationLink {
                                SavedSessionDetailView(
                                    record: record,
                                    fontSize: appState.captionFontSize,
                                    showsTimestamps: appState.isCaptionTimestampVisible
                                )
                            } label: {
                                VStack(alignment: .leading, spacing: 4) {
                                    Text(LocalSessionRecordName.string(startedAt: record.startedAt))
                                        .font(.headline)
                                    Text(record.session.context.courseName.isEmpty ? "未填写课程名称" : record.session.context.courseName)
                                        .foregroundStyle(.secondary)
                                    Text(record.session.context.topic.isEmpty ? "未填写主题" : record.session.context.topic)
                                        .font(.caption)
                                        .foregroundStyle(.tertiary)
                                }
                            }
                        }
                        .onDelete { offsets in
                            let ids = offsets.map { appState.savedSessions[$0].id }
                            ids.forEach(appState.removeSavedSession)
                        }
                    }
                }
            }
            .navigationTitle("本地课堂记录")
            .toolbar {
                ToolbarItem(placement: .navigation) {
                    Button(action: dismiss.callAsFunction) {
                        Image(systemName: "chevron.left")
                    }
                    .help("返回实时字幕")
                    .accessibilityLabel("返回实时字幕")
                }
            }
        }
        .frame(minWidth: 620, minHeight: 500)
    }
}

private struct SavedSessionDetailView: View {
    let record: SavedLectureSession
    let fontSize: CGFloat
    let showsTimestamps: Bool
    @State private var exportFormat: SavedSessionExportFormat = .text
    @State private var includesTimestamps = true
    @State private var exportDocument: SessionExportDocument?
    @State private var isExporting = false
    @State private var exportError: String?

    var body: some View {
        VStack(spacing: 0) {
            exportControls
            Divider()
            CaptionPreviewView(
                segments: record.segments,
                fontSize: fontSize,
                sessionStartedAt: record.session.startedAt,
                showsTimestamps: showsTimestamps
            )
        }
            .navigationTitle(LocalSessionRecordName.string(startedAt: record.startedAt))
            .fileExporter(
                isPresented: $isExporting,
                document: exportDocument,
                contentType: exportFormat.contentType,
                defaultFilename: SavedSessionExporter.defaultFilename(for: record)
            ) { result in
                if case let .failure(error) = result {
                    exportError = "无法导出课堂记录。\n\(error.localizedDescription)"
                }
            }
            .alert(
                "导出失败",
                isPresented: Binding(
                    get: { exportError != nil },
                    set: { if !$0 { exportError = nil } }
                )
            ) {
                Button("好", role: .cancel) {
                    exportError = nil
                }
            } message: {
                Text(exportError ?? "")
            }
    }

    private var exportControls: some View {
        HStack(spacing: 12) {
            Picker("导出格式", selection: $exportFormat) {
                ForEach(SavedSessionExportFormat.allCases) { format in
                    Text(format.title).tag(format)
                }
            }
            .pickerStyle(.menu)
            .frame(width: 120)

            Toggle(isOn: $includesTimestamps) {
                Image(systemName: "clock")
            }
            .toggleStyle(.button)
            .help(includesTimestamps ? "导出时包含时间戳" : "导出时不包含时间戳")
            .accessibilityLabel("导出时包含时间戳")

            Button(action: prepareExport) {
                Image(systemName: "square.and.arrow.up")
            }
            .help("导出\(exportFormat.title) 记录")
            .accessibilityLabel("导出课堂记录")

            Spacer()
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 10)
        .background(.bar)
    }

    private func prepareExport() {
        do {
            exportDocument = try SavedSessionExporter.document(
                for: record,
                format: exportFormat,
                includesTimestamps: includesTimestamps
            )
            isExporting = true
        } catch {
            exportError = "无法准备导出内容。\n\(error.localizedDescription)"
        }
    }
}
