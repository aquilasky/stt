import AppKit
import SwiftUI

struct CaptionPreviewView: View {
    let segments: [CaptionSegment]
    let fontSize: CGFloat
    let sessionStartedAt: Date?
    let showsTimestamps: Bool
    var followsLiveCaptions = true
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var followState = CaptionFollowState()

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
                        ZStack(alignment: .bottom) {
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
                                .background {
                                    if followsLiveCaptions {
                                        CaptionLiveScrollObserver { isNearBottom in
                                            followState.userScrolled(at: .now, isNearBottom: isNearBottom)
                                        }
                                    }
                                }
                                // Keeps the active line near the visual center even at the start or end of a session.
                                .padding(.top, max(72, geometry.size.height * 0.5))
                                .padding(.bottom, max(72, geometry.size.height * 0.5))
                                .padding(.horizontal, 48)
                            }
                            .padding(24)

                            if followsLiveCaptions && !followState.isFollowing {
                                Button {
                                    followState.resume()
                                    scrollToFocusedSegment(using: scrollProxy, animated: true)
                                } label: {
                                    Image(systemName: "arrow.down")
                                        .font(.system(size: 18, weight: .medium))
                                        .foregroundStyle(.primary)
                                        .frame(width: 44, height: 44)
                                        .background(.regularMaterial, in: Circle())
                                        .overlay(Circle().strokeBorder(.primary.opacity(0.09)))
                                        .shadow(color: .black.opacity(0.14), radius: 8, y: 3)
                                }
                                .buttonStyle(.plain)
                                .accessibilityLabel("回到最新")
                                .help("回到最新")
                                .padding(.bottom, 32)
                            }
                        }
                        .onAppear {
                            scrollToFocusedSegment(using: scrollProxy, animated: false)
                        }
                        .onChange(of: focusAnchor(for: geometry.size)) {
                            if followState.isFollowing {
                                scrollToFocusedSegment(using: scrollProxy, animated: true)
                            }
                        }
                        .onChange(of: sessionStartedAt) {
                            followState.resume()
                            scrollToFocusedSegment(using: scrollProxy, animated: false)
                        }
                        .task(id: followState.browsingUntil) {
                            guard followState.browsingUntil != nil else { return }
                            do {
                                try await Task.sleep(for: .seconds(CaptionFollowState.inactivitySeconds))
                            } catch {
                                return
                            }
                            if followState.resumeIfDue(at: .now) {
                                scrollToFocusedSegment(using: scrollProxy, animated: true)
                            }
                        }
                    }
                }
            }
        }
        .background(.regularMaterial)
        .onChange(of: segments.isEmpty) { _, isEmpty in
            if isEmpty { followState.resume() }
        }
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

struct CaptionFollowState: Equatable {
    static let inactivitySeconds: TimeInterval = 3
    private(set) var browsingUntil: Date?

    var isFollowing: Bool { browsingUntil == nil }

    mutating func userScrolled(at time: Date, isNearBottom: Bool) {
        if isNearBottom {
            resume()
        } else {
            browsingUntil = time.addingTimeInterval(Self.inactivitySeconds)
        }
    }

    mutating func resume() {
        browsingUntil = nil
    }

    mutating func resumeIfDue(at time: Date) -> Bool {
        guard let browsingUntil, time >= browsingUntil else { return false }
        resume()
        return true
    }
}

private struct CaptionLiveScrollObserver: NSViewRepresentable {
    let onScroll: (Bool) -> Void

    func makeNSView(context: Context) -> CaptionLiveScrollView {
        let view = CaptionLiveScrollView()
        view.onScroll = onScroll
        return view
    }

    func updateNSView(_ view: CaptionLiveScrollView, context: Context) {
        view.onScroll = onScroll
        view.updateObservedScrollView()
    }
}

final class CaptionLiveScrollView: NSView {
    var onScroll: ((Bool) -> Void)?
    private weak var observedScrollView: NSScrollView?

    override func hitTest(_ point: NSPoint) -> NSView? { nil }

    override func viewDidMoveToSuperview() {
        super.viewDidMoveToSuperview()
        updateObservedScrollView()
    }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        updateObservedScrollView()
    }

    func updateObservedScrollView() {
        let scrollView = enclosingScrollView
        guard scrollView !== observedScrollView else { return }
        NotificationCenter.default.removeObserver(self, name: NSScrollView.didLiveScrollNotification, object: observedScrollView)
        observedScrollView = scrollView
        if let scrollView {
            NotificationCenter.default.addObserver(self, selector: #selector(didLiveScroll), name: NSScrollView.didLiveScrollNotification, object: scrollView)
        }
    }

    @objc private func didLiveScroll(_ notification: Notification) {
        guard let observedScrollView else { return }
        onScroll?(CaptionScrollPosition.isNearBottom(in: observedScrollView))
    }

    deinit {
        NotificationCenter.default.removeObserver(self)
    }
}

@MainActor enum CaptionScrollPosition {
    static let bottomTolerance: CGFloat = 40

    static func isNearBottom(in scrollView: NSScrollView) -> Bool {
        guard let documentView = scrollView.documentView else { return true }
        let visible = scrollView.documentVisibleRect
        let document = documentView.bounds
        let distance = documentView.isFlipped
            ? document.maxY - visible.maxY
            : visible.minY - document.minY
        return distance <= bottomTolerance
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
