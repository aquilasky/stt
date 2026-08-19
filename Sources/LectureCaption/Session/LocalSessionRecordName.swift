import Foundation

enum LocalSessionRecordName {
    static func string(startedAt: Date, calendar: Calendar = .current) -> String {
        let components = calendar.dateComponents(
            [.weekday, .day, .month, .year, .hour, .minute],
            from: startedAt
        )
        let weekday = weekdays[(components.weekday ?? 1) - 1]
        let day = components.day ?? 0
        let month = components.month ?? 0
        let year = (components.year ?? 0) % 100
        let minute = components.minute ?? 0
        let hour = components.hour ?? 0

        return String(
            format: "%@-%02d-%02d-%02d-%02d-%02d",
            weekday,
            day,
            month,
            year,
            minute,
            hour
        )
    }

    private static let weekdays = ["星期日", "星期一", "星期二", "星期三", "星期四", "星期五", "星期六"]
}
