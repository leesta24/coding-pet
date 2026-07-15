import AppKit
import SwiftUI
import Testing
@testable import CodingPet

@MainActor
struct PetAppearanceRenderingTests {
    @Test
    func rendersClaudeSessionNavigationNotice() throws {
        let preview = SessionNavigationNoticeView()
            .background(Color(red: 0.88, green: 0.90, blue: 0.94))
            .environment(\.colorScheme, .light)

        let pngData = try renderPNG(preview)

        #expect(pngData.count > 5_000)
        if let outputPath = ProcessInfo.processInfo.environment[
            "CODINGPET_NAVIGATION_NOTICE_PREVIEW_PATH"
        ] {
            try pngData.write(to: URL(filePath: outputPath), options: .atomic)
        }
    }

    @Test
    func rendersAllAppearancesAndTheSessionPanel() throws {
        let suiteName = "PetAppearanceRenderingTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defer { defaults.removePersistentDomain(forName: suiteName) }

        let store = SessionStore(sessions: .demo)
        let appearanceStore = PetAppearanceStore(defaults: defaults)
        let preview = HStack(alignment: .top, spacing: 28) {
            VStack(alignment: .leading, spacing: 18) {
                Text("CodingPet companions")
                    .font(.system(size: 22, weight: .bold, design: .rounded))

                ForEach(appearanceStore.availableAppearances) { appearance in
                    HStack(spacing: 16) {
                        PetAvatarView(
                            appearance: appearance,
                            state: .needsInput,
                            size: 108
                        )
                        VStack(alignment: .leading, spacing: 4) {
                            Text(appearance.displayName)
                                .font(.system(size: 16, weight: .bold, design: .rounded))
                            Text(appearance.accessibilityName)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                }
            }
            .frame(width: 270, alignment: .leading)

            SessionPanelView { _ in }
                .environmentObject(store)
                .environmentObject(appearanceStore)
        }
        .padding(32)
        .background(Color(red: 0.055, green: 0.065, blue: 0.09))
        .environment(\.colorScheme, .dark)

        let pngData = try renderPNG(preview)

        #expect(pngData.count > 10_000)

        if let outputPath = ProcessInfo.processInfo.environment["CODINGPET_PREVIEW_PATH"] {
            try pngData.write(to: URL(filePath: outputPath), options: .atomic)
        }
    }

    @Test
    func rendersTheAppearanceSettingsPage() throws {
        let suiteName = "PetAppearanceRenderingTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let temporaryHome = FileManager.default.temporaryDirectory
            .appending(path: "codingpet-settings-preview-\(UUID().uuidString)")
        let integrationStore = IntegrationSettingsStore(
            coordinator: HookInstallationCoordinator(
                homeDirectory: temporaryHome,
                hookExecutableURL: temporaryHome.appending(path: "CodingPetHook")
            )
        )

        let preview = SettingsView()
            .environmentObject(SessionStore(sessions: .demo))
            .environmentObject(PetAppearanceStore(defaults: defaults))
            .environmentObject(SessionBubbleSettingsStore(defaults: defaults))
            .environmentObject(integrationStore)
            .environment(\.colorScheme, .light)

        let pngData = try renderPNG(preview)
        #expect(pngData.count > 10_000)

        if let outputPath = ProcessInfo.processInfo.environment["CODINGPET_SETTINGS_PREVIEW_PATH"] {
            try pngData.write(to: URL(filePath: outputPath), options: .atomic)
        }
    }

    @Test
    func rendersIndependentIntegrationControls() throws {
        let temporaryHome = FileManager.default.temporaryDirectory
            .appending(path: "codingpet-integrations-preview-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: temporaryHome) }
        let hookURL = temporaryHome.appending(path: "CodingPetHook")
        let codexInstaller = HookConfigurationInstaller(
            provider: .codex,
            configURL: temporaryHome.appending(path: ".codex/hooks.json"),
            hookExecutableURL: hookURL
        )
        let claudeInstaller = HookConfigurationInstaller(
            provider: .claudeCode,
            configURL: temporaryHome.appending(path: ".claude/settings.json"),
            hookExecutableURL: hookURL
        )
        try codexInstaller.install()
        try claudeInstaller.install()
        let integrationStore = IntegrationSettingsStore(
            coordinator: HookInstallationCoordinator(
                homeDirectory: temporaryHome,
                hookExecutableURL: hookURL
            )
        )
        integrationStore.refresh()

        let preview = IntegrationSettingsView()
            .environmentObject(SessionStore(sessions: .demo))
            .environmentObject(integrationStore)
            .frame(width: 582, height: 700)
            .background(Color(nsColor: .windowBackgroundColor))
            .environment(\.colorScheme, .light)

        let pngData = try renderPNG(preview)
        #expect(pngData.count > 10_000)

        if let outputPath = ProcessInfo.processInfo.environment["CODINGPET_INTEGRATIONS_PREVIEW_PATH"] {
            try pngData.write(to: URL(filePath: outputPath), options: .atomic)
        }
    }

    @Test
    func rendersBundledPetsAcrossAllSessionStates() throws {
        let preview = VStack(spacing: 20) {
            ForEach([PetAppearance.xiaobao]) { appearance in
                HStack(spacing: 20) {
                    ForEach(BotState.allPreviewStates, id: \.rawValue) { state in
                        VStack(spacing: 8) {
                            PetAvatarView(
                                appearance: appearance,
                                state: state,
                                size: 112,
                                animationsEnabled: false
                            )
                            Text(state.rawValue)
                                .font(.caption.bold())
                        }
                    }
                }
            }
        }
        .padding(24)
        .background(Color(red: 0.055, green: 0.065, blue: 0.09))
        .foregroundStyle(.white)

        let pngData = try renderPNG(preview)
        #expect(pngData.count > 10_000)

        if let outputPath = ProcessInfo.processInfo.environment["CODINGPET_PET_STATES_PATH"] {
            try pngData.write(to: URL(filePath: outputPath), options: .atomic)
        }
    }

    @Test
    func rendersFullAndCompactSessionBubbles() throws {
        let fullSuiteName = "PetAppearanceRenderingTests.full.\(UUID().uuidString)"
        let compactSuiteName = "PetAppearanceRenderingTests.compact.\(UUID().uuidString)"
        let fullDefaults = UserDefaults(suiteName: fullSuiteName)!
        let compactDefaults = UserDefaults(suiteName: compactSuiteName)!
        defer {
            fullDefaults.removePersistentDomain(forName: fullSuiteName)
            compactDefaults.removePersistentDomain(forName: compactSuiteName)
        }

        let fullSettings = SessionBubbleSettingsStore(defaults: fullDefaults)
        let compactSettings = SessionBubbleSettingsStore(defaults: compactDefaults)
        compactSettings.runningBubblesEnabled = false
        compactSettings.pendingBubblesEnabled = false
        compactSettings.readyBubblesEnabled = false

        let preview = HStack(alignment: .top, spacing: 34) {
            bubblePreview(
                title: "Conversation bubbles",
                settings: fullSettings
            )
            bubblePreview(
                title: "Compact attention count",
                settings: compactSettings
            )
        }
        .padding(28)
        .background(Color(red: 0.91, green: 0.92, blue: 0.94))

        let pngData = try renderPNG(preview)
        #expect(pngData.count > 10_000)

        if let outputPath = ProcessInfo.processInfo.environment["CODINGPET_BUBBLES_PREVIEW_PATH"] {
            try pngData.write(to: URL(filePath: outputPath), options: .atomic)
        }
    }

    @Test
    func rendersScrollableReadyBubbleViewport() throws {
        let suiteName = "PetAppearanceRenderingTests.scrollable-bubbles.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defer { defaults.removePersistentDomain(forName: suiteName) }

        let sessions = (0..<4).map { index in
            AgentSession(
                id: "codex:ready-\(index)",
                provider: .codex,
                projectName: "Ready task \(index + 1)",
                cwd: "/tmp/coding-pet",
                status: .ready,
                summary: "Completed — unread activity",
                updatedAt: .now.addingTimeInterval(TimeInterval(-index)),
                terminal: nil
            )
        }
        let presentation = BotBubblePresentation(
            sessions: sessions,
            runningBubblesEnabled: true,
            pendingBubblesEnabled: true,
            readyBubblesEnabled: true
        )
        let size = BotWindowController.bubblePanelSize(for: presentation)
        let preview = BotSessionBubbleView()
            .environmentObject(SessionStore(sessions: sessions))
            .environmentObject(SessionBubbleSettingsStore(defaults: defaults))
            .environmentObject(PetAppearanceStore(defaults: defaults))
            .frame(width: size.width, height: size.height)
            .background(
                LinearGradient(
                    colors: [
                        Color(red: 0.84, green: 0.91, blue: 0.98),
                        Color(red: 0.98, green: 0.88, blue: 0.91)
                    ],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
            )
            .environment(\.colorScheme, .light)

        let pngData = try renderHostedPNG(preview, size: size)
        #expect(presentation.sessions.count == 4)
        #expect(size == NSSize(width: 328, height: 152))
        #expect(pngData.count > 10_000)

        if let outputPath = ProcessInfo.processInfo.environment[
            "CODINGPET_SCROLLABLE_BUBBLES_PREVIEW_PATH"
        ] {
            try pngData.write(to: URL(filePath: outputPath), options: .atomic)
        }
    }

    @Test
    func rendersCompactSessionFirstPanelWithFourVisibleRows() throws {
        let store = SessionStore(sessions: [
            panelSession(
                id: "codex:approval",
                name: "Review PR 5446",
                provider: .codex,
                status: .needsInput,
                summary: "Waiting for approval",
                age: 12
            ),
            panelSession(
                id: "claude:tests",
                name: "Run regression tests",
                provider: .claudeCode,
                status: .needsInput,
                summary: "Waiting for you",
                age: 38
            ),
            panelSession(
                id: "codex:pet",
                name: "Polish session card",
                provider: .codex,
                status: .running,
                summary: "Working",
                age: 54
            ),
            panelSession(
                id: "codex:hooks",
                name: "Verify hook install",
                provider: .codex,
                status: .running,
                summary: "Working",
                age: 82
            ),
            panelSession(
                id: "claude:docs",
                name: "Update handoff",
                provider: .claudeCode,
                status: .running,
                summary: "Working",
                age: 120
            ),
        ])
        let preview = SessionPanelView { _ in }
            .environmentObject(store)
            .environment(\.colorScheme, .light)

        let pngData = try renderHostedPNG(
            preview,
            size: SessionPanelLayout.size(sessionCount: store.activeSessions.count)
        )
        #expect(pngData.count > 10_000)

        if let outputPath = ProcessInfo.processInfo.environment[
            "CODINGPET_SESSION_PANEL_PREVIEW_PATH"
        ] {
            try pngData.write(to: URL(filePath: outputPath), options: .atomic)
        }
    }

    @Test
    func rendersAdaptiveTwoRowSessionPanel() throws {
        let store = SessionStore(sessions: .demo)
        let usage = CodexUsageSnapshot(windows: [
            .init(label: "5h", remainingPercent: 72, resetsAt: nil),
            .init(label: "Week", remainingPercent: 61, resetsAt: nil)
        ])
        let preview = SessionPanelView(usageSnapshot: usage) { _ in }
            .environmentObject(store)
            .environment(\.colorScheme, .light)

        let pngData = try renderHostedPNG(
            preview,
            size: SessionPanelLayout.size(sessionCount: store.activeSessions.count)
        )
        #expect(pngData.count > 10_000)

        if let outputPath = ProcessInfo.processInfo.environment[
            "CODINGPET_TWO_ROW_PANEL_PREVIEW_PATH"
        ] {
            try pngData.write(to: URL(filePath: outputPath), options: .atomic)
        }
    }

    @Test
    func rendersSessionBubbleSettingsPage() throws {
        let suiteName = "PetAppearanceRenderingTests.bubble-settings.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defer { defaults.removePersistentDomain(forName: suiteName) }

        let preview = SessionBubbleSettingsView()
            .environmentObject(SessionBubbleSettingsStore(defaults: defaults))
            .frame(width: 582, height: 700)
            .background(Color(nsColor: .windowBackgroundColor))
            .environment(\.colorScheme, .light)

        let pngData = try renderPNG(preview)
        #expect(pngData.count > 10_000)

        if let outputPath = ProcessInfo.processInfo.environment["CODINGPET_BUBBLE_SETTINGS_PREVIEW_PATH"] {
            try pngData.write(to: URL(filePath: outputPath), options: .atomic)
        }
    }

    private func bubblePreview(
        title: String,
        settings: SessionBubbleSettingsStore
    ) -> some View {
        VStack(spacing: 0) {
            Text(title)
                .font(.system(size: 15, weight: .bold, design: .rounded))
                .foregroundStyle(Color.black.opacity(0.72))
                .padding(.bottom, 8)

            BotSessionBubbleView()
                .environmentObject(SessionStore(sessions: bubblePreviewSessions))
                .environmentObject(settings)
                .environmentObject(PetAppearanceStore())
                .frame(width: 340, height: 220)

            PetAvatarView(
                appearance: .xiaobao,
                state: .needsInput,
                size: 104,
                animationsEnabled: false
            )
            .offset(x: 108, y: -8)
        }
        .frame(width: 360)
    }

    private var bubblePreviewSessions: [AgentSession] {
        [
            AgentSession(
                id: "codex:approval-preview",
                provider: .codex,
                projectName: "Review PR 5446",
                cwd: "/tmp/coding-pet",
                status: .needsInput,
                summary: "Waiting for approval",
                updatedAt: .now,
                terminal: nil
            ),
            AgentSession(
                id: "claude-code:running-preview",
                provider: .claudeCode,
                projectName: "比较 review skill 差异",
                cwd: "/tmp/coding-pet",
                status: .ready,
                summary: "Completed — ready to review",
                updatedAt: .now.addingTimeInterval(-1),
                terminal: nil
            )
        ]
    }

    private func panelSession(
        id: String,
        name: String,
        provider: AgentProvider,
        status: SessionStatus,
        summary: String,
        age: TimeInterval
    ) -> AgentSession {
        AgentSession(
            id: id,
            provider: provider,
            projectName: "coding-pet",
            sessionName: name,
            cwd: FileManager.default.currentDirectoryPath,
            status: status,
            summary: summary,
            updatedAt: .now.addingTimeInterval(-age),
            terminal: nil
        )
    }

    private func renderPNG<Content: View>(_ content: Content) throws -> Data {
        let renderer = ImageRenderer(content: content)
        renderer.scale = 2
        let image = try #require(renderer.nsImage)
        let tiffData = try #require(image.tiffRepresentation)
        let bitmap = try #require(NSBitmapImageRep(data: tiffData))
        return try #require(bitmap.representation(using: .png, properties: [:]))
    }

    private func renderHostedPNG<Content: View>(
        _ content: Content,
        size: NSSize
    ) throws -> Data {
        let hostingView = NSHostingView(rootView: content)
        hostingView.frame = NSRect(origin: .zero, size: size)
        hostingView.layoutSubtreeIfNeeded()
        hostingView.displayIfNeeded()
        let bitmap = try #require(
            hostingView.bitmapImageRepForCachingDisplay(in: hostingView.bounds)
        )
        hostingView.cacheDisplay(in: hostingView.bounds, to: bitmap)
        return try #require(bitmap.representation(using: .png, properties: [:]))
    }
}

private extension BotState {
    static let allPreviewStates: [Self] = [.idle, .running, .needsInput, .ready, .blocked]
}
