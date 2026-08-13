import AppKit
import SwiftUI

@MainActor
final class FloatingCaptionWindowController: NSObject, NSWindowDelegate {
    private var panel: FloatingCaptionPanel?
    private weak var appState: AppState?

    func setVisible(_ isVisible: Bool, appState: AppState) {
        self.appState = appState

        if isVisible {
            show(appState: appState)
        } else {
            panel?.orderOut(nil)
        }
    }

    private func show(appState: AppState) {
        let panel: FloatingCaptionPanel
        if let existingPanel = self.panel {
            existingPanel.contentView = makeContentView(appState: appState)
            panel = existingPanel
        } else {
            panel = FloatingCaptionPanel()
            panel.delegate = self
            panel.contentView = makeContentView(appState: appState)
            panel.centerOnPreferredScreen()
            self.panel = panel
        }

        panel.orderFrontRegardless()
    }

    private func makeContentView(appState: AppState) -> NSHostingView<FloatingCaptionWindowView> {
        let hostingView = NSHostingView(rootView: FloatingCaptionWindowView(appState: appState))
        // The panel owns its fixed, user-resizable bounds; subtitle content must not resize it.
        hostingView.sizingOptions = []
        return hostingView
    }

    func windowWillClose(_ notification: Notification) {
        panel = nil
        appState?.isFloatingCaptionVisible = false
    }
}

@MainActor
private final class FloatingCaptionPanel: NSPanel {
    init() {
        super.init(
            contentRect: NSRect(x: 0, y: 0, width: 680, height: 300),
            styleMask: [.nonactivatingPanel, .resizable, .closable, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )

        isFloatingPanel = true
        level = .floating
        collectionBehavior = FloatingCaptionWindowBehavior.collectionBehavior
        hidesOnDeactivate = false
        isMovableByWindowBackground = true
        isOpaque = false
        backgroundColor = .clear
        titleVisibility = .hidden
        titlebarAppearsTransparent = true
        hasShadow = true
        minSize = FloatingCaptionWindowBehavior.minimumSize
        maxSize = FloatingCaptionWindowBehavior.maximumSize
    }

    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }

    func centerOnPreferredScreen() {
        guard let screen = NSScreen.main ?? NSScreen.screens.first else { return }
        let visibleFrame = screen.visibleFrame
        setFrameOrigin(NSPoint(
            x: visibleFrame.midX - (frame.width / 2),
            y: visibleFrame.minY + visibleFrame.height * 0.16
        ))
    }
}

enum FloatingCaptionWindowBehavior {
    static let minimumSize = NSSize(width: 420, height: 180)
    static let maximumSize = NSSize(width: 1_200, height: 720)

    static let collectionBehavior: NSWindow.CollectionBehavior = [
        .canJoinAllSpaces,
        .fullScreenAuxiliary
    ]
}
