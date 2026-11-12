import Foundation

struct TranslationRequest: Sendable {
    let segmentID: UUID
    let sourceText: String
    let recentContext: [TranslationContextSegment]
    let courseName: String
    let topic: String
    let glossary: [GlossaryEntry]
    let sourceLanguage: RecognitionLanguage
    let targetLanguage: TargetLanguage
}

struct TranslationContextSegment: Sendable {
    let sourceText: String
    let translatedText: String?
}

protocol TranslationProvider: Sendable {
    func translate(_ request: TranslationRequest) async throws -> TranslationResult
}

struct TranslationResult: Sendable {
    let text: String
    var usage: TranslationUsage? = nil
    var usageError: String? = nil
}
