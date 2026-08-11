import SwiftUI

struct CaptionPreviewView: View {
    let segments: [CaptionSegment]

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            if segments.isEmpty {
                ContentUnavailableView(
                    "等待字幕",
                    systemImage: "captions.bubble",
                    description: Text("开始会话后将在此显示已确认原文和译文。")
                )
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                ForEach(segments.suffix(6)) { segment in
                    VStack(alignment: .leading, spacing: 4) {
                        Text(segment.sourceText)
                            .font(.headline)
                            .foregroundStyle(segment.state == .provisional ? .secondary : .primary)

                        if let translation = segment.translatedText {
                            Text(translation)
                                .font(.body)
                                .foregroundStyle(.secondary)
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.vertical, 4)
                }
            }
        }
        .padding(20)
        .background(.regularMaterial)
    }
}
