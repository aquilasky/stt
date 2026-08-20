import Foundation

struct LectureSession: Identifiable, Codable, Sendable {
    let id: UUID
    let startedAt: Date
    var endedAt: Date?
    var context: LectureContext
    var provider: SpeechProviderKind

    init(
        id: UUID = UUID(),
        startedAt: Date = .now,
        endedAt: Date? = nil,
        context: LectureContext,
        provider: SpeechProviderKind
    ) {
        self.id = id
        self.startedAt = startedAt
        self.endedAt = endedAt
        self.context = context
        self.provider = provider
    }
}

struct LectureContext: Codable, Sendable {
    var courseName: String
    var topic: String
    var sourceLanguage: RecognitionLanguage
    var targetLanguage: TargetLanguage
    var glossary: [GlossaryEntry]
}

struct GlossaryEntry: Identifiable, Codable, Sendable {
    let id: UUID
    var source: String
    var target: String

    init(id: UUID = UUID(), source: String, target: String) {
        self.id = id
        self.source = source
        self.target = target
    }
}

struct CaptionSegment: Identifiable, Codable, Sendable {
    let id: UUID
    let sequence: Int
    var sourceText: String
    var translatedText: String?
    var startedAt: TimeInterval
    var endedAt: TimeInterval?
    var state: CaptionState

    init(
        id: UUID = UUID(),
        sequence: Int,
        sourceText: String,
        translatedText: String? = nil,
        startedAt: TimeInterval,
        endedAt: TimeInterval? = nil,
        state: CaptionState
    ) {
        self.id = id
        self.sequence = sequence
        self.sourceText = sourceText
        self.translatedText = translatedText
        self.startedAt = startedAt
        self.endedAt = endedAt
        self.state = state
    }
}

enum CaptionState: String, Codable, Sendable {
    case provisional
    case committed
    case translating
    case completed
    case translationFailed
}
