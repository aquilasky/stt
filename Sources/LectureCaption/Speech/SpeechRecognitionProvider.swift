import Foundation

enum SpeechProviderKind: String, CaseIterable, Identifiable, Codable, Sendable {
    case aliyunRealtime
    case mimoChunked

    var id: Self { self }

    var title: String {
        switch self {
        case .aliyunRealtime: "阿里云实时"
        case .mimoChunked: "MiMo 分块"
        }
    }

    var symbolName: String {
        switch self {
        case .aliyunRealtime: "waveform.path.ecg"
        case .mimoChunked: "waveform.badge.magnifyingglass"
        }
    }
}

enum RecognitionLanguage: String, CaseIterable, Identifiable, Codable, Sendable {
    case automatic
    case english
    case chinese

    var id: Self { self }

    var title: String {
        switch self {
        case .automatic: "自动检测"
        case .english: "英语"
        case .chinese: "中文"
        }
    }
}

enum TargetLanguage: String, CaseIterable, Identifiable, Codable, Sendable {
    case simplifiedChinese
    case english

    var id: Self { self }

    var title: String {
        switch self {
        case .simplifiedChinese: "简体中文"
        case .english: "英语"
        }
    }
}

struct SpeechProviderCapabilities: Sendable, Equatable {
    let supportsPartialResults: Bool
    let acceptsStreamingPCM: Bool
    let supportsVocabulary: Bool
    let supportedLanguages: [RecognitionLanguage]
}

struct SpeechConfiguration: Sendable {
    let provider: SpeechProviderKind
    let sourceLanguage: RecognitionLanguage
    let sampleRate: Double
    let glossary: [GlossaryEntry]
}

enum TranscriptEvent: Sendable, Equatable {
    case ready
    case partial(providerSentenceID: String, text: String, startedAt: TimeInterval)
    case final(providerSentenceID: String, text: String, startedAt: TimeInterval, endedAt: TimeInterval)
    case finished
}

protocol SpeechRecognitionProvider: Sendable {
    var capabilities: SpeechProviderCapabilities { get }

    func start(configuration: SpeechConfiguration) async throws
    func send(audio: Data) async throws
    func flush() async throws
    func events() -> AsyncThrowingStream<TranscriptEvent, Error>
    func stop() async
}
