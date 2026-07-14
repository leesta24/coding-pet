import Foundation

struct CodexThreadMetadata: Equatable, Sendable {
    let id: String
    let name: String?
    let cwd: String
    let updatedAt: Date
}

actor CodexThreadCatalog {
    typealias SessionFactory = @Sendable () throws -> any CodexAppServerSessionProtocol

    private enum CatalogError: Swift.Error {
        case malformedResponse
        case repeatedCursor
    }

    private let sessionFactory: SessionFactory
    private var session: (any CodexAppServerSessionProtocol)?

    init(codexExecutableURL: URL? = nil) {
        sessionFactory = {
            let executableURL = try codexExecutableURL
                ?? CodexHookTrustManager.resolveCodexExecutable()
            return try CodexAppServerSession(executableURL: executableURL)
        }
    }

    init(sessionFactory: @escaping SessionFactory) {
        self.sessionFactory = sessionFactory
    }

    func activeThreadIDs() -> Set<String>? {
        do {
            return try fetchActiveThreadIDs(session: try activeSession())
        } catch {
            resetSession()
            return nil
        }
    }

    /// Returns the completion time of the latest terminal turn. This is a
    /// secondary lifecycle signal for Codex App cancellations that do not emit
    /// a Stop or SessionEnd hook. Turn items and message content are not
    /// inspected or retained.
    func latestTerminalTurnCompletionDate(threadID: String) -> Date? {
        do {
            let result = try activeSession().call(
                method: "thread/read",
                params: [
                    "threadId": threadID,
                    "includeTurns": true
                ]
            )
            guard let thread = result["thread"] as? [String: Any],
                  let turns = thread["turns"] as? [[String: Any]],
                  let latestTurn = turns.last,
                  let status = latestTurn["status"] as? String,
                  Self.terminalTurnStatuses.contains(status),
                  let completedAt = latestTurn["completedAt"] as? NSNumber else {
                return nil
            }
            return Date(timeIntervalSince1970: completedAt.doubleValue)
        } catch {
            resetSession()
            return nil
        }
    }

    func metadata(threadID: String) -> CodexThreadMetadata? {
        do {
            let result = try activeSession().call(
                method: "thread/read",
                params: [
                    "threadId": threadID,
                    "includeTurns": false
                ]
            )
            guard let thread = result["thread"] as? [String: Any],
                  let id = thread["id"] as? String,
                  id == threadID,
                  let cwd = thread["cwd"] as? String,
                  !cwd.isEmpty,
                  let updatedAt = thread["updatedAt"] as? NSNumber else {
                return nil
            }
            let rawName = (thread["name"] as? String)?
                .trimmingCharacters(in: .whitespacesAndNewlines)
            let name = rawName.flatMap {
                $0.isEmpty ? nil : String($0.prefix(256))
            }
            return CodexThreadMetadata(
                id: id,
                name: name,
                cwd: cwd,
                updatedAt: Date(timeIntervalSince1970: updatedAt.doubleValue)
            )
        } catch {
            resetSession()
            return nil
        }
    }

    private func activeSession() throws -> any CodexAppServerSessionProtocol {
        if let session { return session }
        let newSession = try sessionFactory()
        session = newSession
        return newSession
    }

    private func resetSession() {
        session?.close()
        session = nil
    }

    private static let terminalTurnStatuses: Set<String> = [
        "completed",
        "interrupted",
        "failed"
    ]

    private func fetchActiveThreadIDs(
        session: any CodexAppServerSessionProtocol
    ) throws -> Set<String> {
        var threadIDs: Set<String> = []
        var cursor: String?
        var seenCursors: Set<String> = []

        repeat {
            var params: [String: Any] = [
                "archived": false,
                "limit": 100,
                "sortKey": "updated_at",
                "sortDirection": "desc",
                "useStateDbOnly": true
            ]
            if let cursor { params["cursor"] = cursor }
            let result = try session.call(method: "thread/list", params: params)
            guard let threads = result["data"] as? [[String: Any]] else {
                throw CatalogError.malformedResponse
            }
            for thread in threads {
                guard let id = thread["id"] as? String, !id.isEmpty else {
                    throw CatalogError.malformedResponse
                }
                threadIDs.insert(id)
            }

            let nextCursor: String?
            if let rawCursor = result["nextCursor"], !(rawCursor is NSNull) {
                guard let value = rawCursor as? String, !value.isEmpty else {
                    throw CatalogError.malformedResponse
                }
                nextCursor = value
            } else {
                nextCursor = nil
            }
            if let nextCursor,
               !seenCursors.insert(nextCursor).inserted {
                throw CatalogError.repeatedCursor
            }
            cursor = nextCursor
        } while cursor != nil

        return threadIDs
    }
}
