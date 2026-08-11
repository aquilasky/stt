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

enum SystemAudioCaptureScope: Equatable, Sendable {
    case allSystemAudio
    case application(processID: Int32)
}

struct SystemAudioTarget: Identifiable, Hashable, Sendable {
    static let allSystemAudio = SystemAudioTarget(
        processID: 0,
        applicationName: "所有系统音频",
        bundleIdentifier: "com.aquilasky.LectureCaption.all-system-audio"
    )

    let processID: Int32
    let applicationName: String
    let bundleIdentifier: String

    var id: Int32 { processID }

    var capturesAllSystemAudio: Bool {
        self == Self.allSystemAudio
    }

    var captureScope: SystemAudioCaptureScope {
        capturesAllSystemAudio ? .allSystemAudio : .application(processID: processID)
    }
}

struct LocalActivityConfiguration: Equatable, Sendable {
    var analysisWindow: TimeInterval = 0.02
    var activationHold: TimeInterval = 0.2
    var releaseHold: TimeInterval = 0.6
    var preRoll: TimeInterval = 0.8
    var activationAboveNoiseFloor: Float = 12
    var releaseAboveNoiseFloor: Float = 6
    var stableNoiseHold: TimeInterval = 2
    var stableNoiseToleranceDB: Float = 2
    var maximumAdaptiveNoiseDBFS: Float = -35
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
