import AppKit
import SwiftUI

@MainActor
final class SessionPanelController {
    private let panel: NSPanel

    init(store: SessionStore) {
        panel = NSPanel(
            contentRect: NSRect(x: 0, y: 0, width: 360, height: 320),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )

        panel.level = .floating
        panel.backgroundColor = .clear
        panel.isOpaque = false
        panel.hasShadow = true
        panel.hidesOnDeactivate = true
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        panel.contentView = NSHostingView(
            rootView: SessionPanelView { session in
                SessionNavigator.activate(session)
                self.panel.orderOut(nil)
            }
            .environmentObject(store)
        )
    }

    func toggle(relativeTo botPanel: NSPanel) {
        if panel.isVisible {
            panel.orderOut(nil)
            return
        }

        position(relativeTo: botPanel)
        panel.orderFrontRegardless()
    }

    private func position(relativeTo botPanel: NSPanel) {
        let screenFrame = botPanel.screen?.visibleFrame ?? NSScreen.main?.visibleFrame ?? .zero
        let preferredX = botPanel.frame.minX - panel.frame.width - 12
        let x = max(screenFrame.minX + 12, preferredX)
        let y = min(
            max(screenFrame.minY + 12, botPanel.frame.minY),
            screenFrame.maxY - panel.frame.height - 12
        )
        panel.setFrameOrigin(NSPoint(x: x, y: y))
    }
}

