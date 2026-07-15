import Foundation
import Testing
import CodingPetBridge
@testable import CodingPet

struct ProviderEventAdapterTests {
    @Test(arguments: [
        ("Codex/user-prompt-submit.json", HookProvider.codex, SessionStatus.running),
        ("Codex/permission-request.json", HookProvider.codex, SessionStatus.needsInput),
        ("Claude/user-prompt-submit.json", HookProvider.claudeCode, SessionStatus.running),
        ("Claude/permission-request.json", HookProvider.claudeCode, SessionStatus.needsInput),
        ("Claude/notification.json", HookProvider.claudeCode, SessionStatus.needsInput)
    ])
    func fixtureMapsToExpectedStatus(
        path: String,
        provider: HookProvider,
        expectedStatus: SessionStatus
    ) throws {
        let event = try fixtureEvent(path, provider: provider)

        let session = SessionEventRouter.session(for: event, existing: nil)

        #expect(session?.status == expectedStatus)
        #expect(session?.provider == (provider == .codex ? .codex : .claudeCode))
        #expect(session?.projectName == event.cwd.split(separator: "/").last.map(String.init))
        #expect(session?.summary.contains("private") == false)
    }

    @Test(arguments: [
        ("Codex/session-start.json", HookProvider.codex),
        ("Codex/stop.json", HookProvider.codex),
        ("Claude/session-start.json", HookProvider.claudeCode),
        ("Claude/stop-failure.json", HookProvider.claudeCode),
    ])
    func inactiveLifecycleFixturesDoNotCreateVisibleSessions(
        path: String,
        provider: HookProvider
    ) throws {
        let event = try fixtureEvent(path, provider: provider)

        #expect(SessionEventRouter.session(for: event, existing: nil) == nil)
    }

    @Test
    func claudeStopCreatesAReadySessionUntilItIsAcknowledged() throws {
        let event = try fixtureEvent("Claude/stop.json", provider: .claudeCode)

        let session = SessionEventRouter.session(for: event, existing: nil)

        #expect(event.clearsActiveSession == false)
        #expect(session?.provider == .claudeCode)
        #expect(session?.status == .ready)
        #expect(session?.summary == "Completed — ready to review")
    }

    @Test
    func unknownEventsAreIgnored() {
        let event = HookEventEnvelope(
            provider: .codex,
            eventName: "FutureEvent",
            timestamp: .now,
            parentProcessID: nil,
            sessionID: "future",
            cwd: "/tmp/project"
        )

        #expect(SessionEventRouter.session(for: event, existing: nil) == nil)
    }

    @Test(arguments: ["PreToolUse", "PostToolUse"])
    func toolActivityKeepsCodexSessionRunning(eventName: String) {
        let event = HookEventEnvelope(
            provider: .codex,
            eventName: eventName,
            timestamp: .now,
            parentProcessID: nil,
            sessionID: "working",
            cwd: "/tmp/project"
        )

        #expect(SessionEventRouter.session(for: event, existing: nil)?.status == .running)
    }

    @Test
    @MainActor
    func sessionStoreUpsertsByProviderAndSessionID() {
        let store = SessionStore()
        let codex = HookEventEnvelope(
            provider: .codex,
            eventName: "UserPromptSubmit",
            timestamp: .distantPast,
            parentProcessID: nil,
            sessionID: "same-id",
            cwd: "/tmp/codex"
        )
        let claude = HookEventEnvelope(
            provider: .claudeCode,
            eventName: "UserPromptSubmit",
            timestamp: .now,
            parentProcessID: nil,
            sessionID: "same-id",
            cwd: "/tmp/claude"
        )

        store.apply(codex)
        store.apply(claude)

        #expect(store.sessions.count == 2)
    }

    @Test
    @MainActor
    func sessionStoreExposesRunningInputAndUnreadReadyAsActive() {
        let sessions = [
            makeSession(id: "running", status: .running),
            makeSession(id: "input", status: .needsInput),
            makeSession(id: "ready", status: .ready),
            makeSession(id: "blocked", status: .blocked)
        ]
        let store = SessionStore(sessions: sessions)

        #expect(Set(store.activeSessions.map(\.id)) == ["running", "input", "ready"])
        #expect(Set(store.codexLifecycleSessions.map(\.id)) == ["running", "input"])
        #expect(store.attentionCount == 2)
        #expect(store.botState == .needsInput)
    }

    @Test
    @MainActor
    func dismissedRunningBubbleStaysHiddenUntilItBecomesAttentionWorthy() {
        let first = makeSession(id: "running", status: .running)
        let store = SessionStore(sessions: [first])

        store.dismissBubble(for: first)

        #expect(store.activeSessions == [first])
        #expect(store.bubbleSessions.isEmpty)

        var updated = first
        updated.summary = "New activity"
        updated.updatedAt = first.updatedAt.addingTimeInterval(1)
        store.upsert(updated)

        #expect(store.bubbleSessions.isEmpty)

        updated.status = .needsInput
        updated.summary = "Waiting for approval"
        updated.updatedAt = first.updatedAt.addingTimeInterval(2)
        store.upsert(updated)

        #expect(store.bubbleSessions == [updated])

        updated.status = .ready
        updated.summary = "Completed — unread activity"
        updated.updatedAt = first.updatedAt.addingTimeInterval(3)
        store.upsert(updated)

        #expect(store.bubbleSessions == [updated])
    }

    @Test
    @MainActor
    func codexUnreadProjectionCreatesAndRemovesOnlyReadyRows() {
        let running = makeSession(id: "codex:running", status: .running)
        let store = SessionStore(sessions: [running])

        #expect(store.reconcileCodexReadyThreadIDs(["running", "ready"]) == ["ready"])
        store.upsertCodexReadyThread(CodexThreadMetadata(
            id: "ready",
            name: "Unread task",
            cwd: "/tmp/project",
            updatedAt: Date(timeIntervalSince1970: 100)
        ))
        #expect(store.sessions.first { $0.providerSessionID == "ready" }?.status == .ready)
        #expect(store.sessions.first { $0.providerSessionID == "running" }?.status == .running)

        #expect(store.reconcileCodexReadyThreadIDs(["running"]).isEmpty)
        #expect(store.sessions.map(\.providerSessionID) == ["running"])
    }

    @Test
    @MainActor
    func acknowledgedReadyVersionStaysHiddenUntilANewerCompletion() throws {
        let store = SessionStore()
        let first = CodexThreadMetadata(
            id: "ready",
            name: "Unread task",
            cwd: "/tmp/project",
            updatedAt: Date(timeIntervalSince1970: 100)
        )
        store.upsertCodexReadyThread(first)
        let session = try #require(store.sessions.first)

        #expect(store.acknowledge(session))
        #expect(store.sessions.isEmpty)

        store.upsertCodexReadyThread(first)
        #expect(store.sessions.isEmpty)

        store.upsertCodexReadyThread(CodexThreadMetadata(
            id: first.id,
            name: first.name,
            cwd: first.cwd,
            updatedAt: Date(timeIntervalSince1970: 101)
        ))
        #expect(store.sessions.first?.status == .ready)
    }

    @Test
    @MainActor
    func idleBoundariesRemoveSessionsAndANewPromptCanReactivateThem() {
        let store = SessionStore()
        let now = Date.now
        let base = HookEventEnvelope(
            provider: .codex,
            eventName: "SessionStart",
            timestamp: now,
            parentProcessID: nil,
            sessionID: "resumable",
            cwd: "/tmp/project"
        )

        store.apply(base)
        #expect(store.activeSessions.isEmpty)

        store.apply(HookEventEnvelope(
            provider: base.provider,
            eventName: "UserPromptSubmit",
            timestamp: now.addingTimeInterval(1),
            parentProcessID: nil,
            sessionID: base.sessionID,
            cwd: base.cwd
        ))
        #expect(store.activeSessions.first?.status == .running)
        store.dismissBubble(for: store.activeSessions[0])
        #expect(store.bubbleSessions.isEmpty)

        store.apply(HookEventEnvelope(
            provider: base.provider,
            eventName: "Stop",
            timestamp: now.addingTimeInterval(2),
            parentProcessID: nil,
            sessionID: base.sessionID,
            cwd: base.cwd
        ))
        #expect(store.sessions.isEmpty)
        #expect(store.activeSessions.isEmpty)
        #expect(store.botState == .idle)

        store.apply(HookEventEnvelope(
            provider: base.provider,
            eventName: "UserPromptSubmit",
            timestamp: now.addingTimeInterval(3),
            parentProcessID: nil,
            sessionID: base.sessionID,
            cwd: base.cwd
        ))
        #expect(store.activeSessions.count == 1)
        #expect(store.activeSessions.first?.status == .running)
        #expect(store.bubbleSessions == store.activeSessions)
    }

    @Test
    @MainActor
    func explicitSessionNameOverridesProjectNameAndSurvivesLifecycleUpdates() {
        let store = SessionStore(sessions: [makeSession(id: "codex:named", status: .running)])
        store.updateSessionName("Review PR 5446", for: "codex:named")
        let existing = store.sessions[0]
        let event = HookEventEnvelope(
            provider: .codex,
            eventName: "PermissionRequest",
            timestamp: .now,
            parentProcessID: nil,
            sessionID: "named",
            cwd: "/tmp/today-cloud"
        )

        let updated = SessionEventRouter.session(for: event, existing: existing)

        #expect(existing.displayName == "Review PR 5446")
        #expect(updated?.sessionName == "Review PR 5446")
        #expect(updated?.displayName == "Review PR 5446")
        #expect(updated?.projectName == "today-cloud")
    }

    @Test
    func unnamedClaudeSessionDoesNotExposeItsDerivedProjectDirectoryAsATitle() {
        let claude = AgentSession(
            id: "claude-code:unnamed",
            provider: .claudeCode,
            projectName: "today-cloud",
            cwd: "/tmp/today-cloud",
            status: .running,
            summary: "Working",
            updatedAt: .now,
            terminal: nil
        )
        let codex = AgentSession(
            id: "codex:unnamed",
            provider: .codex,
            projectName: "today-cloud",
            cwd: "/tmp/today-cloud",
            status: .running,
            summary: "Working",
            updatedAt: .now,
            terminal: nil
        )

        #expect(claude.displayName == "Untitled session")
        #expect(codex.displayName == "today-cloud")
    }

    @Test
    @MainActor
    func latestMessageUpdatesOnlyTheMatchingRunningLifecycleEvent() {
        let timestamp = Date.now
        let store = SessionStore(sessions: [
            AgentSession(
                id: "codex:message",
                provider: .codex,
                projectName: "coding-pet",
                cwd: "/tmp/coding-pet",
                status: .running,
                summary: "Working",
                updatedAt: timestamp,
                terminal: nil
            )
        ])

        store.updateRunningSummary(
            "Planning the implementation",
            for: "codex:message",
            matching: timestamp
        )
        #expect(store.sessions.first?.summary == "Planning the implementation")

        let newerTimestamp = timestamp.addingTimeInterval(1)
        store.apply(HookEventEnvelope(
            provider: .codex,
            eventName: "PostToolUse",
            timestamp: newerTimestamp,
            parentProcessID: nil,
            sessionID: "message",
            cwd: "/tmp/coding-pet"
        ))
        store.updateRunningSummary(
            "Stale message",
            for: "codex:message",
            matching: timestamp
        )
        #expect(store.sessions.first?.summary == "Working")

        store.apply(HookEventEnvelope(
            provider: .codex,
            eventName: "PermissionRequest",
            timestamp: newerTimestamp.addingTimeInterval(1),
            parentProcessID: nil,
            sessionID: "message",
            cwd: "/tmp/coding-pet"
        ))
        store.updateRunningSummary(
            "Should not replace an input prompt",
            for: "codex:message",
            matching: newerTimestamp.addingTimeInterval(1)
        )
        #expect(store.sessions.first?.summary == "Waiting for permission")
    }

    @Test
    @MainActor
    func sessionEndRemovesAnExistingSessionAndOlderEventsCannotOverwriteNewerState() {
        let store = SessionStore()
        let now = Date.now
        store.apply(HookEventEnvelope(
            provider: .codex,
            eventName: "UserPromptSubmit",
            timestamp: now,
            parentProcessID: nil,
            sessionID: "ending",
            cwd: "/tmp/project"
        ))
        store.apply(HookEventEnvelope(
            provider: .codex,
            eventName: "Stop",
            timestamp: now.addingTimeInterval(-1),
            parentProcessID: nil,
            sessionID: "ending",
            cwd: "/tmp/project"
        ))
        #expect(store.sessions.first?.status == .running)

        store.apply(HookEventEnvelope(
            provider: .codex,
            eventName: "SessionEnd",
            timestamp: now.addingTimeInterval(1),
            parentProcessID: nil,
            sessionID: "ending",
            cwd: "/tmp/project"
        ))
        #expect(store.sessions.isEmpty)
    }

    @Test
    @MainActor
    func claudeStopBecomesReadyNewPromptRunsAndSessionEndRemovesIt() {
        let store = SessionStore()
        let now = Date.now
        let event: (String, TimeInterval) -> HookEventEnvelope = { name, offset in
            HookEventEnvelope(
                provider: .claudeCode,
                eventName: name,
                timestamp: now.addingTimeInterval(offset),
                parentProcessID: nil,
                sessionID: "claude-ready",
                cwd: "/tmp/project"
            )
        }

        store.apply(event("UserPromptSubmit", 0))
        #expect(store.sessions.first?.status == .running)

        store.apply(event("Stop", 1))
        #expect(store.sessions.first?.status == .ready)
        #expect(store.attentionCount == 1)

        store.apply(event("UserPromptSubmit", 2))
        #expect(store.sessions.first?.status == .running)

        store.apply(event("SessionEnd", 3))
        #expect(store.sessions.isEmpty)
    }

    @Test
    @MainActor
    func reconciliationRemovesOnlyMissingSessionsFromTheSelectedProvider() {
        let store = SessionStore(sessions: [
            AgentSession(
                id: "codex:active",
                provider: .codex,
                projectName: "active",
                cwd: "/tmp/active",
                status: .running,
                summary: "Working",
                updatedAt: .now,
                terminal: nil
            ),
            AgentSession(
                id: "codex:archived",
                provider: .codex,
                projectName: "archived",
                cwd: "/tmp/archived",
                status: .ready,
                summary: "Waiting for you",
                updatedAt: .now,
                terminal: nil
            ),
            AgentSession(
                id: "claude-code:archived",
                provider: .claudeCode,
                projectName: "claude",
                cwd: "/tmp/claude",
                status: .running,
                summary: "Working",
                updatedAt: .now,
                terminal: nil
            )
        ])

        let removed = store.removeSessions(provider: .codex, notIn: ["active"])

        #expect(removed.map(\.id) == ["codex:archived"])
        #expect(Set(store.sessions.map(\.id)) == ["codex:active", "claude-code:archived"])
    }

    @Test
    @MainActor
    func terminalTurnReconciliationCannotRemoveNewerHookActivity() {
        let oldTimestamp = Date(timeIntervalSince1970: 100)
        let newTimestamp = Date(timeIntervalSince1970: 200)
        let store = SessionStore(sessions: [
            AgentSession(
                id: "codex:session",
                provider: .codex,
                projectName: "project",
                cwd: "/tmp/project",
                status: .running,
                summary: "Working",
                updatedAt: newTimestamp,
                terminal: nil
            )
        ])

        #expect(store.removeSession(
            provider: .codex,
            providerSessionID: "session",
            notUpdatedAfter: oldTimestamp
        ) == nil)
        #expect(store.activeSessions.count == 1)

        #expect(store.removeSession(
            provider: .codex,
            providerSessionID: "session",
            notUpdatedAfter: newTimestamp
        )?.id == "codex:session")
        #expect(store.activeSessions.isEmpty)
    }

    private func fixtureEvent(_ path: String, provider: HookProvider) throws -> HookEventEnvelope {
        let resourceURL = try #require(Bundle.module.resourceURL)
        let url = resourceURL.appending(path: "Fixtures/\(path)")
        return try HookEventSanitizer.sanitize(
            Data(contentsOf: url),
            provider: provider,
            timestamp: Date(timeIntervalSince1970: 1_700_000_000),
            parentProcessID: 123
        )
    }

    private func makeSession(id: String, status: SessionStatus) -> AgentSession {
        AgentSession(
            id: id,
            provider: .codex,
            projectName: "project",
            cwd: "/tmp/project",
            status: status,
            summary: "Test",
            updatedAt: .now,
            terminal: nil
        )
    }
}
