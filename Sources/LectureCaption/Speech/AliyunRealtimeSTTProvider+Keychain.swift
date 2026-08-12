import Foundation

extension AliyunRealtimeSTTProvider {
    static func keychainBacked(settings: AliyunRealtimeSettings) -> AliyunRealtimeSTTProvider {
        AliyunRealtimeSTTProvider(settings: settings, apiKeyLoader: {
            try LocalCredentialsStore.default.loadDashScopeAPIKey()
        })
    }
}
