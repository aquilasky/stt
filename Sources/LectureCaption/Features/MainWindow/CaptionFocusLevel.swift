import SwiftUI

enum CaptionFocusLevel: Equatable {
    case focused
    case standard
    case provisional

    static func forSegment(at index: Int, focusedIndex: Int?, isProvisional: Bool) -> CaptionFocusLevel {
        if index == focusedIndex {
            return .focused
        }
        if isProvisional {
            return .provisional
        }
        return .standard
    }

    static func orderedSegments(_ segments: [CaptionSegment]) -> [CaptionSegment] {
        let confirmedSegments = segments.filter { $0.state != .provisional }
        let latestProvisionalSegment = segments.last { $0.state == .provisional }
        return confirmedSegments + (latestProvisionalSegment.map { [$0] } ?? [])
    }

    var sourceScale: CGFloat {
        switch self {
        case .focused: 1.12
        case .standard, .provisional: 1
        }
    }

    var opacity: Double {
        switch self {
        case .focused, .standard: 1
        case .provisional: 0.68
        }
    }

    var sourceWeight: Font.Weight {
        switch self {
        case .focused: .semibold
        case .standard, .provisional: .medium
        }
    }
}

struct CaptionFocusAnchor: Equatable {
    let scrollTargetSegmentID: UUID?
    let focusedSegmentID: UUID?
    let focusedSourceText: String?
    let focusedTranslatedText: String?
    let focusedState: CaptionState?
    let provisionalSegmentID: UUID?
    let provisionalSourceText: String?
    let fontSize: CGFloat
    let viewportSize: CGSize

    init(segments: [CaptionSegment], fontSize: CGFloat, viewportSize: CGSize) {
        let focusedSegment = segments.last { $0.state != .provisional }
        let provisionalSegment = segments.last { $0.state == .provisional }
        scrollTargetSegmentID = focusedSegment?.id ?? provisionalSegment?.id
        focusedSegmentID = focusedSegment?.id
        focusedSourceText = focusedSegment?.sourceText
        focusedTranslatedText = focusedSegment?.translatedText
        focusedState = focusedSegment?.state
        provisionalSegmentID = provisionalSegment?.id
        provisionalSourceText = focusedSegment == nil ? provisionalSegment?.sourceText : nil
        self.fontSize = fontSize
        self.viewportSize = viewportSize
    }
}
