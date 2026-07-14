import Foundation
import Testing
@testable import CodingPet

struct CodexThreadCatalogTests {
    @Test
    func collectsEveryNonArchivedThreadAcrossPages() async throws {
        let fake = FakeThreadCatalogSession(responses: [
            [
                "data": [["id": "a"], ["id": "b"]],
                "nextCursor": "page-2"
            ],
            [
                "data": [["id": "b"], ["id": "c"]],
                "nextCursor": NSNull()
            ]
        ])
        let catalog = CodexThreadCatalog(sessionFactory: { fake })

        let ids = await catalog.activeThreadIDs()

        #expect(ids == ["a", "b", "c"])
        #expect(fake.methods == ["thread/list", "thread/list"])
        #expect(fake.params[0]["archived"] as? Bool == false)
        #expect(fake.params[0]["useStateDbOnly"] as? Bool == true)
        #expect(fake.params[0]["cursor"] == nil)
        #expect(fake.params[1]["cursor"] as? String == "page-2")
    }

    @Test
    func malformedPageReturnsUnknownInsteadOfAnEmptyDestructiveResult() async {
        let fake = FakeThreadCatalogSession(responses: [["data": [["name": "missing-id"]]]])
        let catalog = CodexThreadCatalog(sessionFactory: { fake })

        #expect(await catalog.activeThreadIDs() == nil)
        #expect(fake.closeCount == 1)
    }

    @Test
    func repeatedCursorReturnsUnknownInsteadOfLoopingForever() async {
        let fake = FakeThreadCatalogSession(responses: [
            ["data": [["id": "a"]], "nextCursor": "same"],
            ["data": [["id": "b"]], "nextCursor": "same"]
        ])
        let catalog = CodexThreadCatalog(sessionFactory: { fake })

        #expect(await catalog.activeThreadIDs() == nil)
        #expect(fake.methods.count == 2)
    }

    @Test
    func returnsCompletionDateForTheLatestTerminalTurn() async {
        let fake = FakeThreadCatalogSession(responses: [[
            "thread": [
                "turns": [
                    ["status": "completed", "completedAt": 100],
                    ["status": "interrupted", "completedAt": 123]
                ]
            ]
        ]])
        let catalog = CodexThreadCatalog(sessionFactory: { fake })

        let completionDate = await catalog.latestTerminalTurnCompletionDate(
            threadID: "thread-id"
        )

        #expect(completionDate == Date(timeIntervalSince1970: 123))
        #expect(fake.methods == ["thread/read"])
        #expect(fake.params[0]["threadId"] as? String == "thread-id")
        #expect(fake.params[0]["includeTurns"] as? Bool == true)
    }

    @Test(arguments: ["inProgress", "interrupted"])
    func ignoresTurnsWithoutATerminalCompletionDate(status: String) async {
        let fake = FakeThreadCatalogSession(responses: [[
            "thread": ["turns": [["status": status]]]
        ]])
        let catalog = CodexThreadCatalog(sessionFactory: { fake })

        #expect(await catalog.latestTerminalTurnCompletionDate(
            threadID: "thread-id"
        ) == nil)
    }

    @Test
    func readsNarrowThreadMetadataWithoutTurns() async {
        let fake = FakeThreadCatalogSession(responses: [[
            "thread": [
                "id": "thread-id",
                "name": "  Ready task  ",
                "cwd": "/tmp/project",
                "updatedAt": 456
            ]
        ]])
        let catalog = CodexThreadCatalog(sessionFactory: { fake })

        let metadata = await catalog.metadata(threadID: "thread-id")

        #expect(metadata == CodexThreadMetadata(
            id: "thread-id",
            name: "Ready task",
            cwd: "/tmp/project",
            updatedAt: Date(timeIntervalSince1970: 456)
        ))
        #expect(fake.methods == ["thread/read"])
        #expect(fake.params[0]["includeTurns"] as? Bool == false)
    }
}

private final class FakeThreadCatalogSession: CodexAppServerSessionProtocol, @unchecked Sendable {
    enum Error: Swift.Error {
        case missingResponse
    }

    private let lock = NSLock()
    private var responses: [[String: Any]]
    private(set) var methods: [String] = []
    private(set) var params: [[String: Any]] = []
    private(set) var closeCount = 0

    init(responses: [[String: Any]]) {
        self.responses = responses
    }

    func call(method: String, params: [String: Any]) throws -> [String: Any] {
        lock.lock()
        defer { lock.unlock() }
        methods.append(method)
        self.params.append(params)
        guard !responses.isEmpty else { throw Error.missingResponse }
        return responses.removeFirst()
    }

    func close() {
        lock.lock()
        closeCount += 1
        lock.unlock()
    }
}
