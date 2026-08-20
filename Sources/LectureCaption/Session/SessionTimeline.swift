import Foundation

struct SessionTimeline: Sendable {
    private let audioSessionStartedAt: TimeInterval
    private var providerTaskOffset: TimeInterval?
    private var latestMappedTime: TimeInterval = 0

    init(audioSessionStartedAt: TimeInterval, initialMappedTime: TimeInterval = 0) {
        self.audioSessionStartedAt = audioSessionStartedAt
        latestMappedTime = initialMappedTime
    }

    mutating func beginProviderTask(audioStartedAt: TimeInterval) {
        let audioOffset = max(0, audioStartedAt - audioSessionStartedAt)
        providerTaskOffset = max(audioOffset, latestMappedTime)
    }

    mutating func map(_ event: TranscriptEvent) -> TranscriptEvent? {
        guard let providerTaskOffset else { return nil }

        switch event {
        case let .partial(providerSentenceID, text, startedAt):
            let sessionStartedAt = providerTaskOffset + startedAt
            latestMappedTime = max(latestMappedTime, sessionStartedAt)
            return .partial(
                providerSentenceID: providerSentenceID,
                text: text,
                startedAt: sessionStartedAt
            )
        case let .final(providerSentenceID, text, startedAt, endedAt):
            let sessionStartedAt = providerTaskOffset + startedAt
            let sessionEndedAt = max(sessionStartedAt, providerTaskOffset + endedAt)
            latestMappedTime = max(latestMappedTime, sessionEndedAt)
            return .final(
                providerSentenceID: providerSentenceID,
                text: text,
                startedAt: sessionStartedAt,
                endedAt: sessionEndedAt
            )
        default:
            return event
        }
    }
}

enum CaptionTimestampFormatter {
    static func string(sessionStartedAt: Date, offset: TimeInterval) -> String {
        formatter.string(from: sessionStartedAt.addingTimeInterval(offset))
    }

    private static let formatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = .current
        formatter.dateFormat = "HH:mm:ss"
        return formatter
    }()
}
