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
            // Release the hosted AppState when hidden; ownership must not form a cycle.
            panel?.contentView = nil
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
        let hostingView = FloatingCaptionHostingView(rootView: FloatingCaptionWindowView(appState: appState))
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
class FloatingCaptionPanel: NSPanel {
    private var resizeSession: (frame: NSRect, pointer: NSPoint, edges: CaptionResizeEdges)?
    init() {
        super.init(
            contentRect: NSRect(x: 0, y: 0, width: 680, height: 300),
            styleMask: [.nonactivatingPanel, .resizable, .closable, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )

        isFloatingPanel = true
        isRestorable = false
        level = .floating
        collectionBehavior = FloatingCaptionWindowBehavior.collectionBehavior
        hidesOnDeactivate = false
        // Route dragging explicitly; SwiftUI's hosting views can reject background dragging.
        isMovableByWindowBackground = false
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

    override func sendEvent(_ event: NSEvent) {
        if let session = resizeSession {
            if event.type == .leftMouseDragged {
                let pointer = convertPoint(toScreen: event.locationInWindow)
                setFrame(session.edges.resizedFrame(session.frame,
                    delta: NSSize(width: pointer.x - session.pointer.x, height: pointer.y - session.pointer.y),
                    minimum: minSize, maximum: maxSize), display: true)
                return
            }
            if event.type == .leftMouseUp {
                resizeSession = nil
                return
            }
        }
        if event.type == .leftMouseDown {
            let edges = resizeEdges(at: event.locationInWindow)
            if !edges.isEmpty {
                resizeSession = (frame, convertPoint(toScreen: event.locationInWindow), edges)
                return
            }
        }
        if shouldStartWindowDrag(for: event) {
            performDrag(with: event)
        } else {
            super.sendEvent(event)
        }
    }

    func shouldStartWindowDrag(for event: NSEvent) -> Bool {
        guard event.type == .leftMouseDown, let contentView else { return false }
        let point = contentView.convert(event.locationInWindow, from: nil)
        guard contentView.bounds.contains(point), resizeEdges(at: event.locationInWindow).isEmpty else { return false }
        guard !containsControls(at: event.locationInWindow, in: contentView) else { return false }
        var hit = contentView.hitTest(point)
        while let view = hit {
            if view is NSControl { return false } // Includes native scrollbars.
            hit = view.superview
        }
        return true
    }

    private func resizeEdges(at point: NSPoint) -> CaptionResizeEdges {
        guard let contentView else { return [] }
        // Window coordinates are bottom-up even when NSHostingView is flipped.
        return CaptionResizeEdges.at(point, in: contentView.convert(contentView.bounds, to: nil))
    }

    override func orderOut(_ sender: Any?) {
        resizeSession = nil
        super.orderOut(sender)
    }

    private func containsControls(at point: NSPoint, in view: NSView) -> Bool {
        guard !view.isHidden else { return false }
        if view is FloatingCaptionControlsView,
           view.bounds.contains(view.convert(point, from: nil)) { return true }
        return view.subviews.contains { containsControls(at: point, in: $0) }
    }

    func centerOnPreferredScreen() {
        guard let screen = NSScreen.main ?? NSScreen.screens.first else { return }
        let visibleFrame = screen.visibleFrame
        setFrameOrigin(NSPoint(
            x: visibleFrame.midX - (frame.width / 2),
            y: visibleFrame.minY + visibleFrame.height * 0.16
        ))
    }
}

/// Explicit resize geometry for the borderless panel: 14pt edges and 24pt corners.
struct CaptionResizeEdges: OptionSet {
    let rawValue: Int
    static let left = Self(rawValue: 1)
    static let right = Self(rawValue: 2)
    static let bottom = Self(rawValue: 4)
    static let top = Self(rawValue: 8)

    static func at(_ point: NSPoint, in bounds: NSRect) -> Self {
        guard bounds.contains(point) else { return [] }
        let nearLeft = point.x < bounds.minX + 24
        let nearRight = point.x >= bounds.maxX - 24
        let nearBottom = point.y < bounds.minY + 24
        let nearTop = point.y >= bounds.maxY - 24
        var edges: Self = []
        if point.x < bounds.minX + 14 || (nearLeft && (nearBottom || nearTop)) { edges.insert(.left) }
        if point.x >= bounds.maxX - 14 || (nearRight && (nearBottom || nearTop)) { edges.insert(.right) }
        if point.y < bounds.minY + 14 || (nearBottom && (nearLeft || nearRight)) { edges.insert(.bottom) }
        if point.y >= bounds.maxY - 14 || (nearTop && (nearLeft || nearRight)) { edges.insert(.top) }
        return edges
    }

    func resizedFrame(_ original: NSRect, delta: NSSize, minimum: NSSize, maximum: NSSize) -> NSRect {
        var result = original
        if contains(.left) || contains(.right) {
            result.size.width = min(maximum.width, max(minimum.width, original.width + (contains(.left) ? -delta.width : delta.width)))
            if contains(.left) { result.origin.x = original.maxX - result.width }
        }
        if contains(.bottom) || contains(.top) {
            result.size.height = min(maximum.height, max(minimum.height, original.height + (contains(.bottom) ? -delta.height : delta.height)))
            if contains(.bottom) { result.origin.y = original.maxY - result.height }
        }
        return result
    }
}

private final class FloatingCaptionHostingView: NSHostingView<FloatingCaptionWindowView> {
    override func resetCursorRects() {
        super.resetCursorRects()
        addCursorRect(NSRect(x: bounds.minX, y: bounds.minY + 24, width: 14, height: bounds.height - 48), cursor: .resizeLeftRight)
        addCursorRect(NSRect(x: bounds.maxX - 14, y: bounds.minY + 24, width: 14, height: bounds.height - 48), cursor: .resizeLeftRight)
        addCursorRect(NSRect(x: bounds.minX + 24, y: bounds.minY, width: bounds.width - 48, height: 14), cursor: .resizeUpDown)
        addCursorRect(NSRect(x: bounds.minX + 24, y: bounds.maxY - 14, width: bounds.width - 48, height: 14), cursor: .resizeUpDown)
        for x in [bounds.minX, bounds.maxX - 24] {
            for y in [bounds.minY, bounds.maxY - 24] {
                addCursorRect(NSRect(x: x, y: y, width: 24, height: 24), cursor: .crosshair)
            }
        }
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
