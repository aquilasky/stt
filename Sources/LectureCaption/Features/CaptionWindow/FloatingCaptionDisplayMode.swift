import Foundation

enum FloatingCaptionDisplayMode: String, CaseIterable, Identifiable, Sendable {
    case bilingual
    case sourceOnly
    case translationOnly

    var id: Self { self }

    var title: String {
        switch self {
        case .bilingual:
            "双语"
        case .sourceOnly:
            "原文"
        case .translationOnly:
            "译文"
        }
    }

    var symbolName: String {
        switch self {
        case .bilingual:
            "captions.bubble"
        case .sourceOnly:
            "text.quote"
        case .translationOnly:
            "character.book.closed"
        }
    }

    func visibleSegments(from segments: [CaptionSegment], maximumCount: Int = 3) -> [CaptionSegment] {
        let matchingSegments: [CaptionSegment]
        switch self {
        case .bilingual, .sourceOnly:
            matchingSegments = segments
        case .translationOnly:
            matchingSegments = segments.filter { $0.translatedText != nil }
        }

        return Array(matchingSegments.suffix(max(1, maximumCount)))
    }
}
