import Foundation

// Full selected rates are persisted with each record. Updating this table must
// never reprice historical records.
struct UsagePriceSnapshot: Codable, Sendable, Equatable {
    let version: String
    let effectiveDate: String
    let model: String
    let currency: String
    let source: String
    let period: String
    let inputRate: Decimal
    let cacheHitRate: Decimal
    let outputRate: Decimal

    var isValid: Bool {
        !version.isEmpty && !model.isEmpty && ["CNY", "USD"].contains(currency)
            && inputRate >= 0 && cacheHitRate >= 0 && outputRate >= 0
    }

    static let verifiedDate = "2026-10-05"
    static let aliyunSource = "https://help.aliyun.com/zh/model-studio/model-pricing"
    static let deepSeekSource = "https://api-docs.deepseek.com/quick_start/pricing/"

    static func audio(model: String, region: AliyunRealtimeSettings.Region) -> Self? {
        guard model == "qwen-audio-3.0-asr-flash-streaming" else { return nil }
        return Self(version: "aliyun-\(verifiedDate)", effectiveDate: verifiedDate, model: model,
                    currency: "CNY", source: aliyunSource, period: "每音频秒",
                    inputRate: region == .beijing ? Decimal(33) / 100_000 : Decimal(66) / 100_000,
                    cacheHitRate: 0, outputRate: 0)
    }

    static func translation(model: String, at date: Date) -> Self? {
        guard ["deepseek-v4-flash", "deepseek-flash"].contains(model),
              let peak = isDeepSeekPeak(at: date) else { return nil }
        let multiplier: Decimal = peak ? 2 : 1
        return Self(version: "deepseek-flash-\(verifiedDate)", effectiveDate: verifiedDate,
                    model: "DeepSeek-V4.1-Flash", currency: "USD", source: deepSeekSource,
                    period: peak ? "高峰 / 每百万 Token" : "非高峰 / 每百万 Token",
                    inputRate: Decimal(15) / 100 * multiplier,
                    cacheHitRate: Decimal(3) / 1000 * multiplier,
                    outputRate: Decimal(6) / 10 * multiplier)
    }

    static func isDeepSeekPeak(at date: Date) -> Bool? {
        var utc = Calendar(identifier: .gregorian)
        utc.timeZone = TimeZone(secondsFromGMT: 0)!
        var china = utc
        china.timeZone = TimeZone(identifier: "Asia/Shanghai")!
        guard china.component(.year, from: date) == 2026 else { return nil }
        let weekday = utc.component(.weekday, from: date)
        if weekday == 1 || weekday == 7 { return false }
        let chinaDay = APIUsageRecord.day(for: date, in: china.timeZone)
        let holidays: [ClosedRange<String>] = [
            "2026-01-01"..."2026-01-03", "2026-02-15"..."2026-02-23",
            "2026-04-04"..."2026-04-06", "2026-05-01"..."2026-05-05",
            "2026-06-19"..."2026-06-21", "2026-09-25"..."2026-09-27",
            "2026-10-01"..."2026-10-07"
        ]
        if holidays.contains(where: { $0.contains(chinaDay) }) { return false }
        let hour = utc.component(.hour, from: date)
        return (1..<4).contains(hour) || (6..<10).contains(hour)
    }
}
