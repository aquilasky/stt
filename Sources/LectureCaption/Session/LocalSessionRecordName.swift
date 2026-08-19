import Foundation

enum LocalSessionRecordName {
    static func string(startedAt: Date, timeZone: TimeZone = .current) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = timeZone
        formatter.dateFormat = "EEE_dd_MMM_yy_HH:mm"
        return formatter.string(from: startedAt)
    }
}
