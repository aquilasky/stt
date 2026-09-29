import AppKit
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
                GeometryReader { geometry in
                    ScrollViewReader { scrollProxy in
                        ScrollView(.vertical) {
                            VStack(spacing: 0) {
                                LazyVStack(alignment: .leading, spacing: 16) {
                                    ForEach(displayedSegments) { segment in
                                        FloatingCaptionSegmentView(
                                            segment: segment,
                                            mode: appState.floatingCaptionDisplayMode,
                                            fontSize: appState.floatingCaptionFontSize,
                                            sessionStartedAt: appState.activeSession?.startedAt,
                                            showsTimestamps: appState.isCaptionTimestampVisible
                                        )
                                    }
                                }
                                .frame(maxWidth: .infinity, alignment: .leading)

                                // Allow a short final line to sit at the bottom without an unbounded content frame.
                                Color.clear.frame(height: max(0, geometry.size.height - 1))
                            }
                        }
                        .scrollIndicators(.automatic)
                        .onAppear {
                            scrollToLatest(using: scrollProxy, viewportSize: geometry.size)
                        }
                        .onChange(of: scrollRequest(viewportSize: geometry.size)) { _, request in
                            guard let request else { return }
                            scrollProxy.scrollTo(request.anchor, anchor: .bottom)
                        }
                    }
                }
            }
        }
    }

    private func scrollToLatest(using scrollProxy: ScrollViewProxy, viewportSize: CGSize) {
        guard let request = scrollRequest(viewportSize: viewportSize) else { return }
        scrollProxy.scrollTo(request.anchor, anchor: .bottom)
    }

    private func scrollRequest(viewportSize: CGSize) -> FloatingCaptionScrollRequest? {
        FloatingCaptionScrollRequest(
            segments: displayedSegments,
            mode: appState.floatingCaptionDisplayMode,
            fontSize: appState.floatingCaptionFontSize,
            viewportSize: viewportSize
        )
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

            ForEach(FloatingCaptionDisplayMode.allCases) { mode in
                Button {
                    appState.floatingCaptionDisplayMode = mode
                } label: {
                    Image(systemName: mode.symbolName)
                }
                .help(mode.title)
                .tint(appState.floatingCaptionDisplayMode == mode ? .accentColor : .secondary)
            }

            Button(action: appState.decreaseFloatingCaptionBackgroundOpacity) {
                Image(systemName: "circle.lefthalf.filled")
            }
            .help("降低背景不透明度")
            .disabled(!appState.canDecreaseFloatingCaptionBackgroundOpacity)

            Button(action: appState.increaseFloatingCaptionBackgroundOpacity) {
                Image(systemName: "circle.fill")
            }
            .help("提高背景不透明度")
            .disabled(!appState.canIncreaseFloatingCaptionBackgroundOpacity)

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
        .background(FloatingCaptionControlsRegion())
    }
}

private struct FloatingCaptionControlsRegion: NSViewRepresentable {
    func makeNSView(context: Context) -> FloatingCaptionControlsView {
        FloatingCaptionControlsView()
    }

    func updateNSView(_ nsView: FloatingCaptionControlsView, context: Context) {}
}

/// Geometry only: SwiftUI buttons keep receiving their own mouse events.
final class FloatingCaptionControlsView: NSView {
    override func hitTest(_ point: NSPoint) -> NSView? { nil }
}

private struct FloatingCaptionSegmentView: View {
    let segment: CaptionSegment
    let mode: FloatingCaptionDisplayMode
    let fontSize: CGFloat
    let sessionStartedAt: Date?
    let showsTimestamps: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 5) {
            if showsTimestamps, let sessionStartedAt {
                Text(CaptionTimestampFormatter.string(sessionStartedAt: sessionStartedAt, offset: segment.startedAt))
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(.white.opacity(0.58))
            }
            if mode != .translationOnly {
                Text(segment.sourceText)
                    .font(.system(size: fontSize, weight: .semibold))
                    .foregroundStyle(segment.state == .provisional ? .white.opacity(0.58) : .white)
                    .fixedSize(horizontal: false, vertical: true)
                Color.clear.frame(height: 1).id(FloatingCaptionTextAnchor.source(segment.id))
            }

            if mode != .sourceOnly, let translation = segment.translatedText {
                Text(translation)
                    .font(.system(size: max(13, fontSize - 3), weight: .medium))
                    .foregroundStyle(.white.opacity(0.82))
                    .fixedSize(horizontal: false, vertical: true)
                Color.clear.frame(height: 1).id(FloatingCaptionTextAnchor.translation(segment.id))
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

enum FloatingCaptionTextAnchor: Hashable {
    case source(UUID)
    case translation(UUID)
}

struct FloatingCaptionScrollRequest: Equatable {
    let anchor: FloatingCaptionTextAnchor
    let mode: FloatingCaptionDisplayMode
    let visibleText: [String]
    let fontSize: CGFloat
    let viewportSize: CGSize

    init?(segments: [CaptionSegment], mode: FloatingCaptionDisplayMode, fontSize: CGFloat, viewportSize: CGSize) {
        guard let latest = segments.last else { return nil }
        self.mode = mode
        self.fontSize = fontSize
        self.viewportSize = viewportSize
        switch mode {
        case .sourceOnly:
            anchor = .source(latest.id)
            visibleText = segments.map(\.sourceText)
        case .bilingual:
            anchor = .source(latest.id)
            visibleText = segments.flatMap { [$0.sourceText, $0.translatedText ?? ""] }
        case .translationOnly:
            anchor = .translation(latest.id)
            visibleText = segments.map { $0.translatedText ?? "" }
        }
    }
}
