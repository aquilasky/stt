import AppKit
import SwiftUI

@main
struct LectureCaptionApp: App {
    @State private var appState = AppState()
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate

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

        guard let window = mainWindow else {
            return
        }

        if !hasVisibleTitleBar(window) {
            let screen = NSScreen.main ?? NSScreen.screens.first
            guard let screen else { return }
            let visibleFrame = screen.visibleFrame
            let origin = NSPoint(
                x: visibleFrame.midX - (window.frame.width / 2),
                y: visibleFrame.midY - (window.frame.height / 2)
            )
            window.setFrameOrigin(origin)
        }

        window.collectionBehavior = MainWindowSpaceBehavior.standardized(window.collectionBehavior)
        NSApp.activate(ignoringOtherApps: true)
        window.makeKeyAndOrderFront(nil)
    }

    static func restoreMainWindowAfterActivationIfNeeded() {
        guard MainWindowSpaceBehavior.shouldRestoreAfterActivation(
            hasKeyWindow: NSApp.keyWindow != nil,
            mainWindowIsVisible: mainWindow?.isVisible ?? false
        ),
              let window = mainWindow,
              window.isVisible else {
            return
        }

        window.makeKeyAndOrderFront(nil)
    }

    private static var mainWindow: NSWindow? {
        NSApp.windows.first {
            $0.styleMask.contains(.titled) && !($0 is NSPanel)
        }
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

enum MainWindowSpaceBehavior {
    static func standardized(_ behavior: NSWindow.CollectionBehavior) -> NSWindow.CollectionBehavior {
        behavior.subtracting(.moveToActiveSpace)
    }

    static func shouldRestoreAfterActivation(
        hasKeyWindow: Bool,
        mainWindowIsVisible: Bool
    ) -> Bool {
        !hasKeyWindow && mainWindowIsVisible
    }
}

@MainActor
private final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.regular)
        NSApp.activate(ignoringOtherApps: true)
    }

    func applicationDidBecomeActive(_ notification: Notification) {
        DispatchQueue.main.async {
            WindowVisibilityController.restoreMainWindowAfterActivationIfNeeded()
        }
    }
}
