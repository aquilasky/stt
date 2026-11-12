import SwiftUI

struct SpeechUsageGroup: Identifiable {
    let model: String
    let region: AliyunRealtimeSettings.Region
    let records: [APIUsageRecord]
    var id: String { "\(region.rawValue):\(model)" }
    var seconds: Double { records.reduce(0) { $0 + $1.audioSeconds } }
    var taskCount: Int { Set(records.compactMap(\.taskID)).count }
    var cost: Decimal { records.compactMap(\.estimatedCost).reduce(0, +) }
}

struct APIUsageSummary {
    let records: [APIUsageRecord]
    let speechGroups: [SpeechUsageGroup]
    let translations: [APIUsageRecord]

    init(records: [APIUsageRecord], range: APIUsageTimeRange, now: Date = .now, timeZone: TimeZone = .current) {
        self.records = records.filter { range.contains($0, now: now, timeZone: timeZone) }
        translations = self.records.filter { if case .translation = $0.metrics { return true }; return false }
        let audio = self.records.filter { if case .audio = $0.metrics { return true }; return false }
        let groups = Dictionary(grouping: audio) { record in
            if case let .audio(_, region) = record.metrics { return "\(region.rawValue):\(record.model)" }
            preconditionFailure("Only audio records are grouped here")
        }
        speechGroups = groups.keys.sorted().map { key in
            let values = groups[key]!
            guard case let .audio(_, region) = values[0].metrics else { preconditionFailure() }
            return SpeechUsageGroup(model: values[0].model, region: region, records: values)
        }
    }

    var speechSeconds: Double { speechGroups.reduce(0) { $0 + $1.seconds } }
    var speechTaskCount: Int { Set(records.compactMap(\.taskID)).count }
    var speechCost: Decimal { speechGroups.reduce(0) { $0 + $1.cost } }
    var translationCost: Decimal { translations.compactMap(\.estimatedCost).reduce(0, +) }
    var unpricedCount: Int { records.filter { $0.price == nil }.count }

    func tokens(_ keyPath: KeyPath<DeepSeekTokenUsage, Int>) -> Decimal {
        translations.reduce(0) { result, record in
            guard case let .translation(tokens) = record.metrics else { return result }
            return result + Decimal(tokens[keyPath: keyPath])
        }
    }
}

struct APIUsageView: View {
    @Bindable var appState: AppState
    @State private var range = APIUsageTimeRange.today

    var body: some View {
        let summary = APIUsageSummary(records: appState.apiUsageRecords, range: range)
        Section("API 用量 · 仅保存在本机") {
            Picker("时间范围", selection: $range) {
                ForEach(APIUsageTimeRange.allCases) { option in
                    Text(option.rawValue).tag(option)
                }
            }
            if let error = appState.apiUsageError {
                Text("统计错误：\(error)")
                    .foregroundStyle(.red)
                    .textSelection(.enabled)
                Text("以下只显示已成功保存的记录，原文与译文不受影响。")
                    .font(.caption)
            }
        }
        Section("语音识别") {
            LabeledContent("云端音频", value: String(format: "%.2f 秒", summary.speechSeconds))
            LabeledContent("任务数", value: "\(summary.speechTaskCount)")
            LabeledContent("人民币估算（已知单价小计）", value: money(summary.speechCost, currency: "CNY"))
            ForEach(summary.speechGroups) { group in
                VStack(alignment: .leading, spacing: 4) {
                    Text("\(group.region.displayName) · \(group.model)").font(.caption)
                    Text(String(format: "%.2f 秒 · %d 个任务 · ", group.seconds, group.taskCount)
                         + money(group.cost, currency: "CNY"))
                        .font(.caption).monospacedDigit()
                }
            }
        }
        Section("翻译") {
            LabeledContent("成功请求数", value: "\(summary.translations.count)")
            LabeledContent("输入 Token", value: "\(summary.tokens(\.promptTokens))")
            LabeledContent("缓存命中 / 未命中", value: "\(summary.tokens(\.cacheHitTokens)) / \(summary.tokens(\.cacheMissTokens))")
            LabeledContent("输出 Token", value: "\(summary.tokens(\.completionTokens))")
            LabeledContent("总 Token", value: "\(summary.tokens(\.totalTokens))")
            LabeledContent("美元估算（已知单价小计）", value: money(summary.translationCost, currency: "USD"))
        }
        if !summary.records.isEmpty {
            Section("记录明细") {
                Table(summary.records) {
                    TableColumn("本地日期", value: \.localDay)
                    TableColumn("服务 / 模型") { record in
                        VStack(alignment: .leading) {
                            Text(record.taskID == nil ? "翻译" : "语音")
                            Text(record.model).font(.caption2)
                        }
                    }
                    TableColumn("用量") { record in
                        switch record.metrics {
                        case .audio: Text(String(format: "%.2f 秒", record.audioSeconds))
                        case let .translation(tokens): Text("\(tokens.totalTokens) Token")
                        }
                    }
                    TableColumn("估算") { record in
                        if let cost = record.estimatedCost, let price = record.price {
                            Text(money(cost, currency: price.currency))
                                .help("\(price.model) · \(price.period) · \(price.version)")
                        } else {
                            Text("无法估算").help(record.priceUnavailableReason ?? "无单价")
                        }
                    }
                }
                .frame(height: 240)
            }
        }
        Section("价格快照 · \(UsagePriceSnapshot.verifiedDate)") {
            Text("ASR：北京 0.00033、新加坡 0.00066 CNY/秒。")
            Text("DeepSeek-V4.1-Flash：非高峰缓存命中/未命中/输出为 0.003 / 0.15 / 0.60 USD/百万 Token；高峰为两倍。旧 v4-flash 名称按此价格估算。")
            Text("高峰：工作日 01–04、06–10 UTC；周末及中国节假日非高峰。内置 2026 年日历，未覆盖的年份无法估算。")
            HStack {
                Link("阿里云价格", destination: URL(string: UsagePriceSnapshot.aliyunSource)!)
                Link("DeepSeek 价格", destination: URL(string: UsagePriceSnapshot.deepSeekSource)!)
            }
            if summary.unpricedCount > 0 {
                Text("\(summary.unpricedCount) 条记录无法估算，不包含在费用小计中。")
            }
            Text("最终费用以供应商账单为准。估算不包含免费额度、优惠、税费、供应商舍入及失败/取消请求费用。ASR 每 30 秒或任务结束更新；异常退出可能丢失最近 30 秒用量。旧会话不回填。")
        }
        .font(.caption)
    }

    private func money(_ amount: Decimal, currency: String) -> String {
        "\(currency) \(amount.formatted(.number.precision(.fractionLength(8))))"
    }
}
