import Foundation

/// Reads only Codex App's local unread-thread index. This is a secondary,
/// read-only projection used to distinguish Ready from ordinary completed/idle
/// threads; hooks remain the primary lifecycle integration.
///
/// Newer Codex builds keep the index in the top-level
/// `electron-thread-read-state-v1` store, keyed by account identity and host
/// (`local:<hash>`); older builds kept `unread-thread-ids-by-host-v1` inside
/// the persisted atom state. Both are understood.
actor CodexUnreadStateReader {
    private static let maximumStateFileSize = 4 * 1024 * 1024
    private static let maximumUnreadThreadCount = 10_000

    private let stateURL: URL

    init(stateURL: URL? = nil) {
        self.stateURL = stateURL ?? Self.defaultStateURL
    }

    func localUnreadThreadIDs() -> Set<String>? {
        guard let values = try? stateURL.resourceValues(forKeys: [
            .isRegularFileKey,
            .fileSizeKey
        ]),
              values.isRegularFile == true,
              let fileSize = values.fileSize,
              fileSize > 0,
              fileSize <= Self.maximumStateFileSize,
              let data = try? Data(contentsOf: stateURL),
              let state = try? JSONDecoder().decode(GlobalState.self, from: data) else {
            return nil
        }

        let threadIDs: [String]
        if let readState = state.threadReadState {
            threadIDs = readState.unreadByIdentity?.values.flatMap { hosts in
                hosts.filter { Self.isLocalHost($0.key) }.values.flatMap { $0 }
            } ?? []
        } else if let unreadByHost = state.persistedAtomState?.unreadThreadIDsByHost {
            threadIDs = unreadByHost["local"] ?? []
        } else {
            return nil
        }

        guard threadIDs.count <= Self.maximumUnreadThreadCount,
              threadIDs.allSatisfy({ !$0.isEmpty && $0.count <= 256 }) else {
            return nil
        }
        return Set(threadIDs)
    }

    private static func isLocalHost(_ key: String) -> Bool {
        key == "local" || key.hasPrefix("local:")
    }

    private static var defaultStateURL: URL {
        let home: URL
        if let configuredHome = ProcessInfo.processInfo.environment["CODEX_HOME"],
           !configuredHome.isEmpty {
            home = URL(fileURLWithPath: configuredHome, isDirectory: true)
        } else {
            home = FileManager.default.homeDirectoryForCurrentUser
                .appending(path: ".codex", directoryHint: .isDirectory)
        }
        return home.appending(path: ".codex-global-state.json")
    }

    private struct GlobalState: Decodable {
        let persistedAtomState: PersistedAtomState?
        let threadReadState: ThreadReadState?

        enum CodingKeys: String, CodingKey {
            case persistedAtomState = "electron-persisted-atom-state"
            case threadReadState = "electron-thread-read-state-v1"
        }
    }

    private struct PersistedAtomState: Decodable {
        let unreadThreadIDsByHost: [String: [String]]?

        enum CodingKeys: String, CodingKey {
            case unreadThreadIDsByHost = "unread-thread-ids-by-host-v1"
        }
    }

    private struct ThreadReadState: Decodable {
        /// identity key → host key → unread thread ids
        let unreadByIdentity: [String: [String: [String]]]?
    }
}
