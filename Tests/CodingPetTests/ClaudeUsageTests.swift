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
    func readerUsesTheKeychainTokenAndParsesTheUsageEndpoint() async throws {
        let credentials = Data(#"{"claudeAiOauth":{"accessToken":"tok-1","expiresAt":32503680000000}}"#.utf8)
        let requests = RequestLog()
        let reader = ClaudeUsageReader(
            credentialProvider: { credentials },
            loader: { request in
                await requests.record(request)
                return (Data("""
                {"five_hour":{"utilization":23.5,"resets_at":"2026-09-14T09:00:00Z"},
                 "seven_day":{"utilization":41.2,"resets_at":"2026-09-20T00:00:00.000Z"},
                 "seven_day_opus":null}
                """.utf8), 200)
            }
        )

        let snapshot = try #require(await reader.snapshot())

        #expect(snapshot.windows.map(\.label) == ["5h", "Week"])
        #expect(snapshot.windows.map(\.remainingPercent) == [76, 59])
        #expect(snapshot.windows[1].resetsAt == Date(timeIntervalSince1970: 1789862400))
        let request = try #require(await requests.requests.first)
        #expect(request.url == ClaudeUsageReader.usageURL)
        #expect(request.value(forHTTPHeaderField: "Authorization") == "Bearer tok-1")
        #expect(request.value(forHTTPHeaderField: "anthropic-beta") == "oauth-2025-04-20")
    }

    @Test
    func readerSkipsExpiredOrMissingTokensAndFailedResponses() async {
        let expired = Data(#"{"claudeAiOauth":{"accessToken":"old","expiresAt":1000}}"#.utf8)
        #expect(ClaudeUsageReader.accessToken(from: expired) == nil)
        let mcpOnly = Data(#"{"mcpOAuth":{}}"#.utf8)
        #expect(ClaudeUsageReader.accessToken(from: mcpOnly) == nil)

        let requests = RequestLog()
        let noToken = ClaudeUsageReader(
            credentialProvider: { expired },
            loader: { request in
                await requests.record(request)
                return (Data(), 200)
            }
        )
        #expect(await noToken.snapshot() == nil)
        #expect(await requests.requests.isEmpty)

        let rateLimited = ClaudeUsageReader(
            credentialProvider: { Data(#"{"claudeAiOauth":{"accessToken":"tok"}}"#.utf8) },
            loader: { _ in (Data(#"{"error":"rate_limit"}"#.utf8), 429) }
        )
        #expect(await rateLimited.snapshot() == nil)
    }

    @Test
    func storeRefreshIsThrottledAndKeepsTheLastSnapshotOnFailure() async throws {
        let counter = RequestLog()
        let store = ClaudeUsageStore(reader: CountingReader(log: counter))

        store.refresh(now: Date(timeIntervalSince1970: 0))
        store.refresh(now: Date(timeIntervalSince1970: 10))
        await store.refreshTask?.value
        #expect(await counter.requests.count == 1)
        #expect(store.snapshot?.windows.first?.remainingPercent == 90)

        store.refresh(now: Date(timeIntervalSince1970: 100))
        await store.refreshTask?.value
        #expect(await counter.requests.count == 2)
        #expect(store.snapshot?.windows.first?.remainingPercent == 90)
    }

    /// Answers once, then fails, so the store must keep its last good value.
    private struct CountingReader: ClaudeUsageReading {
        let log: RequestLog

        func snapshot() async -> UsageSnapshot? {
            await log.record(URLRequest(url: ClaudeUsageReader.usageURL))
            return await log.requests.count == 1
                ? UsageSnapshot(windows: [.init(label: "5h", remainingPercent: 90, resetsAt: nil)])
                : nil
        }
    }

    private actor RequestLog {
        private(set) var requests: [URLRequest] = []
        func record(_ request: URLRequest) { requests.append(request) }
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
