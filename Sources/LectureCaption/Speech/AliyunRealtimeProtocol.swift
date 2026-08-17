import Foundation

struct AliyunRealtimeSettings: Sendable, Equatable {
    enum Region: String, Sendable, CaseIterable {
        case singapore
        case beijing

        var hostSuffix: String {
            switch self {
            case .singapore: "ap-southeast-1.maas.aliyuncs.com"
            case .beijing: "cn-beijing.maas.aliyuncs.com"
            }
        }

        var displayName: String {
            switch self {
            case .singapore: "新加坡"
            case .beijing: "北京"
            }
        }
    }

    let workspaceID: String
    let region: Region
    let model: String

    init(
        workspaceID: String,
        region: Region = .singapore,
        model: String = "qwen-audio-3.0-asr-flash-streaming"
    ) {
        self.workspaceID = workspaceID
        self.region = region
        self.model = model
    }

    var endpoint: URL? {
        URL(string: "wss://\(workspaceID).\(region.hostSuffix)/api-ws/v1/inference")
    }
}

enum AliyunRealtimeProtocol {
    static func runTask(
        taskID: String,
        settings: AliyunRealtimeSettings,
        speech: SpeechConfiguration
    ) throws -> String {
        let vocabulary = Dictionary(
            uniqueKeysWithValues: speech.glossary.map { ($0.source, 3) }
        )
        let parameters = RunTaskParameters(
            format: "pcm",
            sampleRate: Int(speech.sampleRate.rounded()),
            semanticPunctuationEnabled: true,
            maxSentenceSilence: 1_300,
            heartbeat: true,
            languageHints: languageHints(for: speech.sourceLanguage),
            vocabulary: vocabulary.isEmpty ? nil : vocabulary
        )
        let request = RunTaskRequest(
            header: TaskHeader(action: "run-task", taskID: taskID, streaming: "duplex"),
            payload: RunTaskPayload(model: settings.model, parameters: parameters)
        )
        return try encode(request)
    }

    static func finishTask(taskID: String) throws -> String {
        try encode(FinishTaskRequest(
            header: TaskHeader(action: "finish-task", taskID: taskID, streaming: "duplex"),
            payload: FinishTaskPayload()
        ))
    }

    static func parseServerEvent(_ text: String, expectedTaskID: String) throws -> TranscriptEvent? {
        let response = try JSONDecoder().decode(ServerEvent.self, from: Data(text.utf8))
        guard response.header.taskID == nil || response.header.taskID == expectedTaskID else {
            return nil
        }

        switch response.header.event {
        case "task-started":
            return .ready
        case "task-finished":
            return .finished
        case "task-failed":
            return .failed(
                code: response.header.errorCode ?? "UNKNOWN",
                message: response.header.errorMessage ?? "The recognition task failed."
            )
        case "result-generated":
            guard let sentence = response.payload?.output?.sentence,
                  let sentenceID = sentence.sentenceID,
                  sentenceID != 0,
                  let text = sentence.text?.trimmingCharacters(in: .whitespacesAndNewlines),
                  !text.isEmpty else {
                return nil
            }
            let startedAt = Double(sentence.beginTime ?? 0) / 1_000
            let endedAt = Double(sentence.endTime ?? sentence.beginTime ?? 0) / 1_000
            let id = String(sentenceID)
            if sentence.sentenceEnd == true {
                return .final(providerSentenceID: id, text: text, startedAt: startedAt, endedAt: endedAt)
            }
            return .partial(providerSentenceID: id, text: text, startedAt: startedAt)
        default:
            return nil
        }
    }

    private static func languageHints(for language: RecognitionLanguage) -> [String]? {
        switch language {
        case .automatic: nil
        case .english: ["en"]
        case .chinese: ["zh"]
        }
    }

    private static func encode<T: Encodable>(_ value: T) throws -> String {
        let data = try JSONEncoder().encode(value)
        guard let text = String(data: data, encoding: .utf8) else {
            throw AliyunProtocolError.invalidMessage
        }
        return text
    }
}

enum AliyunProtocolError: Error {
    case invalidMessage
}

private struct TaskHeader: Encodable {
    let action: String
    let taskID: String
    let streaming: String

    enum CodingKeys: String, CodingKey {
        case action
        case taskID = "task_id"
        case streaming
    }
}

private struct RunTaskRequest: Encodable {
    let header: TaskHeader
    let payload: RunTaskPayload
}

private struct RunTaskPayload: Encodable {
    let taskGroup = "audio"
    let task = "asr"
    let function = "recognition"
    let model: String
    let parameters: RunTaskParameters
    let input: [String: String] = [:]

    enum CodingKeys: String, CodingKey {
        case taskGroup = "task_group"
        case task
        case function
        case model
        case parameters
        case input
    }
}

private struct RunTaskParameters: Encodable {
    let format: String
    let sampleRate: Int
    let semanticPunctuationEnabled: Bool
    let maxSentenceSilence: Int
    let heartbeat: Bool
    let languageHints: [String]?
    let vocabulary: [String: Int]?

    enum CodingKeys: String, CodingKey {
        case format
        case sampleRate = "sample_rate"
        case semanticPunctuationEnabled = "semantic_punctuation_enabled"
        case maxSentenceSilence = "max_sentence_silence"
        case heartbeat
        case languageHints = "language_hints"
        case vocabulary
    }
}

private struct FinishTaskRequest: Encodable {
    let header: TaskHeader
    let payload: FinishTaskPayload
}

private struct FinishTaskPayload: Encodable {
    let input: [String: String] = [:]
}

private struct ServerEvent: Decodable {
    let header: ServerHeader
    let payload: ServerPayload?
}

private struct ServerHeader: Decodable {
    let taskID: String?
    let event: String
    let errorCode: String?
    let errorMessage: String?

    enum CodingKeys: String, CodingKey {
        case taskID = "task_id"
        case event
        case errorCode = "error_code"
        case errorMessage = "error_message"
    }
}

private struct ServerPayload: Decodable {
    let output: ServerOutput?
}

private struct ServerOutput: Decodable {
    let sentence: ServerSentence?
}

private struct ServerSentence: Decodable {
    let text: String?
    let beginTime: Int?
    let endTime: Int?
    let sentenceEnd: Bool?
    let sentenceID: Int?

    enum CodingKeys: String, CodingKey {
        case text
        case beginTime = "begin_time"
        case endTime = "end_time"
        case sentenceEnd = "sentence_end"
        case sentenceID = "sentence_id"
    }
}
