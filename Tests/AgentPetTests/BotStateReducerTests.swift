import Foundation
import Testing
@testable import AgentPet

struct BotStateReducerTests {
    @Test
    func emptySessionsAreIdle() {
        #expect(BotStateReducer.reduce([AgentSession]()) == .idle)
    }

    @Test
    func needsInputHasHighestPriority() {
        let sessions = [
            makeSession(id: "running", status: .running),
            makeSession(id: "blocked", status: .blocked),
            makeSession(id: "input", status: .needsInput)
        ]

        #expect(BotStateReducer.reduce(sessions) == .needsInput)
    }

    @Test
    func blockedWinsOverReadyAndRunning() {
        let sessions = [
            makeSession(id: "ready", status: .ready),
            makeSession(id: "blocked", status: .blocked),
            makeSession(id: "running", status: .running)
        ]

        #expect(BotStateReducer.reduce(sessions) == .blocked)
    }

    private func makeSession(id: String, status: SessionStatus) -> AgentSession {
        AgentSession(
            id: id,
            provider: .codex,
            projectName: "project",
            cwd: "/tmp/project",
            status: status,
            summary: "Test",
            updatedAt: Date(timeIntervalSince1970: 0),
            terminal: nil
        )
    }
}

