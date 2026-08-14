import Foundation

enum SentenceBoundaryDetector {
    static let commitDelay: Duration = .milliseconds(800)

    static func shouldAutoCommit(_ text: String) -> Bool {
        let normalized = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let last = normalized.last else { return false }

        switch last {
        case "。", "！", "？", "!", "?":
            return true
        case ".":
            // A bare numeric token such as "3." is more likely an unfinished decimal.
            let body = normalized.dropLast()
            let token = body.split(whereSeparator: { $0.isWhitespace || $0.isNewline }).last.map(String.init)
            return token?.allSatisfy(\.isNumber) != true
        default:
            return false
        }
    }
}
