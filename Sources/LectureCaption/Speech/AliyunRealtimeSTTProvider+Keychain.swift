import Foundation

extension AliyunRealtimeSTTProvider {
    static func keychainBacked(settings: AliyunRealtimeSettings, usageStore: APIUsageStore? = nil,
                              sessionID: UUID? = nil) -> AliyunRealtimeSTTProvider {
        AliyunRealtimeSTTProvider(settings: settings, apiKeyLoader: {
            try LocalCredentialsStore.default.loadDashScopeAPIKey()
        }, usageStore: usageStore, sessionID: sessionID)
    }
}
