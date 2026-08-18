import CoreGraphics

enum MainWindowSidebarSection: CaseIterable, Identifiable {
    case apiConfiguration
    case courseConfiguration
    case history

    var id: Self { self }

    var title: String {
        switch self {
        case .apiConfiguration: "API 与识别"
        case .courseConfiguration: "课程"
        case .history: "课堂记录"
        }
    }

    var symbolName: String {
        switch self {
        case .apiConfiguration: "key.horizontal"
        case .courseConfiguration: "book.closed"
        case .history: "clock.arrow.circlepath"
        }
    }
}

struct MainWindowSidebarState: Equatable {
    private(set) var selectedSection: MainWindowSidebarSection?

    init(selectedSection: MainWindowSidebarSection? = .apiConfiguration) {
        self.selectedSection = selectedSection
    }

    var isVisible: Bool {
        selectedSection != nil
    }

    mutating func activate(_ section: MainWindowSidebarSection) {
        selectedSection = selectedSection == section ? nil : section
    }

    mutating func hide() {
        selectedSection = nil
    }
}

enum MainWindowSidebarLayout {
    static let minimumWidth: CGFloat = 280
    static let defaultWidth: CGFloat = 320
    static let maximumWidth: CGFloat = 420
    static let resizeHandleWidth: CGFloat = 6

    static func clampedWidth(_ width: CGFloat) -> CGFloat {
        min(max(width, minimumWidth), maximumWidth)
    }
}
