import AppKit
import Testing
@testable import CodingPet

@Suite(.serialized)
@MainActor
struct SessionPanelControllerTests {
    @Test
    func panelRemainsVisibleWhileAccessoryAppIsInactive() async {
        let application = NSApplication.shared
        application.setActivationPolicy(.accessory)

        let controller = BotWindowController(store: SessionStore(sessions: .demo))
        #expect(!controller.sessionPanelHasWindowShadow)
        #expect(controller.floatingPanelsPreserveKeyboardFocus)
        controller.show()
        controller.toggleSessionPanel()

        try? await Task.sleep(for: .milliseconds(100))

        #expect(controller.isSessionPanelVisible)

        controller.toggleSessionPanel()
        #expect(!controller.isSessionPanelVisible)
    }

    @Test
    func sessionPanelTemporarilyHidesConversationBubbles() {
        let store = SessionStore(sessions: [
            bubbleSession(id: "running", status: .running)
        ])
        let controller = BotWindowController(store: store)

        controller.show()
        #expect(controller.isBubbleOverlayVisible)

        controller.toggleSessionPanel()
        #expect(controller.isSessionPanelVisible)
        #expect(!controller.isBubbleOverlayVisible)

        controller.toggleSessionPanel()
        #expect(!controller.isSessionPanelVisible)
        #expect(controller.isBubbleOverlayVisible)
    }

    @Test
    func clickInAnotherWindowDismissesThePanel() {
        let controller = SessionPanelController(store: SessionStore(sessions: .demo))
        let botPanel = NSPanel(
            contentRect: NSRect(x: 500, y: 500, width: 92, height: 92),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        let otherWindow = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 100, height: 100),
            styleMask: [.titled],
            backing: .buffered,
            defer: false
        )

        controller.toggle(relativeTo: botPanel)
        #expect(controller.isVisible)

        controller.handleLocalMouseDown(in: otherWindow, botPanel: botPanel)

        #expect(!controller.isVisible)
    }

    @Test
    func sessionPanelUsesContentDrivenHeightCappedAtFourRows() {
        #expect(
            SessionPanelLayout.size(sessionCount: 0)
                == NSSize(width: 404, height: 170)
        )
        #expect(
            SessionPanelLayout.size(sessionCount: 1)
                == NSSize(width: 404, height: 132)
        )
        #expect(
            SessionPanelLayout.size(sessionCount: 2)
                == NSSize(width: 404, height: 184)
        )
        #expect(
            SessionPanelLayout.size(sessionCount: 4)
                == NSSize(width: 404, height: 288)
        )
        #expect(
            SessionPanelLayout.size(sessionCount: 8)
                == NSSize(width: 404, height: 288)
        )
    }

    @Test
    func sessionPanelResizesWhenVisibleSessionCountChanges() {
        let store = SessionStore(sessions: .demo)
        let controller = SessionPanelController(store: store)
        #expect(controller.panelSize == NSSize(width: 404, height: 184))

        store.replaceSessions([store.sessions[0]])

        #expect(controller.panelSize == NSSize(width: 404, height: 132))
    }

    @Test
    func visibleSessionPanelFollowsItsBotAnchor() throws {
        let visibleFrame = try #require(NSScreen.main?.visibleFrame)
        let botPanel = FocusPreservingPanel(
            contentRect: NSRect(
                x: visibleFrame.minX + 520,
                y: visibleFrame.minY + 200,
                width: 104,
                height: 104
            ),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        let controller = SessionPanelController(
            store: SessionStore(sessions: .demo)
        )

        controller.toggle(relativeTo: botPanel)
        let initialFrame = controller.panelFrame
        #expect(controller.isAttached(to: botPanel))
        botPanel.setFrameOrigin(
            NSPoint(
                x: botPanel.frame.minX + 72,
                y: botPanel.frame.minY + 48
            )
        )
        #expect(controller.panelFrame.minX == initialFrame.minX + 72)
        #expect(controller.panelFrame.minY == initialFrame.minY + 48)

        controller.hide()
        #expect(!controller.isAttached(to: botPanel))
    }

    @Test
    func visibleOverlaySwitchesNativeAttachmentWithTheSessionPanel() {
        let store = SessionStore(sessions: [
            bubbleSession(id: "running", status: .running)
        ])
        let controller = BotWindowController(store: store)

        controller.show()
        #expect(controller.isBubbleOverlayAttachedToBot)
        #expect(!controller.isSessionPanelAttachedToBot)

        controller.toggleSessionPanel()
        #expect(!controller.isBubbleOverlayAttachedToBot)
        #expect(controller.isSessionPanelAttachedToBot)

        controller.toggleSessionPanel()
        #expect(controller.isBubbleOverlayAttachedToBot)
        #expect(!controller.isSessionPanelAttachedToBot)
    }

    @Test
    func floatingPanelsCannotTakeKeyboardFocusButSettingsCan() {
        let store = SessionStore(sessions: .demo)
        let botController = BotWindowController(store: store)
        let settingsController = SettingsWindowController(
            sessionStore: store,
            appearanceStore: PetAppearanceStore(),
            hookExecutableURL: URL(fileURLWithPath: "/tmp/CodingPetHook")
        )

        #expect(botController.floatingPanelsPreserveKeyboardFocus)
        #expect(!botController.bubbleOverlayIgnoresMouseEvents)
        #expect(settingsController.canBecomeKey)
    }

    @Test
    func bubblePanelShrinksToOnlyItsInteractiveContent() {
        let running = bubbleSession(id: "running", status: .running)
        let secondRunning = bubbleSession(id: "second", status: .running)
        let pending = bubbleSession(id: "pending", status: .needsInput)

        let empty = BotBubblePresentation(
            sessions: [],
            runningBubblesEnabled: true,
            pendingBubblesEnabled: true,
            readyBubblesEnabled: true
        )
        #expect(BotWindowController.bubblePanelSize(for: empty) == .zero)

        let oneFullBubble = BotBubblePresentation(
            sessions: [running],
            runningBubblesEnabled: true,
            pendingBubblesEnabled: true,
            readyBubblesEnabled: true
        )
        #expect(
            BotWindowController.bubblePanelSize(for: oneFullBubble)
                == NSSize(width: 328, height: 80)
        )

        let compactOnly = BotBubblePresentation(
            sessions: [pending],
            runningBubblesEnabled: false,
            pendingBubblesEnabled: false,
            readyBubblesEnabled: false
        )
        #expect(
            BotWindowController.bubblePanelSize(for: compactOnly)
                == NSSize(width: 72, height: 44)
        )

        let twoFullAndCompact = BotBubblePresentation(
            sessions: [running, secondRunning, pending],
            runningBubblesEnabled: true,
            pendingBubblesEnabled: false,
            readyBubblesEnabled: true
        )
        #expect(
            BotWindowController.bubblePanelSize(for: twoFullAndCompact)
                == NSSize(width: 328, height: 196)
        )

        let fourScrollableBubbles = BotBubblePresentation(
            sessions: [
                running,
                secondRunning,
                bubbleSession(id: "third", status: .ready),
                bubbleSession(id: "fourth", status: .ready)
            ],
            runningBubblesEnabled: true,
            pendingBubblesEnabled: true,
            readyBubblesEnabled: true
        )
        #expect(fourScrollableBubbles.sessions.count == 4)
        #expect(
            BotWindowController.bubblePanelSize(for: fourScrollableBubbles)
                == NSSize(width: 328, height: 152)
        )
    }

    @Test
    func scrollableBubblesNeverUseAPersistentSystemScroller() {
        let scrollView = BotBubbleScrollViewFactory.make()

        #expect(!scrollView.hasVerticalScroller)
        #expect(!scrollView.hasHorizontalScroller)
        #expect(scrollView.autohidesScrollers)
        #expect(scrollView.scrollerStyle == .overlay)
        #expect(!scrollView.drawsBackground)
        #expect(scrollView.backgroundColor.alphaComponent == 0)
        #expect(!scrollView.contentView.drawsBackground)
        #expect(scrollView.contentView.backgroundColor.alphaComponent == 0)
        #expect(scrollView.layer?.isOpaque == false)
        #expect(scrollView.contentView.layer?.isOpaque == false)
        #expect(scrollView.layer?.backgroundColor?.alpha == 0)
        #expect(scrollView.contentView.layer?.backgroundColor?.alpha == 0)
    }

    @Test
    func bubbleActivationNavigatesAndAcknowledgesReadySession() {
        let ready = bubbleSession(id: "ready", status: .ready)
        let store = SessionStore(sessions: [ready])
        var navigatedSessionID: String?
        var acknowledgedSessionID: String?
        let controller = BotWindowController(
            store: store,
            onAcknowledge: { acknowledgedSessionID = $0.id },
            navigateToSession: { navigatedSessionID = $0.id }
        )

        controller.handleBubbleActivation(ready)

        #expect(navigatedSessionID == ready.id)
        #expect(acknowledgedSessionID == ready.id)
        #expect(store.sessions.isEmpty)
    }

    @Test
    func claudeBubbleShowsNoticeWithoutNavigatingOrOpeningFinder() {
        let claude = AgentSession(
            id: "claude-code:session",
            provider: .claudeCode,
            projectName: "project",
            cwd: "/tmp/project",
            status: .running,
            summary: "Working",
            updatedAt: .now,
            terminal: nil
        )
        let store = SessionStore(sessions: [claude])
        var navigationCount = 0
        let controller = BotWindowController(
            store: store,
            navigateToSession: { _ in navigationCount += 1 }
        )

        controller.handleBubbleActivation(claude)

        #expect(navigationCount == 0)
        #expect(controller.isNavigationNoticeVisible)
        #expect(store.sessions == [claude])
    }

    @Test
    func claudePanelSelectionUsesUnavailableNoticeInsteadOfNavigation() {
        let claude = AgentSession(
            id: "claude-code:session",
            provider: .claudeCode,
            projectName: "project",
            cwd: "/tmp/project",
            status: .running,
            summary: "Working",
            updatedAt: .now,
            terminal: nil
        )
        let store = SessionStore(sessions: [claude])
        var navigationCount = 0
        var noticeCount = 0
        let controller = SessionPanelController(
            store: store,
            navigateToSession: { _ in navigationCount += 1 },
            onNavigationUnavailable: { _, _ in noticeCount += 1 }
        )

        controller.handleSessionActivation(claude)

        #expect(navigationCount == 0)
        #expect(noticeCount == 1)
        #expect(store.sessions == [claude])
    }

    @Test
    func navigationNoticePrefersTheLeftSideWithoutOverlappingItsAnchor() {
        let visibleFrame = NSRect(x: 0, y: 0, width: 1_440, height: 900)
        let anchorFrame = NSRect(x: 900, y: 320, width: 328, height: 152)

        let noticeFrame = SessionNavigationNoticeController.noticeFrame(
            beside: anchorFrame,
            visibleFrame: visibleFrame,
            preferredCenterY: 400
        )

        #expect(noticeFrame.maxX == anchorFrame.minX - 12)
        #expect(!noticeFrame.intersects(anchorFrame))
        #expect(visibleFrame.contains(noticeFrame))
    }

    @Test
    func navigationNoticeMovesRightWhenTheAnchorIsNearTheLeftEdge() {
        let visibleFrame = NSRect(x: 0, y: 0, width: 1_440, height: 900)
        let anchorFrame = NSRect(x: 20, y: 320, width: 404, height: 184)

        let noticeFrame = SessionNavigationNoticeController.noticeFrame(
            beside: anchorFrame,
            visibleFrame: visibleFrame,
            preferredCenterY: 400
        )

        #expect(noticeFrame.minX == anchorFrame.maxX + 12)
        #expect(!noticeFrame.intersects(anchorFrame))
        #expect(visibleFrame.contains(noticeFrame))
    }

    @Test
    func dismissingBubbleKeepsSessionAndDoesNotNavigate() {
        let running = bubbleSession(id: "running", status: .running)
        let store = SessionStore(sessions: [running])
        var navigationCount = 0
        let controller = BotWindowController(
            store: store,
            navigateToSession: { _ in navigationCount += 1 }
        )

        controller.handleBubbleDismissal(running)

        #expect(navigationCount == 0)
        #expect(store.sessions == [running])
        #expect(store.bubbleSessions.isEmpty)
    }

    @Test
    func closingOneOfTwoBubblesKeepsTheRemainingCardAboveThePet() {
        let first = bubbleSession(id: "first", status: .running)
        let second = bubbleSession(id: "second", status: .running)
        let store = SessionStore(sessions: [first, second])
        let controller = BotWindowController(store: store)
        controller.show()
        RunLoop.main.run(until: Date.now.addingTimeInterval(0.05))

        controller.handleBubbleDismissal(first)
        RunLoop.main.run(until: Date.now.addingTimeInterval(0.05))

        let overlay = controller.bubbleOverlayFrame
        let bot = controller.botWindowFrame
        let remainingCard = NSRect(
            x: overlay.minX + 12,
            y: overlay.minY + 8,
            width: 304,
            height: 64
        )
        #expect(overlay.size == NSSize(width: 328, height: 80))
        #expect(remainingCard.minY >= bot.maxY)
    }

    @Test
    func draggingBotDoesNotOpenPanelButFollowingClickDoes() {
        let controller = BotWindowController(store: SessionStore(sessions: .demo))

        controller.handleBotPointerDown(at: NSPoint(x: 100, y: 100))
        controller.handleBotPointerDragged(to: NSPoint(x: 130, y: 120))
        controller.handleBotPointerUp(at: NSPoint(x: 135, y: 125))
        controller.handleBotActivation()
        #expect(!controller.isSessionPanelVisible)

        controller.handleBotPointerDown(at: NSPoint(x: 135, y: 125))
        controller.handleBotPointerUp(at: NSPoint(x: 136, y: 125))
        controller.handleBotActivation()
        #expect(controller.isSessionPanelVisible)

        controller.toggleSessionPanel()
    }

    @Test
    func botPrefersTheScreenContainingTheMousePointer() throws {
        let screen = try #require(
            NSScreen.screens.first { $0.frame.contains(NSEvent.mouseLocation) }
        )

        #expect(BotWindowController.preferredScreen(at: NSEvent.mouseLocation) === screen)
    }

    @Test
    func bubbleOverlayStaysInsideTheVisibleScreenNearTheBot() {
        let visibleFrame = NSRect(x: 0, y: 0, width: 1440, height: 900)
        let botFrame = NSRect(x: 1300, y: 40, width: 104, height: 104)

        let bubbleFrame = BotWindowController.bubbleFrame(
            relativeTo: botFrame,
            visibleFrame: visibleFrame
        )

        #expect(visibleFrame.contains(bubbleFrame))
        #expect(bubbleFrame.maxX < botFrame.maxX)
        #expect(bubbleFrame.minY >= botFrame.maxY - 8)
    }

    @Test
    func changingBotSizeResizesItsWindowAroundTheSameCenter() {
        let suiteName = "SessionPanelControllerTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let appearanceStore = PetAppearanceStore(defaults: defaults)
        let controller = BotWindowController(
            store: SessionStore(),
            appearanceStore: appearanceStore
        )
        let originalCenter = NSPoint(
            x: controller.botWindowFrame.midX,
            y: controller.botWindowFrame.midY
        )

        for size in [64.0, 160.0, 72.0, 144.0, 84.0] {
            appearanceStore.setBotSize(size)

            let side = size + 20
            #expect(controller.botWindowFrame.size == NSSize(width: side, height: side))
            #expect(controller.botWindowFrame.midX == originalCenter.x)
            #expect(controller.botWindowFrame.midY == originalCenter.y)
        }
    }

    @Test
    func resizingNearAScreenEdgeDoesNotAccumulateDrift() {
        var frame = NSRect(x: 1390, y: 850, width: 104, height: 104)
        let originalCenter = NSPoint(x: frame.midX, y: frame.midY)

        for size in [64.0, 160.0, 68.0, 148.0, 84.0] {
            frame = BotWindowController.resizedBotFrame(
                from: frame,
                botSize: CGFloat(size)
            )

            #expect(frame.midX == originalCenter.x)
            #expect(frame.midY == originalCenter.y)
        }
    }

    private func bubbleSession(id: String, status: SessionStatus) -> AgentSession {
        AgentSession(
            id: "codex:\(id)",
            provider: .codex,
            projectName: id,
            cwd: "/tmp/\(id)",
            status: status,
            summary: status == .running ? "Working" : "Waiting",
            updatedAt: .now,
            terminal: nil
        )
    }
}
