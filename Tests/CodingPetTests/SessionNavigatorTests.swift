import Foundation
import Testing
@testable import CodingPet

@MainActor
struct SessionNavigatorTests {
    @Test
    func codexSessionBuildsExactThreadDeepLink() throws {
        let threadID = "019f5b3b-ab87-7d23-9f6e-e7e51c301158"
        var session = makeSession(id: "codex:\(threadID)", provider: .codex)
        session.codexThreadIsPersisted = true

        let url = try #require(SessionNavigator.codexThreadURL(for: session))

        #expect(url.absoluteString == "codex://threads/\(threadID)")
    }

    @Test
    func claudeCodeSessionDoesNotBuildCodexDeepLink() {
        let session = makeSession(
            id: "claude-code:019f5b3b-ab87-7d23-9f6e-e7e51c301158",
            provider: .claudeCode
        )

        #expect(SessionNavigator.codexThreadURL(for: session) == nil)
        #expect(!SessionNavigator.supportsDirectActivation(session))
    }

    @Test
    func onlyCodexSessionsSupportDirectActivation() {
        let codex = makeSession(id: "codex:not-a-thread-id", provider: .codex)
        let claude = makeSession(id: "claude-code:session", provider: .claudeCode)

        #expect(SessionNavigator.supportsDirectActivation(codex))
        #expect(!SessionNavigator.supportsDirectActivation(claude))
    }

    @Test
    func claudeDesktopSessionUsesClaudeApplication() {
        var session = makeSession(id: "claude-code:desktop", provider: .claudeCode)
        session.terminal = TerminalTarget(
            bundleIdentifier: "com.anthropic.claudefordesktop",
            processIdentifier: 100,
            tty: nil
        )

        #expect(SessionNavigator.supportsDirectActivation(session))
        #expect(SessionNavigator.preferredBundleIdentifier(for: session)
            == "com.anthropic.claudefordesktop")
    }

    @Test
    func claudeTerminalSessionUsesAllowlistedTerminalApplication() {
        var session = makeSession(id: "claude-code:terminal", provider: .claudeCode)
        session.terminal = TerminalTarget(
            bundleIdentifier: "com.apple.Terminal",
            processIdentifier: 101,
            tty: nil
        )

        #expect(SessionNavigator.supportsDirectActivation(session))
        #expect(SessionNavigator.preferredBundleIdentifier(for: session) == "com.apple.Terminal")
    }

    @Test
    func malformedCodexSessionIDDoesNotBuildDeepLink() {
        let session = makeSession(id: "codex:../../settings", provider: .codex)

        #expect(SessionNavigator.codexThreadURL(for: session) == nil)
    }

    @Test
    func unpersistedCodexSessionActivatesAppWithoutBuildingADeepLink() {
        let session = makeSession(
            id: "codex:019f5b3b-ab87-7d23-9f6e-e7e51c301158",
            provider: .codex
        )

        #expect(SessionNavigator.codexThreadURL(for: session) == nil)
        #expect(SessionNavigator.supportsDirectActivation(session))
        #expect(SessionNavigator.preferredBundleIdentifier(for: session) == "com.openai.codex")
    }

    private func makeSession(id: String, provider: AgentProvider) -> AgentSession {
        AgentSession(
            id: id,
            provider: provider,
            projectName: "coding-pet",
            cwd: "/Users/example/coding-pet",
            status: .running,
            summary: "Working",
            updatedAt: .now,
            terminal: nil
        )
    }
}
