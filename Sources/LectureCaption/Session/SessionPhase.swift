import SwiftUI

enum SessionPhase: Equatable, Sendable {
    case idle
    case monitoringLocal
    case activatingProvider
    case recognizing
    case autoPaused
    case manuallyPaused
    case completed

    var primaryAction: SessionPrimaryAction {
        switch self {
        case .idle, .completed: .start
        case .manuallyPaused: .resume
        case .monitoringLocal, .activatingProvider, .recognizing, .autoPaused: .unavailable
        }
    }

    var title: String {
        switch self {
        case .idle: "准备就绪"
        case .monitoringLocal: "本地监听中"
        case .activatingProvider: "正在连接"
        case .recognizing: "正在识别"
        case .autoPaused: "自动待机"
        case .manuallyPaused: "已暂停"
        case .completed: "会话已结束"
        }
    }

    var symbolName: String {
        switch self {
        case .idle: "circle"
        case .monitoringLocal: "ear"
        case .activatingProvider: "arrow.triangle.2.circlepath"
        case .recognizing: "captions.bubble"
        case .autoPaused: "moon.zzz"
        case .manuallyPaused: "pause.circle"
        case .completed: "checkmark.circle"
        }
    }

    var tint: Color {
        switch self {
        case .recognizing: .green
        case .autoPaused, .manuallyPaused: .orange
        case .completed: .secondary
        default: .primary
        }
    }
}

enum SessionPrimaryAction: Equatable, Sendable {
    case start
    case resume
    case unavailable

    var title: String {
        self == .resume ? "继续" : "开始"
    }

    var symbolName: String {
        self == .resume ? "playpause.fill" : "play.fill"
    }

    var helpText: String {
        switch self {
        case .start: "开始采集"
        case .resume: "继续采集"
        case .unavailable: "会话进行中"
        }
    }

    var isEnabled: Bool { self != .unavailable }

    func canTrigger(startInFlight: Bool) -> Bool {
        isEnabled && !(self == .start && startInFlight)
    }
}
