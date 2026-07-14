import Foundation

actor CodexActivityMessageResolver {
    typealias SessionFactory = @Sendable () throws -> any CodexAppServerSessionProtocol

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

    func latestMessage(for threadID: String) -> String? {
        do {
            let result = try activeSession().call(
                method: "thread/read",
                params: ["threadId": threadID, "includeTurns": true]
            )
            return Self.extractLatestMessage(from: result)
        } catch {
            session?.close()
            session = nil
            return nil
        }
    }

    static func extractLatestMessage(from result: [String: Any]) -> String? {
        guard let thread = result["thread"] as? [String: Any],
              let turns = thread["turns"] as? [[String: Any]],
              let currentTurn = turns.last,
              let items = currentTurn["items"] as? [[String: Any]] else {
            return nil
        }

        for item in items.reversed() where item["type"] as? String == "agentMessage" {
            guard let rawText = item["text"] as? String else { continue }
            let message = rawText
                .split(whereSeparator: \Character.isWhitespace)
                .joined(separator: " ")
            guard !message.isEmpty else { continue }
            return String(message.prefix(240))
        }
        return nil
    }

    private func activeSession() throws -> any CodexAppServerSessionProtocol {
        if let session { return session }
        let newSession = try sessionFactory()
        session = newSession
        return newSession
    }
}
