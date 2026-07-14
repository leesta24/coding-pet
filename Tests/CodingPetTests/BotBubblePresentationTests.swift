import Foundation
import Testing
@testable import CodingPet

struct BotBubblePresentationTests {
    @Test
    func enabledBubblesPrioritizeAllSessionsWithoutTruncatingScrollableRows() {
        let sessions = [
            makeSession(id: "running-new", status: .running, updatedAt: 40),
            makeSession(id: "pending-old", status: .needsInput, updatedAt: 10),
            makeSession(id: "pending-new", status: .needsInput, updatedAt: 30),
            makeSession(id: "ready", status: .ready, updatedAt: 50)
        ]

        let presentation = BotBubblePresentation(
            sessions: sessions,
            runningBubblesEnabled: true,
            pendingBubblesEnabled: true,
            readyBubblesEnabled: true
        )

        #expect(
            presentation.sessions.map(\.id)
                == ["pending-new", "pending-old", "ready", "running-new"]
        )
        #expect(presentation.compactAttentionCount == 0)
    }

    @Test
    func moreThanTwoReadySessionsRemainAvailableToTheBubbleScroller() {
        let presentation = BotBubblePresentation(
            sessions: [
                makeSession(id: "ready-old", status: .ready, updatedAt: 10),
                makeSession(id: "ready-new", status: .ready, updatedAt: 30),
                makeSession(id: "ready-middle", status: .ready, updatedAt: 20)
            ],
            runningBubblesEnabled: true,
            pendingBubblesEnabled: true,
            readyBubblesEnabled: true
        )

        #expect(
            presentation.sessions.map(\.id)
                == ["ready-new", "ready-middle", "ready-old"]
        )
    }

    @Test
    func disabledPendingCompactsOnlyPendingWhileReadyAndRunningRemainVisible() {
        let sessions = [
            makeSession(id: "pending-one", status: .needsInput, updatedAt: 30),
            makeSession(id: "pending-two", status: .needsInput, updatedAt: 20),
            makeSession(id: "ready", status: .ready, updatedAt: 15),
            makeSession(id: "running", status: .running, updatedAt: 10)
        ]

        let presentation = BotBubblePresentation(
            sessions: sessions,
            runningBubblesEnabled: true,
            pendingBubblesEnabled: false,
            readyBubblesEnabled: true
        )

        #expect(presentation.sessions.map(\.id) == ["ready", "running"])
        #expect(presentation.compactAttentionCount == 2)
    }

    @Test
    func readyUsesTheAttentionBubblePreferenceAndPrecedesRunning() {
        let sessions = [
            makeSession(id: "running", status: .running, updatedAt: 20),
            makeSession(id: "ready", status: .ready, updatedAt: 10)
        ]

        let presentation = BotBubblePresentation(
            sessions: sessions,
            runningBubblesEnabled: true,
            pendingBubblesEnabled: true,
            readyBubblesEnabled: true
        )

        #expect(presentation.sessions.map(\.id) == ["ready", "running"])
    }

    @Test
    func disabledReadyCompactsOnlyReadyWhilePendingRemainsVisible() {
        let presentation = BotBubblePresentation(
            sessions: [
                makeSession(id: "pending", status: .needsInput, updatedAt: 20),
                makeSession(id: "ready", status: .ready, updatedAt: 10)
            ],
            runningBubblesEnabled: true,
            pendingBubblesEnabled: true,
            readyBubblesEnabled: false
        )

        #expect(presentation.sessions.map(\.id) == ["pending"])
        #expect(presentation.compactAttentionCount == 1)
    }

    @Test
    func disabledRunningIsCompletelyHidden() {
        let presentation = BotBubblePresentation(
            sessions: [makeSession(id: "running", status: .running, updatedAt: 10)],
            runningBubblesEnabled: false,
            pendingBubblesEnabled: false,
            readyBubblesEnabled: false
        )

        #expect(presentation.sessions.isEmpty)
        #expect(presentation.compactAttentionCount == 0)
    }

    private func makeSession(
        id: String,
        status: SessionStatus,
        updatedAt: TimeInterval
    ) -> AgentSession {
        AgentSession(
            id: id,
            provider: .codex,
            projectName: id,
            cwd: "/tmp/\(id)",
            status: status,
            summary: status == .needsInput ? "Waiting for your input" : "Working",
            updatedAt: Date(timeIntervalSince1970: updatedAt)
        )
    }
}
