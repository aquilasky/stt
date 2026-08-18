import SwiftUI

struct SessionHistorySidebar: View {
    @Bindable var appState: AppState
    @Binding var selectedSessionID: UUID?
    let onClose: () -> Void
    @State private var searchText = ""

    var body: some View {
        VStack(spacing: 0) {
            SidebarHeader(title: "课堂记录", onClose: onClose)

            TextField("搜索记录", text: $searchText)
                .textFieldStyle(.roundedBorder)
                .padding(12)

            if filteredSessions.isEmpty {
                ContentUnavailableView(
                    searchText.isEmpty ? "暂无本地记录" : "没有匹配记录",
                    systemImage: "clock.arrow.circlepath",
                    description: Text(searchText.isEmpty ? "结束课堂或点击保存记录后，会在这里保留完整双语字幕。" : "尝试其他课程名称或主题。")
                )
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                List(selection: $selectedSessionID) {
                    ForEach(filteredSessions) { record in
                        SessionHistoryRow(record: record)
                            .tag(record.id)
                            .contextMenu {
                                Button("删除", role: .destructive) {
                                    remove(record)
                                }
                            }
                    }
                }
            }

            Divider()
            HStack {
                Button(role: .destructive) {
                    guard let selectedSessionID,
                          let record = appState.savedSessions.first(where: { $0.id == selectedSessionID }) else {
                        return
                    }
                    remove(record)
                } label: {
                    Label("删除记录", systemImage: "trash")
                }
                .disabled(selectedSessionID == nil)

                Spacer()
            }
            .padding(12)
        }
        .background(.regularMaterial)
    }

    private var filteredSessions: [SavedLectureSession] {
        let query = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !query.isEmpty else { return appState.savedSessions }

        return appState.savedSessions.filter { record in
            record.session.context.courseName.localizedCaseInsensitiveContains(query)
                || record.session.context.topic.localizedCaseInsensitiveContains(query)
        }
    }

    private func remove(_ record: SavedLectureSession) {
        appState.removeSavedSession(id: record.id)
        if selectedSessionID == record.id {
            selectedSessionID = nil
        }
    }
}

private struct SessionHistoryRow: View {
    let record: SavedLectureSession

    var body: some View {
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

struct SavedSessionDetailWorkspace: View {
    let record: SavedLectureSession
    let fontSize: CGFloat
    let onReturnToLiveCaptions: () -> Void

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text(record.session.context.courseName.isEmpty ? "课堂记录" : record.session.context.courseName)
                    .font(.headline)
                Spacer()
                Button(action: onReturnToLiveCaptions) {
                    Label("返回实时字幕", systemImage: "captions.bubble")
                }
            }
            .padding(.horizontal, 18)
            .frame(height: 44)
            Divider()

            CaptionPreviewView(segments: record.segments, fontSize: fontSize)
        }
        .background(.regularMaterial)
    }
}
