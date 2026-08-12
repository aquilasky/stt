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
    case startCancelled

    var errorDescription: String? {
        switch self {
        case .microphonePermissionDenied:
            "未获得麦克风权限。"
        case .noInputDevice:
            "未检测到可用的音频输入设备。"
        case .startCancelled:
            "音频采集启动已取消。"
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
