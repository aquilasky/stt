@preconcurrency import AVFoundation
import Foundation

typealias MicrophoneBufferHandler = (AVAudioPCMBuffer, AVAudioTime) -> Void

protocol AudioCaptureService: AnyObject {
    var isRunning: Bool { get }

    func stop()
}

enum AudioCaptureError: LocalizedError {
    case microphonePermissionDenied
    case noInputDevice
    case noShareableDisplay
    case systemAudioTargetUnavailable
    case startCancelled
    case unsupportedSystemAudioFormat

    var errorDescription: String? {
        switch self {
        case .microphonePermissionDenied:
            "未获得麦克风权限。"
        case .noInputDevice:
            "未检测到可用的音频输入设备。"
        case .noShareableDisplay:
            "未检测到可采集系统音频的显示器。"
        case .systemAudioTargetUnavailable:
            "所选应用已退出或无法采集，请重新选择。"
        case .startCancelled:
            "音频采集启动已取消。"
        case .unsupportedSystemAudioFormat:
            "系统音频格式无法转换。"
        }
    }
}

enum MicrophoneAuthorization {
    static func requestAccess() async -> Bool {
        switch AVCaptureDevice.authorizationStatus(for: .audio) {
        case .authorized:
            true
        case .notDetermined:
            await AVCaptureDevice.requestAccess(for: .audio)
        case .denied, .restricted:
            false
        @unknown default:
            false
        }
    }
}
