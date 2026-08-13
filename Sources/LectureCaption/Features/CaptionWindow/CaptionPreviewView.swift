import SwiftUI

struct CaptionPreviewView: View {
    let segments: [CaptionSegment]
    let fontSize: CGFloat
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private var focusAnimation: Animation? {
        reduceMotion ? nil : .spring(response: 0.42, dampingFraction: 0.86)
    }

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
                GeometryReader { geometry in
                    ScrollViewReader { scrollProxy in
                        ScrollView {
                            LazyVStack(spacing: 20) {
                                ForEach(Array(segments.enumerated()), id: \.element.id) { index, segment in
                                    CaptionPreviewSegmentView(
                                        segment: segment,
                                        fontSize: fontSize,
                                        focusLevel: CaptionFocusLevel.forSegment(
                                            at: index,
                                            focusedIndex: segments.indices.last
                                        )
                                    )
                                    .id(segment.id)
                                }
                            }
                            // Keeps the active line near the visual center even at the start or end of a session.
                            .padding(.top, max(40, geometry.size.height * 0.38))
                            .padding(.bottom, max(72, geometry.size.height * 0.44))
                            .padding(.horizontal, 48)
                        }
                        .padding(24)
                        .onAppear {
                            scrollToFocusedSegment(using: scrollProxy, animated: false)
                        }
                        .onChange(of: focusAnchor(for: geometry.size)) {
                            scrollToFocusedSegment(using: scrollProxy, animated: true)
                        }
                    }
                }
            }
        }
        .background(.regularMaterial)
    }

    private func scrollToFocusedSegment(using scrollProxy: ScrollViewProxy, animated: Bool) {
        guard let focusedSegmentID else { return }

        let scroll = {
            scrollProxy.scrollTo(focusedSegmentID, anchor: .center)
        }

        if animated, let focusAnimation {
            withAnimation(focusAnimation, scroll)
        } else {
            scroll()
        }
    }

    private var focusedSegmentID: UUID? {
        segments.last?.id
    }

    private func focusAnchor(for viewportSize: CGSize) -> CaptionFocusAnchor {
        CaptionFocusAnchor(segments: segments, fontSize: fontSize, viewportSize: viewportSize)
    }
}

private struct CaptionPreviewSegmentView: View {
    let segment: CaptionSegment
    let fontSize: CGFloat
    let focusLevel: CaptionFocusLevel
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private var focusAnimation: Animation? {
        reduceMotion ? nil : .spring(response: 0.42, dampingFraction: 0.86)
    }

    private var contentAnimation: Animation? {
        reduceMotion ? nil : .easeInOut(duration: 0.16)
    }

    var body: some View {
        VStack(spacing: 8) {
            Text(segment.sourceText)
                .font(.system(size: fontSize * focusLevel.sourceScale, weight: focusLevel.sourceWeight))
                .foregroundStyle(segment.state == .provisional ? .secondary : .primary)
                .contentTransition(.opacity)

            if let translation = segment.translatedText {
                Text(translation)
                    .font(.system(size: max(13, fontSize - 1), weight: .medium))
                    .foregroundStyle(.secondary)
                    .contentTransition(.opacity)
            }
        }
        .multilineTextAlignment(.center)
        .frame(maxWidth: 780)
        .frame(maxWidth: .infinity)
        .textSelection(.enabled)
        .padding(.vertical, 6)
        .opacity(focusLevel.opacity)
        .scaleEffect(focusLevel == .focused ? 1 : 0.98)
        .animation(focusAnimation, value: focusLevel)
        .animation(contentAnimation, value: segment.sourceText)
        .animation(contentAnimation, value: segment.translatedText)
    }
}
