import Foundation

struct DeepSeekTokenUsage: Codable, Sendable, Equatable {
    let promptTokens: Int
    let cacheHitTokens: Int
    let cacheMissTokens: Int
    let completionTokens: Int
    let totalTokens: Int

    enum CodingKeys: String, CodingKey {
        case promptTokens = "prompt_tokens"
        case cacheHitTokens = "prompt_cache_hit_tokens"
        case cacheMissTokens = "prompt_cache_miss_tokens"
        case completionTokens = "completion_tokens"
        case totalTokens = "total_tokens"
    }

    var isValid: Bool {
        promptTokens >= 0 && cacheHitTokens >= 0 && cacheMissTokens >= 0
            && completionTokens >= 0 && totalTokens >= 0
            && cacheHitTokens <= promptTokens && promptTokens - cacheHitTokens == cacheMissTokens
            && promptTokens <= totalTokens && totalTokens - promptTokens == completionTokens
    }
}

struct TranslationUsage: Sendable {
    let tokens: DeepSeekTokenUsage
    let model: String
    let completedAt: Date
}

struct APIUsageRecord: Codable, Identifiable, Sendable, Equatable {
    enum Metrics: Codable, Sendable, Equatable {
        case audio(bytes: Int64, region: AliyunRealtimeSettings.Region)
        case translation(DeepSeekTokenUsage)
    }

    let id: String
    let taskID: String?
    let sessionID: UUID?
    let occurredAt: Date
    let localDay: String
    let timeZoneID: String
    let model: String
    var metrics: Metrics
    let price: UsagePriceSnapshot?
    let priceUnavailableReason: String?

    var audioSeconds: Double {
        guard case let .audio(bytes, _) = metrics else { return 0 }
        return Double(bytes) / 32_000
    }

    var estimatedCost: Decimal? {
        guard let price else { return nil }
        switch metrics {
        case let .audio(bytes, _):
            return Decimal(bytes) / 32_000 * price.inputRate
        case let .translation(tokens):
            return (Decimal(tokens.cacheHitTokens) * price.cacheHitRate
                + Decimal(tokens.cacheMissTokens) * price.inputRate
                + Decimal(tokens.completionTokens) * price.outputRate) / 1_000_000
        }
    }

    var isValid: Bool {
        guard price?.isValid != false, let timeZone = TimeZone(identifier: timeZoneID),
              localDay == Self.day(for: occurredAt, in: timeZone), !model.isEmpty else { return false }
        switch metrics {
        case let .audio(bytes, _):
            guard let taskID else { return false }
            return bytes >= 0 && bytes.isMultiple(of: 2)
                && id == "asr:\(taskID):\(localDay)" && (price == nil || price?.currency == "CNY")
        case let .translation(tokens):
            return tokens.isValid && taskID == nil && (price == nil || price?.currency == "USD")
        }
    }

    static func day(for date: Date, in timeZone: TimeZone) -> String {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = timeZone
        let parts = calendar.dateComponents([.year, .month, .day], from: date)
        return String(format: "%04d-%02d-%02d", parts.year!, parts.month!, parts.day!)
    }

    static func audio(taskID: String, sessionID: UUID?, model: String,
                      region: AliyunRealtimeSettings.Region, at date: Date,
                      timeZone: TimeZone = .current) -> Self {
        let day = day(for: date, in: timeZone)
        let price = UsagePriceSnapshot.audio(model: model, region: region)
        return Self(id: "asr:\(taskID):\(day)", taskID: taskID, sessionID: sessionID,
                    occurredAt: date, localDay: day, timeZoneID: timeZone.identifier, model: model,
                    metrics: .audio(bytes: 0, region: region), price: price,
                    priceUnavailableReason: price == nil ? "模型没有已核实的音频单价" : nil)
    }

    static func translation(_ usage: TranslationUsage, sessionID: UUID?,
                            timeZone: TimeZone = .current) -> Self {
        let price = UsagePriceSnapshot.translation(model: usage.model, at: usage.completedAt)
        return Self(id: UUID().uuidString, taskID: nil, sessionID: sessionID,
                    occurredAt: usage.completedAt, localDay: day(for: usage.completedAt, in: timeZone),
                    timeZoneID: timeZone.identifier, model: usage.model, metrics: .translation(usage.tokens),
                    price: price, priceUnavailableReason: price == nil ? "模型或节假日日历未覆盖，无法估算" : nil)
    }
}

// Used only within the Provider actor. Retained across an in-flight send so a
// successful send returning after reset can publish one final cumulative snapshot.
final class AudioUsageAccumulator {
    private let taskID: String
    private let sessionID: UUID?
    private let settings: AliyunRealtimeSettings
    private var buckets: [String: APIUsageRecord] = [:]
    var isFinished = false

    init(taskID: String, sessionID: UUID?, settings: AliyunRealtimeSettings) {
        self.taskID = taskID
        self.sessionID = sessionID
        self.settings = settings
    }

    func add(bytes: Int, at date: Date, timeZone: TimeZone = .current) {
        let day = APIUsageRecord.day(for: date, in: timeZone)
        var record = buckets[day] ?? .audio(taskID: taskID, sessionID: sessionID,
            model: settings.model, region: settings.region, at: date, timeZone: timeZone)
        if case let .audio(total, region) = record.metrics {
            record.metrics = .audio(bytes: total + Int64(bytes), region: region)
        }
        buckets[day] = record
    }

    var snapshots: [APIUsageRecord] { Array(buckets.values) }
}

enum APIUsageTimeRange: String, CaseIterable, Identifiable {
    case today = "今天"
    case week = "最近 7 天"
    case month = "最近 30 天"
    case all = "全部"
    var id: Self { self }

    func contains(_ record: APIUsageRecord, now: Date, timeZone: TimeZone = .current) -> Bool {
        guard self != .all else { return true }
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = timeZone
        let days = self == .today ? 0 : (self == .week ? 6 : 29)
        let beginning = calendar.date(byAdding: .day, value: -days, to: calendar.startOfDay(for: now))!
        return record.localDay >= APIUsageRecord.day(for: beginning, in: timeZone)
            && record.localDay <= APIUsageRecord.day(for: now, in: timeZone)
    }
}
