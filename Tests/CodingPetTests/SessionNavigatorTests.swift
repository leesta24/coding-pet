import Foundation
import Testing
@testable import CodingPet

@MainActor
struct SessionNavigatorTests {
    @Test
    func codexSessionBuildsExactThreadDeepLink() throws {
        let threadID = "019f5b3b-ab87-7d23-9f6e-e7e51c301158"
        let session = makeSession(id: "codex:\(threadID)", provider: .codex)

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
    func malformedCodexSessionIDDoesNotBuildDeepLink() {
        let session = makeSession(id: "codex:../../settings", provider: .codex)

        #expect(SessionNavigator.codexThreadURL(for: session) == nil)
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
