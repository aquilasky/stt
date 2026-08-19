import SwiftUI

struct CaptionPreviewView: View {
    let segments: [CaptionSegment]
    let fontSize: CGFloat
    let sessionStartedAt: Date?
    let showsTimestamps: Bool
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
                                let displayedSegments = CaptionFocusLevel.orderedSegments(segments)
                                let focusedIndex = displayedSegments.lastIndex { $0.state != .provisional }
                                ForEach(Array(displayedSegments.enumerated()), id: \.element.id) { index, segment in
                                    CaptionPreviewSegmentView(
                                        segment: segment,
                                        fontSize: fontSize,
                                        sessionStartedAt: sessionStartedAt,
                                        showsTimestamps: showsTimestamps,
                                        focusLevel: CaptionFocusLevel.forSegment(
                                            at: index,
                                            focusedIndex: focusedIndex,
                                            isProvisional: segment.state == .provisional
                                        )
                                    )
                                    .id(segment.id)
                                }
                            }
                            // Keeps the active line near the visual center even at the start or end of a session.
                            .padding(.top, max(72, geometry.size.height * 0.5))
                            .padding(.bottom, max(72, geometry.size.height * 0.5))
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
        guard let scrollTargetSegmentID else { return }

        let scroll = {
            scrollProxy.scrollTo(scrollTargetSegmentID, anchor: .center)
        }

        if animated, let focusAnimation {
            withAnimation(focusAnimation, scroll)
        } else {
            scroll()
        }
    }

    private var scrollTargetSegmentID: UUID? {
        CaptionFocusAnchor(segments: segments, fontSize: fontSize, viewportSize: .zero).scrollTargetSegmentID
    }

    private func focusAnchor(for viewportSize: CGSize) -> CaptionFocusAnchor {
        CaptionFocusAnchor(segments: segments, fontSize: fontSize, viewportSize: viewportSize)
    }
}

private struct CaptionPreviewSegmentView: View {
    let segment: CaptionSegment
    let fontSize: CGFloat
    let sessionStartedAt: Date?
    let showsTimestamps: Bool
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
            if showsTimestamps, let sessionStartedAt {
                Text(CaptionTimestampFormatter.string(sessionStartedAt: sessionStartedAt, offset: segment.startedAt))
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(.tertiary)
            }
            if segment.state == .provisional {
                ProvisionalCaptionText(
                    sourceText: segment.sourceText,
                    font: .system(size: fontSize, weight: focusLevel.sourceWeight)
                )
            } else {
                Text(segment.sourceText)
                    .font(.system(size: fontSize * focusLevel.sourceScale, weight: focusLevel.sourceWeight))
                    .foregroundStyle(.primary)
            }

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
        .scaleEffect(focusLevel == .focused ? 1 : 1)
        .animation(focusAnimation, value: focusLevel)
        .animation(contentAnimation, value: segment.translatedText)
    }
}

private struct ProvisionalCaptionText: View {
    let sourceText: String
    let font: Font
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private var updateAnimation: Animation? {
        reduceMotion ? nil : .easeOut(duration: 0.2)
    }

    var body: some View {
        Text(sourceText)
            .font(font)
            .foregroundStyle(.secondary)
            .contentTransition(.interpolate)
            .animation(updateAnimation, value: sourceText)
    }
}
