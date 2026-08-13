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

        do {
            return try await translate(request, apiKey: apiKey, includeContext: true)
        } catch let error as DeepSeekTranslationError {
            // Course metadata is optional enrichment. A malformed or oversized value
            // must not prevent the confirmed transcript from receiving a translation.
            guard request.hasTranslationContext,
                  error.isContextRetryable else {
                throw error
            }
            return try await translate(request, apiKey: apiKey, includeContext: false)
        }
    }

    private func translate(
        _ request: TranslationRequest,
        apiKey: String,
        includeContext: Bool
    ) async throws -> String {
        var urlRequest = URLRequest(url: settings.endpoint)
        urlRequest.httpMethod = "POST"
        urlRequest.timeoutInterval = settings.timeout
        urlRequest.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        urlRequest.setValue("application/json", forHTTPHeaderField: "Content-Type")
        urlRequest.httpBody = try JSONEncoder().encode(DeepSeekRequest(
            model: settings.model,
            messages: messages(for: request, includeContext: includeContext)
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
        "你是课堂字幕翻译器。只输出当前句子的\(target.title)译文。可根据连续上下文调整语序、指代和省略，使译文自然连贯；必须保留原意和术语表，不补充事实，不解释，不总结。"
    }

    private func messages(for request: TranslationRequest, includeContext: Bool) -> [ChatMessage] {
        guard includeContext else {
            return [
                ChatMessage(role: "system", content: systemPrompt(target: request.targetLanguage)),
                ChatMessage(role: "user", content: "当前原文：\(bounded(request.sourceText, maximumLength: 2_000))")
            ]
        }

        let glossary = request.glossary.prefix(40)
            .filter { !$0.source.isEmpty && !$0.target.isEmpty }
            .map { "\(bounded($0.source, maximumLength: 120))=\(bounded($0.target, maximumLength: 120))" }
            .joined(separator: "；")
        var messages = [ChatMessage(
            role: "system",
            content: "\(systemPrompt(target: request.targetLanguage))\n课程：\(bounded(request.courseName, maximumLength: 160))\n主题：\(bounded(request.topic, maximumLength: 240))\n原文语言：\(request.sourceLanguage.title)\n术语：\(glossary)"
        )]
        for segment in request.recentContext.suffix(6) {
            messages.append(ChatMessage(role: "user", content: "上文原文：\(bounded(segment.sourceText, maximumLength: 600))"))
            if let translation = segment.translatedText, !translation.isEmpty {
                messages.append(ChatMessage(role: "assistant", content: bounded(translation, maximumLength: 800)))
            }
        }
        messages.append(ChatMessage(role: "user", content: "当前原文：\(bounded(request.sourceText, maximumLength: 2_000))"))
        return messages
    }

    private func bounded(_ value: String, maximumLength: Int) -> String {
        String(value.prefix(maximumLength)).trimmingCharacters(in: .whitespacesAndNewlines)
    }
}

private extension TranslationRequest {
    var hasTranslationContext: Bool {
        !courseName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            || !topic.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            || !glossary.isEmpty
            || !recentContext.isEmpty
    }
}

private extension DeepSeekTranslationError {
    var isContextRetryable: Bool {
        guard case let .requestFailed(statusCode) = self else { return false }
        return statusCode == 400 || statusCode == 413 || statusCode == 422
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
