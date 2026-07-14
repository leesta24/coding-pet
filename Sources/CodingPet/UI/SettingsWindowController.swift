import AppKit
import SwiftUI

@MainActor
final class SettingsWindowController {
    private let window: NSWindow
    private let integrationStore: IntegrationSettingsStore
    private var hasPositionedWindow = false

    init(
        sessionStore: SessionStore,
        appearanceStore: PetAppearanceStore,
        bubbleSettingsStore: SessionBubbleSettingsStore = SessionBubbleSettingsStore(),
        hookExecutableURL: URL? = nil,
        integrationStore: IntegrationSettingsStore? = nil
    ) {
        let hookURL = hookExecutableURL ?? AppBundlePaths.hookExecutableURL
        let resolvedIntegrationStore = integrationStore ?? IntegrationSettingsStore(
            coordinator: HookInstallationCoordinator(hookExecutableURL: hookURL)
        )
        self.integrationStore = resolvedIntegrationStore

        window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 760, height: 700),
            styleMask: [.titled, .closable, .miniaturizable],
            backing: .buffered,
            defer: false
        )
        window.title = "CodingPet Settings"
        window.titlebarAppearsTransparent = true
        window.isReleasedWhenClosed = false
        window.tabbingMode = .disallowed
        window.collectionBehavior = [.moveToActiveSpace]
        window.minSize = NSSize(width: 720, height: 650)
        window.contentView = NSHostingView(
            rootView: SettingsView()
                .environmentObject(sessionStore)
                .environmentObject(appearanceStore)
                .environmentObject(bubbleSettingsStore)
                .environmentObject(resolvedIntegrationStore)
        )
    }

    func show() {
        integrationStore.refresh()
        if !hasPositionedWindow {
            window.center()
            hasPositionedWindow = true
        }
        NSApp.activate(ignoringOtherApps: true)
        window.makeKeyAndOrderFront(nil)
    }

    func close() {
        window.close()
    }

    var isVisible: Bool {
        window.isVisible
    }

    var canBecomeKey: Bool {
        window.canBecomeKey
    }
}
