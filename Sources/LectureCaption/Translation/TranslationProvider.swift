import Foundation

struct TranslationRequest: Sendable {
    let segmentID: UUID
    let sourceText: String
    let recentContext: [String]
    let courseName: String
    let topic: String
    let glossary: [GlossaryEntry]
    let sourceLanguage: RecognitionLanguage
    let targetLanguage: TargetLanguage
}

protocol TranslationProvider: Sendable {
    func translate(_ request: TranslationRequest) async throws -> String
}
