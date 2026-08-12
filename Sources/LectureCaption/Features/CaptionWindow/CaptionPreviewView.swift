import SwiftUI

struct CaptionPreviewView: View {
    let segments: [CaptionSegment]
    let fontSize: CGFloat

    var body: some View {
        Group {
            if segments.isEmpty {
                ContentUnavailableView(
                    "等待字幕",
                    systemImage: "captions.bubble",
                    description: Text("开始会话后将在此显示已确认原文和译文。")
                )
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                ScrollViewReader { scrollProxy in
                    ScrollView {
                        LazyVStack(alignment: .leading, spacing: 18) {
                            ForEach(segments) { segment in
                                VStack(alignment: .leading, spacing: 6) {
                                    Text(segment.sourceText)
                                        .font(.system(size: fontSize, weight: .medium))
                                        .foregroundStyle(segment.state == .provisional ? .secondary : .primary)

                                    if let translation = segment.translatedText {
                                        Text(translation)
                                            .font(.system(size: max(13, fontSize - 2)))
                                            .foregroundStyle(.secondary)
                                    }
                                }
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .textSelection(.enabled)
                                .padding(.vertical, 2)
                            }
                            Color.clear
                                .frame(height: 1)
                                .id("caption-bottom")
                        }
                        .padding(24)
                    }
                    .onAppear {
                        scrollToLatest(using: scrollProxy)
                    }
                    .onChange(of: latestCaptionToken) {
                        scrollToLatest(using: scrollProxy)
                    }
                }
            }
        }
        .background(.regularMaterial)
    }

    private func scrollToLatest(using scrollProxy: ScrollViewProxy) {
        withAnimation(.easeOut(duration: 0.2)) {
            scrollProxy.scrollTo("caption-bottom", anchor: .bottom)
        }
    }

    private var latestCaptionToken: String {
        guard let segment = segments.last else { return "" }
        return "\(segment.id.uuidString)|\(segment.sourceText)|\(segment.translatedText ?? "")"
    }
}
