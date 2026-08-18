import CoreGraphics

enum MainWindowSidebarSection: CaseIterable, Identifiable {
    case configuration
    case history

    var id: Self { self }

    var title: String {
        switch self {
        case .configuration: "配置"
        case .history: "课堂记录"
        }
    }

    var symbolName: String {
        switch self {
        case .configuration: "slider.horizontal.3"
        case .history: "clock.arrow.circlepath"
        }
    }
}

struct MainWindowSidebarState: Equatable {
    private(set) var selectedSection: MainWindowSidebarSection?

    init(selectedSection: MainWindowSidebarSection? = .configuration) {
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
