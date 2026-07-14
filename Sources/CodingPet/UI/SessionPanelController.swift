import AppKit
import Combine
import SwiftUI

@MainActor
final class SessionPanelController {
    private let panel: NSPanel
    var onVisibilityChange: (@MainActor (Bool) -> Void)?
    // AppKit owns these opaque monitor tokens. Access is confined to the main
    // thread except for deinit, where they must still be removed.
    nonisolated(unsafe) private var localEventMonitor: Any?
    nonisolated(unsafe) private var globalEventMonitor: Any?
    private var sessionsCancellable: AnyCancellable?
    private weak var anchorPanel: NSPanel?
    private let codexUsageStore: CodexUsageStore

    init(
        store: SessionStore,
        codexUsageStore: CodexUsageStore? = nil,
        onAcknowledge: @escaping @MainActor (AgentSession) -> Void = { _ in },
        onOpenSettings: @escaping @MainActor () -> Void = {}
    ) {
        let usageStore = codexUsageStore ?? CodexUsageStore(
            statusProvider: { .notInstalled }
        )
        self.codexUsageStore = usageStore
        let initialSize = SessionPanelLayout.size(
            sessionCount: store.activeSessions.count
        )
        panel = FocusPreservingPanel(
            contentRect: NSRect(origin: .zero, size: initialSize),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )

        panel.level = .floating
        panel.backgroundColor = .clear
        panel.isOpaque = false
        // AppKit draws a rectangular shadow for a borderless transparent
        // window. The rounded SwiftUI surface provides the visible shadow.
        panel.hasShadow = false
        // This is a non-activating panel, so the app normally remains inactive
        // while it is open. Hiding on deactivation would therefore make the
        // panel disappear as soon as it is shown.
        panel.hidesOnDeactivate = false
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        let hostingView = NSHostingView(
            rootView: SessionPanelRootView(
                usageStore: usageStore,
                onSelect: { session in
                    SessionNavigator.activate(session)
                    if store.acknowledge(session) {
                        onAcknowledge(session)
                    }
                    self.hide()
                },
                onOpenSettings: {
                    self.hide()
                    onOpenSettings()
                }
            )
            .environmentObject(store)
        )
        // The AppKit controller owns the floating panel's exact frame. Do not
        // let SwiftUI's intrinsic content size move or resize the anchor.
        hostingView.sizingOptions = []
        panel.contentView = hostingView

        sessionsCancellable = store.$sessions
            .map { sessions in
                sessions.count { $0.status.isActive }
            }
            .removeDuplicates()
            .sink { [weak self] sessionCount in
                self?.updatePanelSize(sessionCount: sessionCount)
            }
    }

    deinit {
        if let localEventMonitor {
            NSEvent.removeMonitor(localEventMonitor)
        }
        if let globalEventMonitor {
            NSEvent.removeMonitor(globalEventMonitor)
        }
    }

    func toggle(relativeTo botPanel: NSPanel) {
        if panel.isVisible {
            hide()
            return
        }

        anchorPanel = botPanel
        codexUsageStore.refresh()
        position(relativeTo: botPanel)
        attach(to: botPanel)
        panel.orderFrontRegardless()
        onVisibilityChange?(true)
        installEventMonitors(relativeTo: botPanel)
    }

    var isVisible: Bool {
        panel.isVisible
    }

    var canBecomeKey: Bool {
        panel.canBecomeKey
    }

    var hasWindowShadow: Bool {
        panel.hasShadow
    }

    var panelSize: NSSize {
        panel.frame.size
    }

    var panelFrame: NSRect {
        panel.frame
    }

    func reposition(relativeTo botPanel: NSPanel) {
        guard panel.isVisible else { return }
        anchorPanel = botPanel
        position(relativeTo: botPanel)
    }

    func isAttached(to botPanel: NSPanel) -> Bool {
        panel.parent === botPanel
    }

    func handleLocalMouseDown(in clickedWindow: NSWindow?, botPanel: NSPanel) {
        guard panel.isVisible,
              clickedWindow !== panel,
              clickedWindow !== botPanel else { return }
        hide()
    }

    func hide() {
        guard panel.isVisible else { return }
        detachFromAnchor()
        panel.orderOut(nil)
        removeEventMonitors()
        onVisibilityChange?(false)
    }

    private func installEventMonitors(relativeTo botPanel: NSPanel) {
        removeEventMonitors()
        localEventMonitor = NSEvent.addLocalMonitorForEvents(
            matching: [.leftMouseDown, .rightMouseDown]
        ) { [weak self, weak botPanel] event in
            MainActor.assumeIsolated {
                guard let botPanel else { return }
                self?.handleLocalMouseDown(in: event.window, botPanel: botPanel)
            }
            return event
        }
        globalEventMonitor = NSEvent.addGlobalMonitorForEvents(
            matching: [.leftMouseDown, .rightMouseDown]
        ) { [weak self] _ in
            Task { @MainActor in
                self?.hide()
            }
        }
    }

    private func removeEventMonitors() {
        if let localEventMonitor {
            NSEvent.removeMonitor(localEventMonitor)
            self.localEventMonitor = nil
        }
        if let globalEventMonitor {
            NSEvent.removeMonitor(globalEventMonitor)
            self.globalEventMonitor = nil
        }
    }

    private func attach(to botPanel: NSPanel) {
        guard panel.parent !== botPanel else { return }
        panel.parent?.removeChildWindow(panel)
        botPanel.addChildWindow(panel, ordered: .above)
    }

    private func detachFromAnchor() {
        panel.parent?.removeChildWindow(panel)
    }

    private func updatePanelSize(sessionCount: Int) {
        let size = SessionPanelLayout.size(sessionCount: sessionCount)
        guard panel.frame.size != size else { return }
        panel.setContentSize(size)
        if panel.isVisible, let anchorPanel {
            position(relativeTo: anchorPanel)
        }
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

private struct SessionPanelRootView: View {
    @ObservedObject var usageStore: CodexUsageStore
    let onSelect: (AgentSession) -> Void
    let onOpenSettings: () -> Void

    var body: some View {
        SessionPanelView(
            usageSnapshot: usageStore.snapshot,
            onSelect: onSelect,
            onOpenSettings: onOpenSettings
        )
    }
}
