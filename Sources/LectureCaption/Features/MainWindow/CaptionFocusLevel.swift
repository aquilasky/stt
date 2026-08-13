import SwiftUI

enum CaptionFocusLevel: Equatable {
    case focused
    case nearby
    case background

    static func forSegment(at index: Int, focusedIndex: Int?) -> CaptionFocusLevel {
        guard let focusedIndex else { return .background }

        return switch abs(index - focusedIndex) {
        case 0:
            .focused
        case 1:
            .nearby
        default:
            .background
        }
    }

    var sourceScale: CGFloat {
        switch self {
        case .focused: 1.12
        case .nearby: 0.94
        case .background: 0.88
        }
    }

    var opacity: Double {
        switch self {
        case .focused: 1
        case .nearby: 0.58
        case .background: 0.32
        }
    }

    var sourceWeight: Font.Weight {
        switch self {
        case .focused: .semibold
        case .nearby, .background: .medium
        }
    }
}

struct CaptionFocusAnchor: Equatable {
    let segmentID: UUID?
    let sourceText: String?
    let translatedText: String?
    let state: CaptionState?
    let fontSize: CGFloat
    let viewportSize: CGSize

    init(segments: [CaptionSegment], fontSize: CGFloat, viewportSize: CGSize) {
        let focusedSegment = segments.last
        segmentID = focusedSegment?.id
        sourceText = focusedSegment?.sourceText
        translatedText = focusedSegment?.translatedText
        state = focusedSegment?.state
        self.fontSize = fontSize
        self.viewportSize = viewportSize
    }
}
