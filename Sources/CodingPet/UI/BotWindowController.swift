import AppKit
import Combine
import SwiftUI

@MainActor
final class BotWindowController {
    static let bubblePanelSize = NSSize(width: 328, height: 212)
    private static let fullBubbleWidth: CGFloat = 328
    private static let compactBubbleWidth: CGFloat = 72
    private static let conversationBubbleHeight: CGFloat = 64
    private static let compactBubbleHeight: CGFloat = 36
    private static let bubbleSpacing: CGFloat = 8
    private static let bubbleTopPadding: CGFloat = 8
    private static let bubbleBottomPadding: CGFloat = 8

    private let panel: NSPanel
    private let bubblePanel: NSPanel
    private let sessionPanel: SessionPanelController
    private let settingsWindow: SettingsWindowController
    private let store: SessionStore
    private let onAcknowledge: @MainActor (AgentSession) -> Void
    private let navigateToSession: @MainActor (AgentSession) -> Void
    private let appearanceStore: PetAppearanceStore
    private let bubbleSettingsStore: SessionBubbleSettingsStore
    nonisolated(unsafe) private var pointerEventMonitor: Any?
    private var botSizeCancellable: AnyCancellable?
    private var bubblePresentationCancellable: AnyCancellable?
    private var pointerGate = BotPointerInteractionGate()
    private var hasBeenShown = false
    private var hasVisibleBubbleContent = false

    init(
        store: SessionStore,
        appearanceStore: PetAppearanceStore = PetAppearanceStore(),
        bubbleSettingsStore: SessionBubbleSettingsStore = SessionBubbleSettingsStore(),
        onAcknowledge: @escaping @MainActor (AgentSession) -> Void = { _ in },
        navigateToSession: @escaping @MainActor (AgentSession) -> Void = {
            SessionNavigator.activate($0)
        }
    ) {
        let botWindowSide = CGFloat(appearanceStore.botSize) + 20
        panel = FocusPreservingPanel(
            contentRect: NSRect(x: 0, y: 0, width: botWindowSide, height: botWindowSide),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        bubblePanel = FocusPreservingPanel(
            contentRect: NSRect(origin: .zero, size: Self.bubblePanelSize),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        self.store = store
        self.onAcknowledge = onAcknowledge
        self.navigateToSession = navigateToSession
        self.appearanceStore = appearanceStore
        self.bubbleSettingsStore = bubbleSettingsStore
        let hookURL = AppBundlePaths.hookExecutableURL
        let integrationStore = IntegrationSettingsStore(
            coordinator: HookInstallationCoordinator(hookExecutableURL: hookURL)
        )
        let codexUsageStore = CodexUsageStore(
            statusProvider: {
                integrationStore.refresh()
                return integrationStore.statuses[.codex] ?? .notInstalled
            }
        )
        let settingsWindow = SettingsWindowController(
            sessionStore: store,
            appearanceStore: appearanceStore,
            bubbleSettingsStore: bubbleSettingsStore,
            hookExecutableURL: hookURL,
            integrationStore: integrationStore
        )
        self.settingsWindow = settingsWindow
        sessionPanel = SessionPanelController(
            store: store,
            codexUsageStore: codexUsageStore,
            onAcknowledge: onAcknowledge,
            onOpenSettings: { [weak settingsWindow] in
                settingsWindow?.show()
            }
        )

        panel.level = .floating
        panel.backgroundColor = .clear
        panel.isOpaque = false
        panel.hasShadow = false
        panel.hidesOnDeactivate = false
        panel.isMovableByWindowBackground = true
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        panel.contentView = Self.transparentHostingView(
            rootView: BotView { [weak self] in
                self?.handleBotActivation()
            }
            .environmentObject(store)
            .environmentObject(appearanceStore)
        )

        bubblePanel.level = .floating
        bubblePanel.backgroundColor = .clear
        bubblePanel.isOpaque = false
        bubblePanel.hasShadow = false
        bubblePanel.hidesOnDeactivate = false
        bubblePanel.ignoresMouseEvents = false
        bubblePanel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        bubblePanel.contentView = Self.transparentHostingView(
            rootView: BotSessionBubbleView(
                onSelect: { [weak self] session in
                    self?.handleBubbleActivation(session)
                },
                onDismiss: { [weak self] session in
                    self?.handleBubbleDismissal(session)
                },
                onSelectCompact: { [weak self] in
                    self?.toggleSessionPanel()
                }
            )
                .environmentObject(store)
                .environmentObject(bubbleSettingsStore)
                .environmentObject(appearanceStore)
        )

        positionOnActiveScreen()
        installPointerEventMonitor()
        observeBotSize()
        observeBubblePresentation()
        sessionPanel.onVisibilityChange = { [weak self] isVisible in
            self?.handleSessionPanelVisibilityChange(isVisible)
        }
    }

    private static func transparentHostingView<Content: View>(
        rootView: Content
    ) -> NSHostingView<Content> {
        let hostingView = NSHostingView(rootView: rootView)
        hostingView.sizingOptions = []
        BotBubbleScrollViewFactory.makeTransparent(hostingView)
        return hostingView
    }

    deinit {
        if let pointerEventMonitor {
            NSEvent.removeMonitor(pointerEventMonitor)
        }
    }

    func show() {
        hasBeenShown = true
        positionBubblePanel()
        if hasVisibleBubbleContent, !sessionPanel.isVisible {
            showBubblePanel()
        }
        panel.orderFrontRegardless()
    }

    var isSessionPanelVisible: Bool {
        sessionPanel.isVisible
    }

    var floatingPanelsPreserveKeyboardFocus: Bool {
        !panel.canBecomeKey && !bubblePanel.canBecomeKey && !sessionPanel.canBecomeKey
    }

    var bubbleOverlayIgnoresMouseEvents: Bool { bubblePanel.ignoresMouseEvents }

    var bubbleOverlayFrame: NSRect { bubblePanel.frame }

    var isBubbleOverlayVisible: Bool { bubblePanel.isVisible }

    var isBubbleOverlayAttachedToBot: Bool { bubblePanel.parent === panel }

    var botWindowFrame: NSRect { panel.frame }

    var sessionPanelHasWindowShadow: Bool {
        sessionPanel.hasWindowShadow
    }

    var isSessionPanelAttachedToBot: Bool {
        sessionPanel.isAttached(to: panel)
    }

    func toggleSessionPanel() {
        sessionPanel.toggle(relativeTo: panel)
    }

    func showSettings() {
        sessionPanel.hide()
        settingsWindow.show()
    }

    var isSettingsVisible: Bool {
        settingsWindow.isVisible
    }

    static func preferredScreen(
        at point: NSPoint,
        screens: [NSScreen] = NSScreen.screens
    ) -> NSScreen? {
        screens.first { $0.frame.contains(point) } ?? NSScreen.main ?? screens.first
    }

    private func positionOnActiveScreen() {
        guard let visibleFrame = Self.preferredScreen(at: NSEvent.mouseLocation)?.visibleFrame else {
            return
        }
        let origin = NSPoint(
            x: visibleFrame.maxX - panel.frame.width - 24,
            y: visibleFrame.minY + 42
        )
        panel.setFrameOrigin(origin)
        positionAttachedPanels()
    }

    static func bubbleFrame(
        relativeTo botFrame: NSRect,
        visibleFrame: NSRect,
        bubbleSize: NSSize = bubblePanelSize
    ) -> NSRect {
        let margin: CGFloat = 12
        let preferredX = botFrame.midX - bubbleSize.width + 28
        let preferredY = botFrame.maxY - 8
        let maximumX = visibleFrame.maxX - bubbleSize.width - margin
        let maximumY = visibleFrame.maxY - bubbleSize.height - margin
        let x = min(max(preferredX, visibleFrame.minX + margin), maximumX)
        let y = min(max(preferredY, visibleFrame.minY + margin), maximumY)
        return NSRect(x: x, y: y, width: bubbleSize.width, height: bubbleSize.height)
    }

    static func resizedBotFrame(
        from currentFrame: NSRect,
        botSize: CGFloat
    ) -> NSRect {
        let center = currentFrame.center
        let side = botSize + 20
        return NSRect(
            x: center.x - side / 2,
            y: center.y - side / 2,
            width: side,
            height: side
        )
    }

    static func bubblePanelSize(for presentation: BotBubblePresentation) -> NSSize {
        let fullCount = presentation.sessions.count
        let visibleFullCount = min(
            fullCount,
            BotBubblePresentation.maximumVisibleRows
        )
        let hasCompactBubble = presentation.compactAttentionCount > 0
        guard visibleFullCount > 0 || hasCompactBubble else { return .zero }

        var contentHeight: CGFloat = 0
        if visibleFullCount > 0 {
            contentHeight += bubbleTopPadding
                + CGFloat(visibleFullCount) * conversationBubbleHeight
                + CGFloat(visibleFullCount - 1) * bubbleSpacing
        }
        if hasCompactBubble {
            if visibleFullCount > 0 {
                contentHeight += bubbleSpacing
            }
            contentHeight += compactBubbleHeight
        }
        return NSSize(
            width: fullCount > 0 ? fullBubbleWidth : compactBubbleWidth,
            height: contentHeight + bubbleBottomPadding
        )
    }

    private func positionBubblePanel() {
        guard let screen = panel.screen ?? Self.preferredScreen(at: panel.frame.center) else {
            return
        }
        bubblePanel.setFrame(
            Self.bubbleFrame(
                relativeTo: panel.frame,
                visibleFrame: screen.visibleFrame,
                bubbleSize: bubblePanel.frame.size
            ),
            display: true
        )
    }

    private func positionAttachedPanels() {
        positionBubblePanel()
        sessionPanel.reposition(relativeTo: panel)
    }

    private func showBubblePanel() {
        if bubblePanel.parent !== panel {
            bubblePanel.parent?.removeChildWindow(bubblePanel)
            panel.addChildWindow(bubblePanel, ordered: .above)
        }
        bubblePanel.orderFrontRegardless()
    }

    private func hideBubblePanel() {
        bubblePanel.parent?.removeChildWindow(bubblePanel)
        bubblePanel.orderOut(nil)
    }

    private func installPointerEventMonitor() {
        pointerEventMonitor = NSEvent.addLocalMonitorForEvents(
            matching: [.leftMouseDown, .leftMouseDragged, .leftMouseUp]
        ) { [weak self, weak panel] event in
            MainActor.assumeIsolated {
                guard let self, event.window === panel else { return }
                let location = NSEvent.mouseLocation
                switch event.type {
                case .leftMouseDown:
                    self.handleBotPointerDown(at: location)
                case .leftMouseDragged:
                    self.handleBotPointerDragged(to: location)
                case .leftMouseUp:
                    self.handleBotPointerUp(at: location)
                default:
                    break
                }
            }
            return event
        }
    }

    private func observeBotSize() {
        botSizeCancellable = appearanceStore.$botSize
            .removeDuplicates()
            .sink { [weak self] size in
                self?.resizeBotWindow(to: CGFloat(size))
            }
    }

    private func observeBubblePresentation() {
        bubblePresentationCancellable = Publishers.CombineLatest(
            Publishers.CombineLatest(
                store.$sessions,
                store.$dismissedBubbleVersions
            ),
            Publishers.CombineLatest3(
                bubbleSettingsStore.$runningBubblesEnabled,
                bubbleSettingsStore.$pendingBubblesEnabled,
                bubbleSettingsStore.$readyBubblesEnabled
            )
        )
        .map { sessionState, bubblePreferences in
            let (sessions, dismissedVersions) = sessionState
            let (runningEnabled, pendingEnabled, readyEnabled) = bubblePreferences
            let visibleSessions = sessions.filter {
                dismissedVersions[$0.id]?.suppresses($0) != true
            }
            return BotBubblePresentation(
                sessions: visibleSessions,
                runningBubblesEnabled: runningEnabled,
                pendingBubblesEnabled: pendingEnabled,
                readyBubblesEnabled: readyEnabled
            )
        }
        .removeDuplicates()
        .sink { [weak self] presentation in
            self?.updateBubblePanel(for: presentation)
        }
    }

    private func updateBubblePanel(for presentation: BotBubblePresentation) {
        let size = Self.bubblePanelSize(for: presentation)
        hasVisibleBubbleContent = size != .zero
        guard hasVisibleBubbleContent else {
            hideBubblePanel()
            return
        }

        var frame = bubblePanel.frame
        frame.size = size
        bubblePanel.setFrame(frame, display: true)
        positionBubblePanel()
        if hasBeenShown, !sessionPanel.isVisible {
            showBubblePanel()
        }
    }

    private func handleSessionPanelVisibilityChange(_ isVisible: Bool) {
        if isVisible {
            hideBubblePanel()
        } else if hasBeenShown, hasVisibleBubbleContent {
            positionBubblePanel()
            showBubblePanel()
        }
    }

    private func resizeBotWindow(to botSize: CGFloat) {
        panel.setFrame(
            Self.resizedBotFrame(from: panel.frame, botSize: botSize),
            display: true
        )
        positionAttachedPanels()
    }

    func handleBotPointerDown(at location: NSPoint) {
        pointerGate.pointerDown(at: location)
    }

    func handleBotPointerDragged(to location: NSPoint) {
        pointerGate.pointerDragged(to: location)
    }

    func handleBotPointerUp(at location: NSPoint) {
        pointerGate.pointerUp(at: location)
        // Native child windows move atomically with the pet. Recompute their
        // clamped placement once, after a drag may have crossed displays.
        positionAttachedPanels()
    }

    func handleBotActivation() {
        guard pointerGate.consumeActivation() else { return }
        sessionPanel.toggle(relativeTo: panel)
    }

    func handleBubbleActivation(_ session: AgentSession) {
        navigateToSession(session)
        if store.acknowledge(session) {
            onAcknowledge(session)
        }
        sessionPanel.hide()
    }

    func handleBubbleDismissal(_ session: AgentSession) {
        store.dismissBubble(for: session)
    }
}

private extension NSRect {
    var center: NSPoint {
        NSPoint(x: midX, y: midY)
    }
}

struct BotPointerInteractionGate {
    static let dragThreshold: CGFloat = 4

    private var pointerDownLocation: NSPoint?
    private var dragged = false
    private var suppressActivation = false

    mutating func pointerDown(at location: NSPoint) {
        pointerDownLocation = location
        dragged = false
        suppressActivation = false
    }

    mutating func pointerDragged(to location: NSPoint) {
        updateDragState(at: location)
    }

    mutating func pointerUp(at location: NSPoint) {
        updateDragState(at: location)
        suppressActivation = dragged
        pointerDownLocation = nil
        dragged = false
    }

    mutating func consumeActivation() -> Bool {
        let shouldActivate = !suppressActivation
        suppressActivation = false
        return shouldActivate
    }

    private mutating func updateDragState(at location: NSPoint) {
        guard !dragged, let start = pointerDownLocation else { return }
        let distance = hypot(location.x - start.x, location.y - start.y)
        dragged = distance >= Self.dragThreshold
    }
}
