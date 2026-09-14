import Foundation
import Testing
@testable import CodingPet
import CodingPetBridge

@MainActor
struct ClaudeUsageTests {
    private let statusLineJSON = Data("""
    {
      "session_id": "abc-123",
      "cwd": "/Users/me/project",
      "model": {"id": "claude-opus-5", "display_name": "Opus"},
      "rate_limits": {
        "five_hour": {"used_percentage": 23.5, "resets_at": 1738425600},
        "seven_day": {"used_percentage": 41.2, "resets_at": 1738857600},
        "spend_limit": {"used_percentage": 62.8, "resets_at": 1740787200}
      }
    }
    """.utf8)

    @Test
    func statusLinePayloadBecomesAStatusLineEnvelopeWithUsageWindows() throws {
        let event = try #require(StatusLinePayloadParser.envelope(from: statusLineJSON))

        #expect(event.isStatusLine)
        #expect(event.provider == .claudeCode)
        #expect(event.sessionID == "abc-123")
        #expect(event.rateLimits?.fiveHour?.usedPercentage == 23.5)
        #expect(event.rateLimits?.sevenDay?.resetsAt == Date(timeIntervalSince1970: 1738857600))
        #expect(event.rateLimits?.spendLimit?.usedPercentage == 62.8)

        let roundTripped = try HookEventCodec.decode(HookEventCodec.encode(event))
        #expect(roundTripped.rateLimits == event.rateLimits)
    }

    @Test
    func payloadsWithoutUsageWindowsProduceNoEnvelope() {
        let withoutLimits = Data(#"{"session_id":"x","cwd":"/","model":{"id":"m"}}"#.utf8)
        #expect(StatusLinePayloadParser.envelope(from: withoutLimits) == nil)
        #expect(StatusLinePayloadParser.envelope(from: Data("not json".utf8)) == nil)
    }

    @Test
    func storeShowsRemainingPercentForTheFiveHourAndWeeklyWindows() throws {
        let store = ClaudeUsageStore()
        #expect(store.snapshot == nil)

        store.apply(try #require(StatusLinePayloadParser.envelope(from: statusLineJSON)))

        #expect(store.snapshot?.windows.map(\.label) == ["5h", "Week"])
        #expect(store.snapshot?.windows.map(\.remainingPercent) == [76, 59])
    }

    @Test
    func storeIgnoresOrdinaryHookEvents() {
        let store = ClaudeUsageStore()
        store.apply(HookEventEnvelope(
            provider: .claudeCode,
            eventName: "Stop",
            timestamp: .now,
            parentProcessID: nil,
            sessionID: "s",
            cwd: "/"
        ))
        #expect(store.snapshot == nil)
    }

    @Test
    func detailLineDropsSummariesThatRepeatTheStatusAndFormatsElapsedCompactly() {
        var session = AgentSession(
            id: "claude-code:x",
            provider: .claudeCode,
            projectName: "p",
            cwd: "/",
            status: .running,
            summary: "Working",
            updatedAt: .now,
            terminal: nil
        )
        #expect(SessionDetailFormatter.meaningfulSummary(for: session) == nil)
        session.summary = "Editing files"
        #expect(SessionDetailFormatter.meaningfulSummary(for: session) == "Editing files")
        session.status = .needsInput
        session.summary = "Waiting"
        #expect(SessionDetailFormatter.meaningfulSummary(for: session) == nil)

        let start = Date(timeIntervalSince1970: 0)
        #expect(SessionDetailFormatter.elapsedText(from: start, to: start.addingTimeInterval(12)) == "12s")
        #expect(SessionDetailFormatter.elapsedText(from: start, to: start.addingTimeInterval(157)) == "2m 37s")
        #expect(SessionDetailFormatter.elapsedText(from: start, to: start.addingTimeInterval(3_900)) == "1h 05m")
        #expect(SessionDetailFormatter.elapsedText(from: start, to: start.addingTimeInterval(200_000)) == "2d")
    }

    @Test
    func panelReservesAUsageRowOnlyWhenUsageIsShown() {
        let plain = SessionPanelLayout.size(sessionCount: 2)
        let withUsage = SessionPanelLayout.size(sessionCount: 2, showsUsage: true)
        #expect(withUsage.height == plain.height + SessionPanelLayout.usageRowHeight)
        #expect(withUsage.width == plain.width)
    }
}
