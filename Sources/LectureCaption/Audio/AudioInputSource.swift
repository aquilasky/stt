import Foundation

enum AudioInputSource: String, CaseIterable, Identifiable, Codable, Sendable {
    case microphone
    case systemAudio

    var id: Self { self }

    var title: String {
        switch self {
        case .microphone: "麦克风"
        case .systemAudio: "系统音频"
        }
    }
}

struct LocalActivityConfiguration: Equatable, Sendable {
    var analysisWindow: TimeInterval = 0.02
    var activationHold: TimeInterval = 0.2
    var releaseHold: TimeInterval = 0.6
    var preRoll: TimeInterval = 0.8
    var activationAboveNoiseFloor: Float = 12
    var releaseAboveNoiseFloor: Float = 6
}

enum AutoPauseOption: String, CaseIterable, Identifiable {
    case disabled
    case seconds15
    case seconds30
    case seconds60

    var id: Self { self }

    var title: String {
        switch self {
        case .disabled: "关闭"
        case .seconds15: "15 秒"
        case .seconds30: "30 秒"
        case .seconds60: "60 秒"
        }
    }

    var interval: TimeInterval? {
        switch self {
        case .disabled: nil
        case .seconds15: 15
        case .seconds30: 30
        case .seconds60: 60
        }
    }

    static func option(for interval: TimeInterval?) -> Self {
        switch interval {
        case nil: .disabled
        case 15: .seconds15
        case 60: .seconds60
        default: .seconds30
        }
    }
}
