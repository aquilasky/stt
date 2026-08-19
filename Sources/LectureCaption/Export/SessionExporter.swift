import Foundation
import SwiftUI
import UniformTypeIdentifiers

enum SavedSessionExportFormat: String, CaseIterable, Identifiable {
    case text
    case json

    var id: Self { self }

    var title: String {
        switch self {
        case .text: "TXT"
        case .json: "JSON"
        }
    }

    var contentType: UTType {
        switch self {
        case .text: .plainText
        case .json: .json
        }
    }
}

struct SessionExportDocument: FileDocument {
    static let readableContentTypes: [UTType] = [.plainText, .json]

    let data: Data

    init(data: Data) {
        self.data = data
    }

    init(configuration: ReadConfiguration) throws {
        guard let data = configuration.file.regularFileContents else {
            throw CocoaError(.fileReadCorruptFile)
        }
        self.data = data
    }

    func fileWrapper(configuration: WriteConfiguration) throws -> FileWrapper {
        FileWrapper(regularFileWithContents: data)
    }
}

enum SavedSessionExporter {
    static func document(
        for record: SavedLectureSession,
        format: SavedSessionExportFormat,
        includesTimestamps: Bool
    ) throws -> SessionExportDocument {
        let data: Data
        switch format {
        case .text:
            data = Data(text(for: record, includesTimestamps: includesTimestamps).utf8)
        case .json:
            data = try jsonData(for: record, includesTimestamps: includesTimestamps)
        }
        return SessionExportDocument(data: data)
    }

    static func defaultFilename(for record: SavedLectureSession) -> String {
        let courseName = record.session.context.courseName.trimmingCharacters(in: .whitespacesAndNewlines)
        let title = courseName.isEmpty ? "LectureCaption" : sanitizedFilenameComponent(courseName)
        return "\(title)_\(dateFormatter.string(from: record.startedAt))"
    }

    static func text(for record: SavedLectureSession, includesTimestamps: Bool) -> String {
        let course = record.session.context.courseName.isEmpty
            ? "未填写课程名称"
            : record.session.context.courseName
        let topic = record.session.context.topic.isEmpty
            ? "未填写主题"
            : record.session.context.topic
        var lines = [
            "课程：\(course)",
            "主题：\(topic)",
            ""
        ]

        for segment in record.segments.sorted(by: { $0.sequence < $1.sequence }) {
            let prefix = includesTimestamps
                ? "[\(CaptionTimestampFormatter.string(sessionStartedAt: record.startedAt, offset: segment.startedAt))] "
                : ""
            lines.append("\(prefix)\(segment.sourceText)")
            if let translatedText = segment.translatedText, !translatedText.isEmpty {
                lines.append("\(prefix)\(translatedText)")
            }
            lines.append("")
        }
        return lines.joined(separator: "\n")
    }

    static func jsonData(for record: SavedLectureSession, includesTimestamps: Bool) throws -> Data {
        let document = PublicSessionExport(
            record: record,
            includesTimestamps: includesTimestamps
        )
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        return try encoder.encode(document)
    }

    private static func sanitizedFilenameComponent(_ value: String) -> String {
        let invalid = CharacterSet(charactersIn: "/:\\?%*|\"<>\n\r")
        let sanitized = value.components(separatedBy: invalid)
            .joined(separator: "-")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return sanitized.isEmpty ? "LectureCaption" : sanitized
    }

    private static let dateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = .current
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter
    }()
}

private struct PublicSessionExport: Encodable {
    let formatVersion = 1
    let course: String
    let topic: String
    let sessionStartedAt: Date?
    let sessionEndedAt: Date?
    let segments: [PublicCaptionSegmentExport]

    init(record: SavedLectureSession, includesTimestamps: Bool) {
        course = record.session.context.courseName
        topic = record.session.context.topic
        sessionStartedAt = includesTimestamps ? record.session.startedAt : nil
        sessionEndedAt = includesTimestamps ? record.session.endedAt : nil
        segments = record.segments
            .sorted { $0.sequence < $1.sequence }
            .map { PublicCaptionSegmentExport(segment: $0, includesTimestamps: includesTimestamps) }
    }
}

private struct PublicCaptionSegmentExport: Encodable {
    let sequence: Int
    let sourceText: String
    let translatedText: String?
    let startedAtMilliseconds: Int?
    let endedAtMilliseconds: Int?

    init(segment: CaptionSegment, includesTimestamps: Bool) {
        sequence = segment.sequence
        sourceText = segment.sourceText
        translatedText = segment.translatedText
        startedAtMilliseconds = includesTimestamps ? Self.milliseconds(segment.startedAt) : nil
        endedAtMilliseconds = includesTimestamps ? segment.endedAt.map(Self.milliseconds) : nil
    }

    private static func milliseconds(_ seconds: TimeInterval) -> Int {
        Int((seconds * 1_000).rounded())
    }
}
