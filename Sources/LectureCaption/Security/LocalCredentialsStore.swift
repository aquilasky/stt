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
        self.fileURL = ApplicationStorage.applicationSupportDirectory()
            .appendingPathComponent("LocalCredentials.json", isDirectory: false)
    }

    func loadDashScopeAPIKey() throws -> String? {
        try loadCredentials().dashScopeAPIKey?.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    func saveDashScopeAPIKey(_ apiKey: String) throws {
        var credentials = try loadCredentials()
        credentials.dashScopeAPIKey = apiKey
        try save(credentials)
    }

    func loadDeepSeekAPIKey() throws -> String? {
        try loadCredentials().deepSeekAPIKey?.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    func saveDeepSeekAPIKey(_ apiKey: String) throws {
        var credentials = try loadCredentials()
        credentials.deepSeekAPIKey = apiKey
        try save(credentials)
    }

    private func loadCredentials() throws -> Credentials {
        guard FileManager.default.fileExists(atPath: fileURL.path) else { return Credentials() }
        let data = try Data(contentsOf: fileURL)
        return try JSONDecoder().decode(Credentials.self, from: data)
    }

    private func save(_ credentials: Credentials) throws {
        let directory = fileURL.deletingLastPathComponent()
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        let data = try encoder.encode(credentials)
        try data.write(to: fileURL, options: .atomic)
    }
}

private struct Credentials: Codable {
    var dashScopeAPIKey: String?
    var deepSeekAPIKey: String?

    init(dashScopeAPIKey: String? = nil, deepSeekAPIKey: String? = nil) {
        self.dashScopeAPIKey = dashScopeAPIKey
        self.deepSeekAPIKey = deepSeekAPIKey
    }

    enum CodingKeys: String, CodingKey {
        case dashScopeAPIKey = "dashscope_api_key"
        case deepSeekAPIKey = "deepseek_api_key"
    }
}
