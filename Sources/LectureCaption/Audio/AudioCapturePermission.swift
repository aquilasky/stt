@preconcurrency import AVFoundation
import AppKit
import CoreGraphics
import Foundation
import ScreenCaptureKit

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
        systemAudioStatus(
            hasLegacyScreenCaptureAccess: CGPreflightScreenCaptureAccess(),
            hasScreenCaptureKitAccess: false
        )
    }

    static func systemAudioStatus(
        hasLegacyScreenCaptureAccess: Bool,
        hasScreenCaptureKitAccess: Bool
    ) -> CapturePermissionStatus {
        (hasLegacyScreenCaptureAccess || hasScreenCaptureKitAccess)
            ? .authorized
            : .requiresSystemSettings
    }

    static func screenCaptureKitAccessResult(for error: Error) -> SystemAudioAccessResult {
        let error = error as NSError
        if error.domain == SCStreamErrorDomain, error.code == -3_801 {
            return .permissionDenied
        }
        return .unavailable
    }

    static func openMicrophonePrivacySettings() {
        openPrivacySettings(anchor: "Privacy_Microphone")
    }

    static func openSystemAudioPrivacySettings() {
        openPrivacySettings(anchor: "Privacy_ScreenCapture")
    }

    @discardableResult
    static func requestSystemAudioAccess() -> Bool {
        CGRequestScreenCaptureAccess()
    }

    static func diagnosticMessage(for error: Error) -> String {
        let error = error as NSError
        return "ScreenCaptureKit 授权验证失败（\(error.domain)，代码 \(error.code)）：\(error.localizedDescription)"
    }

    private static func openPrivacySettings(anchor: String) {
        guard let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?\(anchor)") else {
            return
        }
        NSWorkspace.shared.open(url)
    }
}

enum SystemAudioAccessResult: Equatable, Sendable {
    case authorized
    case permissionDenied
    case unavailable
}

struct SystemAudioPermissionState: Sendable {
    private(set) var hasVerifiedScreenCaptureKitAccess = false

    mutating func refresh(legacyAccess: Bool) -> CapturePermissionStatus {
        AudioCapturePermission.systemAudioStatus(
            hasLegacyScreenCaptureAccess: legacyAccess,
            hasScreenCaptureKitAccess: hasVerifiedScreenCaptureKitAccess
        )
    }

    mutating func record(
        _ result: SystemAudioAccessResult,
        legacyAccess: Bool
    ) -> CapturePermissionStatus {
        switch result {
        case .authorized:
            hasVerifiedScreenCaptureKitAccess = true
            return .authorized
        case .permissionDenied:
            hasVerifiedScreenCaptureKitAccess = false
            return .requiresSystemSettings
        case .unavailable:
            return refresh(legacyAccess: legacyAccess)
        }
    }
}
