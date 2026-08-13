import SwiftUI

struct FloatingCaptionWindowView: View {
    @Bindable var appState: AppState
    @State private var isHovering = false

    var body: some View {
        ZStack(alignment: .topTrailing) {
            captionContent
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: captionAlignment)
                .padding(.horizontal, 28)
                // Keep text below the hover controls at every font size and panel width.
                .padding(.top, 68)
                .padding(.bottom, 32)

            if isHovering {
                controls
                    .padding(14)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .foregroundStyle(.white)
        .background(Color.black.opacity(appState.floatingCaptionBackgroundOpacity))
        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
        .padding(6)
        .onHover { isHovering = $0 }
    }

    private var captionContent: some View {
        return Group {
            if displayedSegments.isEmpty {
                Label("等待字幕", systemImage: "captions.bubble")
                    .font(.system(size: appState.floatingCaptionFontSize, weight: .medium))
                    .foregroundStyle(.white.opacity(0.72))
            } else {
                ScrollView(.vertical) {
                    LazyVStack(alignment: .leading, spacing: 16) {
                        ForEach(displayedSegments) { segment in
                            FloatingCaptionSegmentView(
                                segment: segment,
                                mode: appState.floatingCaptionDisplayMode,
                                fontSize: appState.floatingCaptionFontSize
                            )
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
                .scrollIndicators(.automatic)
            }
        }
    }

    private var captionAlignment: Alignment {
        displayedSegments.isEmpty ? .center : .bottomLeading
    }

    private var displayedSegments: [CaptionSegment] {
        appState.floatingCaptionDisplayMode.visibleSegments(from: appState.captionSegments)
    }

    private var controls: some View {
        HStack(spacing: 6) {
            Button(action: appState.decreaseFloatingCaptionFontSize) {
                Image(systemName: "textformat.size.smaller")
            }
            .help("减小字幕字号")
            .disabled(appState.floatingCaptionFontSize <= 14)

            Button(action: appState.increaseFloatingCaptionFontSize) {
                Image(systemName: "textformat.size.larger")
            }
            .help("增大字幕字号")
            .disabled(appState.floatingCaptionFontSize >= 30)

            Menu {
                Picker("字幕显示", selection: $appState.floatingCaptionDisplayMode) {
                    ForEach(FloatingCaptionDisplayMode.allCases) { mode in
                        Label(mode.title, systemImage: mode.symbolName).tag(mode)
                    }
                }
            } label: {
                Image(systemName: appState.floatingCaptionDisplayMode.symbolName)
            }
            .help("字幕显示模式")

            Menu {
                Slider(value: $appState.floatingCaptionBackgroundOpacity, in: 0.35...0.95) {
                    Text("背景不透明度")
                }
                .frame(width: 160)
            } label: {
                Image(systemName: "circle.lefthalf.filled")
            }
            .help("背景不透明度")

            Button {
                appState.isFloatingCaptionVisible = false
            } label: {
                Image(systemName: "xmark")
            }
            .help("隐藏悬浮字幕")
        }
        .buttonStyle(.bordered)
        .controlSize(.small)
        .padding(6)
        .background(.black.opacity(0.7), in: RoundedRectangle(cornerRadius: 6, style: .continuous))
    }
}

private struct FloatingCaptionSegmentView: View {
    let segment: CaptionSegment
    let mode: FloatingCaptionDisplayMode
    let fontSize: CGFloat

    var body: some View {
        VStack(alignment: .leading, spacing: 5) {
            if mode != .translationOnly {
                Text(segment.sourceText)
                    .font(.system(size: fontSize, weight: .semibold))
                    .foregroundStyle(segment.state == .provisional ? .white.opacity(0.58) : .white)
                    .fixedSize(horizontal: false, vertical: true)
            }

            if mode != .sourceOnly, let translation = segment.translatedText {
                Text(translation)
                    .font(.system(size: max(13, fontSize - 3), weight: .medium))
                    .foregroundStyle(.white.opacity(0.82))
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}
