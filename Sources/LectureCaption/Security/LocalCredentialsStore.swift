import Foundation

enum LocalCredentialsStoreError: LocalizedError {
    case missingApplicationSupportDirectory
    case invalidFile

    var errorDescription: String? {
        switch self {
        case .missingApplicationSupportDirectory:
            "无法定位本机应用配置目录。"
        case .invalidFile:
            "本机 API 配置文件格式无效。"
        }
    }
}

struct LocalCredentialsStore: Sendable {
    static let `default` = LocalCredentialsStore()

    private let fileURL: URL

    init(fileURL: URL? = nil) {
        if let fileURL {
            self.fileURL = fileURL
            return
        }
        let directory = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? URL(fileURLWithPath: NSTemporaryDirectory(), isDirectory: true)
        self.fileURL = directory
            .appendingPathComponent("LectureCaption", isDirectory: true)
            .appendingPathComponent("LocalCredentials.json", isDirectory: false)
    }

    func loadDashScopeAPIKey() throws -> String? {
        guard FileManager.default.fileExists(atPath: fileURL.path) else { return nil }
        let data = try Data(contentsOf: fileURL)
        let credentials = try JSONDecoder().decode(Credentials.self, from: data)
        return credentials.dashScopeAPIKey?.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    func saveDashScopeAPIKey(_ apiKey: String) throws {
        let directory = fileURL.deletingLastPathComponent()
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let credentials = Credentials(dashScopeAPIKey: apiKey)
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        let data = try encoder.encode(credentials)
        try data.write(to: fileURL, options: .atomic)
    }
}

private struct Credentials: Codable {
    let dashScopeAPIKey: String?

    enum CodingKeys: String, CodingKey {
        case dashScopeAPIKey = "dashscope_api_key"
    }
}
