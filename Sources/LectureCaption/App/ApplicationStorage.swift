import Foundation

enum ApplicationStorage {
    static let directoryConfigurationKey = "LectureCaptionStorageDirectory"

    static var directoryName: String {
        directoryName(
            configuredName: Bundle.main.object(forInfoDictionaryKey: directoryConfigurationKey) as? String
        )
    }

    static func directoryName(configuredName: String?) -> String {
        if let configuredName = configuredName?.trimmingCharacters(in: .whitespacesAndNewlines),
           !configuredName.isEmpty,
           !configuredName.hasPrefix("$(") {
            return configuredName
        }

        #if DEBUG
        return "LectureCaption-Debug"
        #else
        return "LectureCaption"
        #endif
    }

    static func applicationSupportDirectory(fileManager: FileManager = .default) -> URL {
        let baseDirectory = fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? URL(fileURLWithPath: NSTemporaryDirectory(), isDirectory: true)
        return baseDirectory.appendingPathComponent(directoryName, isDirectory: true)
    }
}
