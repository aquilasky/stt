import Foundation

enum LocalSessionRecordName {
    static func string(for record: SavedLectureSession, timeZone: TimeZone = .current) -> String {
        let name = string(startedAt: record.startedAt, timeZone: timeZone)
        guard let mergedIntoStartedAt = record.mergedIntoStartedAt else { return name }
        return "\(name) · 已合并到 \(string(startedAt: mergedIntoStartedAt, timeZone: timeZone))"
    }

    static func string(startedAt: Date, timeZone: TimeZone = .current) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = timeZone
        formatter.dateFormat = "EEE_dd_MMM_yy_HH:mm"
        return formatter.string(from: startedAt)
    }
}
