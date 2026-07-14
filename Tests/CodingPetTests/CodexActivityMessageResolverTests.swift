import Foundation
import Testing
@testable import CodingPet

struct CodexActivityMessageResolverTests {
    @Test
    func readsLatestAgentMessageFromOnlyTheCurrentTurn() async throws {
        let session = FakeActivityMessageSession(result: [
            "thread": [
                "turns": [
                    ["items": [[
                        "type": "agentMessage",
                        "phase": "final_answer",
                        "text": "Old completed answer"
                    ]]],
                    ["items": [
                        [
                            "type": "agentMessage",
                            "phase": "commentary",
                            "text": "Planning the first approach"
                        ],
                        ["type": "commandExecution", "command": "swift test"],
                        [
                            "type": "agentMessage",
                            "phase": "commentary",
                            "text": "  Planning hybrid single-agent\nwith optional parallel mode  "
                        ]
                    ]]
                ]
            ]
        ])
        let resolver = CodexActivityMessageResolver(sessionFactory: { session })

        let message = await resolver.latestMessage(for: "thread-1")

        #expect(message == "Planning hybrid single-agent with optional parallel mode")
        let call = try #require(session.calls().first)
        #expect(call.method == "thread/read")
        #expect(call.params["threadId"] as? String == "thread-1")
        #expect(call.params["includeTurns"] as? Bool == true)
    }

    @Test
    func doesNotReuseAnAgentMessageFromAPreviousTurn() async {
        let session = FakeActivityMessageSession(result: [
            "thread": [
                "turns": [
                    ["items": [["type": "agentMessage", "text": "Old answer"]]],
                    ["items": [["type": "commandExecution", "command": "swift test"]]]
                ]
            ]
        ])
        let resolver = CodexActivityMessageResolver(sessionFactory: { session })

        #expect(await resolver.latestMessage(for: "thread-1") == nil)
    }

    @Test
    func malformedResponsesFailClosedWithoutThrowing() async {
        let session = FakeActivityMessageSession(result: ["thread": ["turns": "invalid"]])
        let resolver = CodexActivityMessageResolver(sessionFactory: { session })

        #expect(await resolver.latestMessage(for: "thread-1") == nil)
    }
}

private final class FakeActivityMessageSession: @unchecked Sendable, CodexAppServerSessionProtocol {
    struct RecordedCall {
        let method: String
        let params: [String: Any]
    }

    private let lock = NSLock()
    private let result: [String: Any]
    private var recordedCalls: [RecordedCall] = []

    init(result: [String: Any]) {
        self.result = result
    }

    func call(method: String, params: [String: Any]) throws -> [String: Any] {
        lock.withLock {
            recordedCalls.append(RecordedCall(method: method, params: params))
        }
        return result
    }

    func close() {}

    func calls() -> [RecordedCall] {
        lock.withLock { recordedCalls }
    }
}
