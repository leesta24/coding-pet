import AppKit
import SwiftUI

@MainActor
final class BotWindowController {
    private let panel: NSPanel
    private let sessionPanel: SessionPanelController

    init(store: SessionStore) {
        panel = NSPanel(
            contentRect: NSRect(x: 0, y: 0, width: 104, height: 104),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        sessionPanel = SessionPanelController(store: store)

        panel.level = .floating
        panel.backgroundColor = .clear
        panel.isOpaque = false
        panel.hasShadow = false
        panel.hidesOnDeactivate = false
        panel.isMovableByWindowBackground = true
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        panel.contentView = NSHostingView(
            rootView: BotView { [weak sessionPanel, weak panel] in
                guard let panel else { return }
                sessionPanel?.toggle(relativeTo: panel)
            }
            .environmentObject(store)
        )

        positionOnPrimaryScreen()
    }

    func show() {
        panel.orderFrontRegardless()
    }

    private func positionOnPrimaryScreen() {
        guard let visibleFrame = NSScreen.main?.visibleFrame else { return }
        let origin = NSPoint(
            x: visibleFrame.maxX - panel.frame.width - 24,
            y: visibleFrame.minY + 42
        )
        panel.setFrameOrigin(origin)
    }
}

