import Foundation

extension AliyunRealtimeSTTProvider {
    static func keychainBacked(settings: AliyunRealtimeSettings) -> AliyunRealtimeSTTProvider {
        AliyunRealtimeSTTProvider(settings: settings, apiKeyLoader: {
            try KeychainStore.load(
                service: "com.aquilasky.LectureCaption",
                account: "dashscope-api-key"
            )
        })
    }
}
