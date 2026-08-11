import AppKit
import SwiftUI

@main
struct LectureCaptionApp: App {
    @State private var appState = AppState()

    var body: some Scene {
        WindowGroup {
            MainWindowView(appState: appState)
                .onAppear {
                    DispatchQueue.main.async {
                        WindowVisibilityController.restoreMainWindowIfNeeded()
                    }
                }
        }
        .defaultSize(width: 1_080, height: 720)
        .windowResizability(.contentSize)
    }
}

@MainActor
private enum WindowVisibilityController {
    private static var hasAttemptedRestoration = false

    static func restoreMainWindowIfNeeded() {
        guard !hasAttemptedRestoration else { return }
        hasAttemptedRestoration = true

        guard let window = NSApp.windows.first(where: { $0.styleMask.contains(.titled) }) else {
            return
        }

        guard !hasVisibleTitleBar(window) else { return }

        let screen = NSScreen.main ?? NSScreen.screens.first
        guard let screen else { return }
        let visibleFrame = screen.visibleFrame
        let origin = NSPoint(
            x: visibleFrame.midX - (window.frame.width / 2),
            y: visibleFrame.midY - (window.frame.height / 2)
        )
        window.setFrameOrigin(origin)

        NSApp.activate(ignoringOtherApps: true)
        window.makeKeyAndOrderFront(nil)
    }

    private static func hasVisibleTitleBar(_ window: NSWindow) -> Bool {
        let titleBarHeight = min(32, window.frame.height)
        let titleBar = NSRect(
            x: window.frame.minX,
            y: window.frame.maxY - titleBarHeight,
            width: window.frame.width,
            height: titleBarHeight
        )

        return NSScreen.screens.contains { screen in
            let visibleTitleBar = titleBar.intersection(screen.visibleFrame)
            return visibleTitleBar.width >= min(120, titleBar.width)
                && visibleTitleBar.height >= min(20, titleBar.height)
        }
    }
}
