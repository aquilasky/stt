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
                                SavedSessionDetailView(record: record, fontSize: appState.captionFontSize)
                            } label: {
                                VStack(alignment: .leading, spacing: 4) {
                                    Text(record.session.context.courseName.isEmpty ? "未命名课堂" : record.session.context.courseName)
                                        .font(.headline)
                                    Text(record.session.context.topic.isEmpty ? "未填写主题" : record.session.context.topic)
                                        .foregroundStyle(.secondary)
                                    Text(record.startedAt, format: .dateTime.year().month().day().hour().minute())
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
                ToolbarItem(placement: .cancellationAction) {
                    Button("完成") { dismiss() }
                }
            }
        }
        .frame(minWidth: 620, minHeight: 500)
    }
}

private struct SavedSessionDetailView: View {
    let record: SavedLectureSession
    let fontSize: CGFloat

    var body: some View {
        CaptionPreviewView(
            segments: record.segments,
            fontSize: fontSize,
            sessionStartedAt: record.session.startedAt
        )
            .navigationTitle(record.session.context.courseName.isEmpty ? "课堂记录" : record.session.context.courseName)
    }
}
