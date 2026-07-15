import Foundation

actor CodexSessionNameResolver {
    struct Resolution: Equatable, Sendable {
        let name: String?
    }

    typealias Lookup = @Sendable (String) -> Resolution?

    private let lookup: Lookup
    private var cachedResolutions: [String: Resolution] = [:]

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
            return Self.extractResolution(from: result)
        }
    }

    init(lookup: @escaping Lookup) {
        self.lookup = lookup
    }

    func resolution(
        for sessionID: String,
        refresh: Bool = false
    ) async -> Resolution? {
        if !refresh, let cachedResolution = cachedResolutions[sessionID] {
            return cachedResolution
        }

        let lookup = self.lookup
        let resolution = await Task.detached(priority: .utility) {
            lookup(sessionID)
        }.value
        if let resolution {
            cachedResolutions[sessionID] = resolution
            return resolution
        }
        return cachedResolutions[sessionID]
    }

    func name(for sessionID: String, refresh: Bool = false) async -> String? {
        await resolution(for: sessionID, refresh: refresh)?.name
    }

    static func extractResolution(from result: [String: Any]) -> Resolution? {
        guard result["thread"] is [String: Any] else { return nil }
        return Resolution(name: extractName(from: result))
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
