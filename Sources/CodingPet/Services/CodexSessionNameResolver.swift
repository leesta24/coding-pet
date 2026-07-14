import Foundation

actor CodexSessionNameResolver {
    typealias Lookup = @Sendable (String) -> String?

    private let lookup: Lookup
    private var cachedNames: [String: String] = [:]

    init(codexExecutableURL: URL? = nil) {
        lookup = { sessionID in
            let session: CodexAppServerSession
            do {
                let executableURL = try codexExecutableURL
                    ?? CodexHookTrustManager.resolveCodexExecutable()
                session = try CodexAppServerSession(executableURL: executableURL)
            } catch {
                return nil
            }
            defer { session.close() }

            guard let result = try? session.call(
                method: "thread/read",
                params: ["threadId": sessionID, "includeTurns": false]
            ) else {
                return nil
            }
            return Self.extractName(from: result)
        }
    }

    init(lookup: @escaping Lookup) {
        self.lookup = lookup
    }

    func name(for sessionID: String, refresh: Bool = false) async -> String? {
        if !refresh, let cachedName = cachedNames[sessionID] {
            return cachedName
        }

        let lookup = self.lookup
        let resolvedName = await Task.detached(priority: .utility) {
            lookup(sessionID)
        }.value
        if let resolvedName {
            cachedNames[sessionID] = resolvedName
            return resolvedName
        }
        return cachedNames[sessionID]
    }

    static func extractName(from result: [String: Any]) -> String? {
        guard let thread = result["thread"] as? [String: Any],
              let rawName = thread["name"] as? String else {
            return nil
        }
        let name = rawName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty else { return nil }
        return String(name.prefix(256))
    }
}
