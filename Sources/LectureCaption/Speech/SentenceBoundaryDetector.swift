import Foundation

enum SentenceBoundaryDetector {
    static let commitDelay: Duration = .milliseconds(800)

    static func shouldAutoCommit(_ text: String) -> Bool {
        split(atFirstBoundaryIn: text) != nil
    }

    static func split(atFirstBoundaryIn text: String) -> (committed: String, remainder: String)? {
        let normalized = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !normalized.isEmpty else { return nil }

        var boundaryEnd: String.Index?
        var index = normalized.startIndex
        while index < normalized.endIndex {
            let character = normalized[index]
            if isTerminalPunctuation(character), isValidBoundary(at: index, in: normalized) {
                boundaryEnd = normalized.index(after: index)
                break
            }
            index = normalized.index(after: index)
        }

        guard let boundaryEnd else { return nil }
        let committed = String(normalized[..<boundaryEnd]).trimmingCharacters(in: .whitespacesAndNewlines)
        let remainder = String(normalized[boundaryEnd...]).trimmingCharacters(in: .whitespacesAndNewlines)
        guard !committed.isEmpty else { return nil }
        return (committed, remainder)
    }

    private static func isTerminalPunctuation(_ character: Character) -> Bool {
        "。！？!?".contains(character) || character == "."
    }

    private static func isValidBoundary(at index: String.Index, in text: String) -> Bool {
        guard text[index] == "." else { return true }

        let before = index > text.startIndex ? text[text.index(before: index)] : nil
        let afterIndex = text.index(after: index)
        let after = afterIndex < text.endIndex ? text[afterIndex] : nil
        if before?.isNumber == true, after?.isNumber == true {
            return false
        }

        // A numeric token ending in a period is ambiguous ("3."). Keep it
        // provisional until the provider supplies a clearer sentence boundary.
        if after == nil || after?.isWhitespace == true {
            let body = text[..<index]
            let token = body.split(whereSeparator: { $0.isWhitespace || $0.isNewline }).last
            if token?.allSatisfy(\.isNumber) == true {
                return false
            }
        }
        return true
    }
}
