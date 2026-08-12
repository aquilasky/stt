import Foundation

enum DeepSeekTranslationError: LocalizedError, Equatable {
    case missingAPIKey
    case invalidResponse
    case requestFailed(statusCode: Int)

    var errorDescription: String? {
        switch self {
        case .missingAPIKey: "未配置 DeepSeek API Key。"
        case .invalidResponse: "DeepSeek 返回了无法读取的译文。"
        case let .requestFailed(statusCode): "DeepSeek 翻译请求失败（HTTP \(statusCode)）。"
        }
    }
}

protocol DeepSeekHTTPTransport: Sendable {
    func perform(_ request: URLRequest) async throws -> (Data, URLResponse)
}

struct URLSessionDeepSeekHTTPTransport: DeepSeekHTTPTransport {
    func perform(_ request: URLRequest) async throws -> (Data, URLResponse) {
        try await URLSession.shared.data(for: request)
    }
}

struct DeepSeekTranslationSettings: Sendable, Equatable {
    let endpoint: URL
    let model: String
    let timeout: TimeInterval

    init(
        endpoint: URL = URL(string: "https://api.deepseek.com/chat/completions")!,
        model: String = "deepseek-v4-flash",
        timeout: TimeInterval = 8
    ) {
        self.endpoint = endpoint
        self.model = model
        self.timeout = timeout
    }
}

struct DeepSeekTranslationProvider: TranslationProvider {
    private let settings: DeepSeekTranslationSettings
    private let apiKeyLoader: @Sendable () throws -> String?
    private let transport: DeepSeekHTTPTransport

    init(
        settings: DeepSeekTranslationSettings = .init(),
        apiKeyLoader: @escaping @Sendable () throws -> String?,
        transport: DeepSeekHTTPTransport = URLSessionDeepSeekHTTPTransport()
    ) {
        self.settings = settings
        self.apiKeyLoader = apiKeyLoader
        self.transport = transport
    }

    func translate(_ request: TranslationRequest) async throws -> String {
        guard let apiKey = try apiKeyLoader(), !apiKey.isEmpty else {
            throw DeepSeekTranslationError.missingAPIKey
        }
        var urlRequest = URLRequest(url: settings.endpoint)
        urlRequest.httpMethod = "POST"
        urlRequest.timeoutInterval = settings.timeout
        urlRequest.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        urlRequest.setValue("application/json", forHTTPHeaderField: "Content-Type")
        urlRequest.httpBody = try JSONEncoder().encode(DeepSeekRequest(
            model: settings.model,
            messages: [
                ChatMessage(role: "system", content: systemPrompt(target: request.targetLanguage)),
                ChatMessage(role: "user", content: prompt(for: request))
            ]
        ))

        let (data, response) = try await transport.perform(urlRequest)
        guard let httpResponse = response as? HTTPURLResponse else {
            throw DeepSeekTranslationError.invalidResponse
        }
        guard (200...299).contains(httpResponse.statusCode) else {
            throw DeepSeekTranslationError.requestFailed(statusCode: httpResponse.statusCode)
        }
        let translation = try DeepSeekResponse.translation(from: data)
        guard !translation.isEmpty else { throw DeepSeekTranslationError.invalidResponse }
        return translation
    }

    private func systemPrompt(target: TargetLanguage) -> String {
        "你是课堂字幕翻译器。只输出待翻译句子的\(target.title)译文。遵守术语表，不解释，不总结。"
    }

    private func prompt(for request: TranslationRequest) -> String {
        let glossary = request.glossary
            .filter { !$0.source.isEmpty && !$0.target.isEmpty }
            .map { "\($0.source)=\($0.target)" }
            .joined(separator: "；")
        let context = request.recentContext.joined(separator: "\n")
        return "课程：\(request.courseName)\n主题：\(request.topic)\n原文语言：\(request.sourceLanguage.title)\n术语：\(glossary)\n上下文：\(context)\n待翻译：\(request.sourceText)"
    }
}

extension DeepSeekTranslationProvider {
    static func localCredentialsBacked(
        settings: DeepSeekTranslationSettings = .init()
    ) -> DeepSeekTranslationProvider {
        DeepSeekTranslationProvider(settings: settings, apiKeyLoader: {
            try LocalCredentialsStore.default.loadDeepSeekAPIKey()
        })
    }
}

private struct DeepSeekRequest: Encodable {
    let model: String
    let messages: [ChatMessage]
    let stream = false
    let thinking = Thinking(type: "disabled")
}

private struct ChatMessage: Encodable {
    let role: String
    let content: String
}

private struct Thinking: Encodable {
    let type: String
}

private struct DeepSeekResponse: Decodable {
    private let choices: [Choice]

    private struct Choice: Decodable {
        let message: Message
    }

    private struct Message: Decodable {
        let content: String?
    }

    static func translation(from data: Data) throws -> String {
        let response = try JSONDecoder().decode(Self.self, from: data)
        guard let content = response.choices.first?.message.content else {
            throw DeepSeekTranslationError.invalidResponse
        }
        return content.trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
