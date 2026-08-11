@preconcurrency import AVFoundation
import AppKit
import CoreGraphics
import Foundation

enum CapturePermissionStatus: Equatable, Sendable {
    case authorized
    case notDetermined
    case denied
    case restricted
    case requiresSystemSettings

    var title: String {
        switch self {
        case .authorized:
            "已授权"
        case .notDetermined:
            "未请求"
        case .denied:
            "已拒绝"
        case .restricted:
            "受系统限制"
        case .requiresSystemSettings:
            "需要在系统设置授权"
        }
    }

    var symbolName: String {
        switch self {
        case .authorized:
            "checkmark.circle.fill"
        case .notDetermined, .requiresSystemSettings:
            "exclamationmark.circle"
        case .denied, .restricted:
            "xmark.circle.fill"
        }
    }

    var isAuthorized: Bool {
        self == .authorized
    }
}

enum AudioCapturePermission {
    static func microphoneStatus() -> CapturePermissionStatus {
        microphoneStatus(for: AVCaptureDevice.authorizationStatus(for: .audio))
    }

    static func microphoneStatus(for status: AVAuthorizationStatus) -> CapturePermissionStatus {
        switch status {
        case .authorized:
            .authorized
        case .notDetermined:
            .notDetermined
        case .denied:
            .denied
        case .restricted:
            .restricted
        @unknown default:
            .restricted
        }
    }

    static func systemAudioStatus() -> CapturePermissionStatus {
        systemAudioStatus(hasAccess: CGPreflightScreenCaptureAccess())
    }

    static func systemAudioStatus(hasAccess: Bool) -> CapturePermissionStatus {
        hasAccess ? .authorized : .requiresSystemSettings
    }

    static func openMicrophonePrivacySettings() {
        openPrivacySettings(anchor: "Privacy_Microphone")
    }

    static func openSystemAudioPrivacySettings() {
        openPrivacySettings(anchor: "Privacy_ScreenCapture")
    }

    private static func openPrivacySettings(anchor: String) {
        guard let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?\(anchor)") else {
            return
        }
        NSWorkspace.shared.open(url)
    }
}
