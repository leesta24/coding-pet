import Foundation

actor ClaudeSessionNameResolver {
    typealias Lookup = @Sendable (_ sessionID: String, _ processID: Int32?) -> String?

    private static let maximumActiveMetadataFileSize = 64 * 1_024
    private static let maximumDesktopMetadataFileSize = 512 * 1_024
    private static let maximumDesktopMetadataFileCount = 4_096
    private static let maximumFocusLogReadSize = 2 * 1_024 * 1_024
    private static let desktopIndexRefreshInterval: TimeInterval = 2
    private static let focusLogMarker =
        "[CCD] LocalSessions.setFocusedSession: sessionId="

    private let lookup: Lookup
    private let desktopSessionsDirectory: URL?
    private let focusedSessionLogURL: URL?
    private var cachedNames: [String: String] = [:]
    private var desktopIndex: [String: ClaudeDesktopSessionIndexEntry]?
    private var desktopIndexUpdatedAt = Date.distantPast
    private var focusedSessionState: ClaudeFocusedSessionState?
    private var focusLogOffset: UInt64 = 0
    private var focusLogFileNumber: UInt64?

    init(homeDirectory: URL = FileManager.default.homeDirectoryForCurrentUser) {
        let sessionsDirectory = homeDirectory
            .appending(path: ".claude", directoryHint: .isDirectory)
            .appending(path: "sessions", directoryHint: .isDirectory)
        desktopSessionsDirectory = homeDirectory
            .appending(path: "Library/Application Support/Claude", directoryHint: .isDirectory)
            .appending(path: "claude-code-sessions", directoryHint: .isDirectory)
        focusedSessionLogURL = homeDirectory
            .appending(path: "Library/Logs/Claude/main.log")
        lookup = { sessionID, processID in
            Self.lookupName(
                sessionID: sessionID,
                processID: processID,
                sessionsDirectory: sessionsDirectory
            )
        }
    }

    init(lookup: @escaping Lookup) {
        self.lookup = lookup
        desktopSessionsDirectory = nil
        focusedSessionLogURL = nil
    }

    func name(
        for sessionID: String,
        processID: Int32?,
        refresh: Bool = false
    ) async -> String? {
        if !refresh, let cachedName = cachedNames[sessionID] {
            return cachedName
        }

        if let desktopSessionsDirectory,
           let desktopName = await desktopName(
               for: sessionID,
               sessionsDirectory: desktopSessionsDirectory,
               refresh: refresh
           ) {
            cachedNames[sessionID] = desktopName
            return desktopName
        }

        let lookup = self.lookup
        let resolvedName = await Task.detached(priority: .utility) {
            lookup(sessionID, processID)
        }.value
        if let resolvedName {
            cachedNames[sessionID] = resolvedName
            return resolvedName
        }
        return cachedNames[sessionID]
    }

    /// Claude Desktop considers the currently selected session read even when
    /// its persisted focus timestamp predates the latest activity. The local
    /// focus event is therefore authoritative; timestamps remain the fallback
    /// for sessions that were selected after completion.
    func isReadySessionRead(
        sessionID: String,
        completedAt: Date
    ) async -> Bool? {
        guard let desktopSessionsDirectory,
              let entry = await desktopEntry(
                  for: sessionID,
                  sessionsDirectory: desktopSessionsDirectory,
                  refresh: true
              ) else {
            return nil
        }
        if entry.isArchived {
            return true
        }
        if let desktopSessionID = entry.desktopSessionID,
           await focusedDesktopSessionID() == desktopSessionID {
            return true
        }
        guard let lastActivityAt = entry.lastActivityAt,
              let lastFocusedAt = entry.lastFocusedAt else {
            return false
        }
        let completedAtMilliseconds = completedAt.timeIntervalSince1970 * 1_000
        return lastFocusedAt >= lastActivityAt
            && lastFocusedAt >= completedAtMilliseconds
    }

    private func desktopName(
        for sessionID: String,
        sessionsDirectory: URL,
        refresh: Bool
    ) async -> String? {
        guard let entry = await desktopEntry(
            for: sessionID,
            sessionsDirectory: sessionsDirectory,
            refresh: refresh
        ),
              !entry.isArchived else {
            return nil
        }
        return entry.title
    }

    private func desktopEntry(
        for sessionID: String,
        sessionsDirectory: URL,
        refresh: Bool
    ) async -> ClaudeDesktopSessionIndexEntry? {
        if let entry = desktopIndex?[sessionID] {
            guard refresh else { return entry }
            let sourceURL = entry.sourceURL
            let refreshedMetadata = await Task.detached(priority: .utility) {
                Self.desktopMetadata(at: sourceURL)
            }.value
            guard let refreshedMetadata,
                  refreshedMetadata.cliSessionID == sessionID else {
                return entry
            }
            let refreshedEntry = ClaudeDesktopSessionIndexEntry(
                title: Self.normalizedDesktopTitle(refreshedMetadata.title)
                    ?? entry.title,
                sourceURL: sourceURL,
                desktopSessionID: refreshedMetadata.sessionID
                    ?? entry.desktopSessionID,
                lastActivityAt: refreshedMetadata.lastActivityAt,
                lastFocusedAt: refreshedMetadata.lastFocusedAt,
                isArchived: refreshedMetadata.isArchived == true
            )
            desktopIndex?[sessionID] = refreshedEntry
            return refreshedEntry
        }

        let now = Date()
        guard desktopIndex == nil
                || now.timeIntervalSince(desktopIndexUpdatedAt)
                    >= Self.desktopIndexRefreshInterval else {
            return nil
        }
        let rebuiltIndex = await Task.detached(priority: .utility) {
            Self.buildDesktopIndex(sessionsDirectory: sessionsDirectory)
        }.value
        desktopIndex = rebuiltIndex
        desktopIndexUpdatedAt = now
        return rebuiltIndex[sessionID]
    }

    nonisolated static func lookupName(
        sessionID: String,
        processID: Int32?,
        sessionsDirectory: URL,
        fileManager: FileManager = .default
    ) -> String? {
        var candidates: [URL] = []
        if let processID {
            candidates.append(sessionsDirectory.appending(path: "\(processID).json"))
        }

        if let urls = try? fileManager.contentsOfDirectory(
            at: sessionsDirectory,
            includingPropertiesForKeys: [.isRegularFileKey, .isSymbolicLinkKey, .fileSizeKey],
            options: [.skipsHiddenFiles]
        ) {
            candidates.append(contentsOf: urls.filter {
                $0.pathExtension == "json" && !candidates.contains($0)
            })
        }

        for candidate in candidates {
            guard let metadata = metadata(at: candidate, fileManager: fileManager),
                  metadata.sessionID == sessionID,
                  let name = normalizedName(
                    metadata.name,
                    nameSource: metadata.nameSource
                  ) else {
                continue
            }
            return name
        }
        return nil
    }

    private nonisolated static func metadata(
        at url: URL,
        fileManager: FileManager
    ) -> ClaudeActiveSessionMetadata? {
        guard let values = try? url.resourceValues(forKeys: [
            .isRegularFileKey,
            .isSymbolicLinkKey,
            .fileSizeKey
        ]),
              values.isRegularFile == true,
              values.isSymbolicLink != true,
              let fileSize = values.fileSize,
              fileSize > 0,
              fileSize <= maximumActiveMetadataFileSize,
              let data = try? Data(contentsOf: url, options: [.mappedIfSafe]) else {
            return nil
        }
        return try? JSONDecoder().decode(ClaudeActiveSessionMetadata.self, from: data)
    }

    private nonisolated static func buildDesktopIndex(
        sessionsDirectory: URL,
        fileManager: FileManager = .default
    ) -> [String: ClaudeDesktopSessionIndexEntry] {
        guard let enumerator = fileManager.enumerator(
            at: sessionsDirectory,
            includingPropertiesForKeys: [
                .isRegularFileKey,
                .isSymbolicLinkKey,
                .fileSizeKey
            ],
            options: [.skipsHiddenFiles, .skipsPackageDescendants]
        ) else {
            return [:]
        }

        var index: [String: ClaudeDesktopSessionIndexEntry] = [:]
        var visitedItemCount = 0
        while let candidate = enumerator.nextObject() as? URL {
            visitedItemCount += 1
            guard visitedItemCount <= maximumDesktopMetadataFileCount else {
                break
            }
            guard candidate.pathExtension == "json" else { continue }
            guard let metadata = desktopMetadata(
                at: candidate,
                fileManager: fileManager
            ) else {
                continue
            }

            let entry = ClaudeDesktopSessionIndexEntry(
                title: normalizedDesktopTitle(metadata.title),
                sourceURL: candidate,
                desktopSessionID: metadata.sessionID,
                lastActivityAt: metadata.lastActivityAt,
                lastFocusedAt: metadata.lastFocusedAt,
                isArchived: metadata.isArchived == true
            )
            if let existing = index[metadata.cliSessionID],
               existing.lastActivityAt ?? 0 > entry.lastActivityAt ?? 0 {
                continue
            }
            index[metadata.cliSessionID] = entry
        }
        return index
    }

    private nonisolated static func desktopMetadata(
        at url: URL,
        fileManager: FileManager = .default
    ) -> ClaudeDesktopSessionMetadata? {
        guard let values = try? url.resourceValues(forKeys: [
            .isRegularFileKey,
            .isSymbolicLinkKey,
            .fileSizeKey
        ]),
              values.isRegularFile == true,
              values.isSymbolicLink != true,
              let fileSize = values.fileSize,
              fileSize > 0,
              fileSize <= maximumDesktopMetadataFileSize,
              let data = try? Data(contentsOf: url, options: [.mappedIfSafe]) else {
            return nil
        }
        return try? JSONDecoder().decode(ClaudeDesktopSessionMetadata.self, from: data)
    }

    private func focusedDesktopSessionID() async -> String? {
        guard let focusedSessionLogURL else { return nil }
        let previousOffset = focusLogOffset
        let previousFileNumber = focusLogFileNumber
        let result = await Task.detached(priority: .utility) {
            Self.readFocusedSessionState(
                logURL: focusedSessionLogURL,
                previousOffset: previousOffset,
                previousFileNumber: previousFileNumber
            )
        }.value
        guard let result else { return focusedSessionState?.sessionID }

        focusLogOffset = result.endOffset
        focusLogFileNumber = result.fileNumber
        if result.didReset, result.latestState == nil {
            focusedSessionState = nil
        } else if let latestState = result.latestState {
            focusedSessionState = latestState
        }
        return focusedSessionState?.sessionID
    }

    private nonisolated static func readFocusedSessionState(
        logURL: URL,
        previousOffset: UInt64,
        previousFileNumber: UInt64?,
        fileManager: FileManager = .default
    ) -> ClaudeFocusLogReadResult? {
        guard let values = try? logURL.resourceValues(forKeys: [
            .isRegularFileKey,
            .isSymbolicLinkKey
        ]),
              values.isRegularFile == true,
              values.isSymbolicLink != true,
              let attributes = try? fileManager.attributesOfItem(
                  atPath: logURL.path
              ),
              let rawFileSize = attributes[.size] as? NSNumber else {
            return nil
        }

        let fileSize = rawFileSize.uint64Value
        let fileNumber = (attributes[.systemFileNumber] as? NSNumber)?.uint64Value
        let didReset = (previousFileNumber != nil && fileNumber != previousFileNumber)
            || fileSize < previousOffset
        let canContinue = previousOffset > 0 && !didReset
        let startOffset = canContinue
            ? previousOffset
            : fileSize > UInt64(maximumFocusLogReadSize)
                ? fileSize - UInt64(maximumFocusLogReadSize)
                : 0
        let byteCount = Int(min(
            fileSize - startOffset,
            UInt64(maximumFocusLogReadSize)
        ))
        guard byteCount > 0 else {
            return ClaudeFocusLogReadResult(
                latestState: nil,
                endOffset: fileSize,
                fileNumber: fileNumber,
                didReset: didReset
            )
        }

        guard let handle = try? FileHandle(forReadingFrom: logURL) else {
            return nil
        }
        defer { try? handle.close() }
        do {
            try handle.seek(toOffset: startOffset)
            guard let data = try handle.read(upToCount: byteCount),
                  let text = String(data: data, encoding: .utf8) else {
                return nil
            }
            return ClaudeFocusLogReadResult(
                latestState: latestFocusedSessionState(in: text),
                endOffset: startOffset + UInt64(data.count),
                fileNumber: fileNumber,
                didReset: didReset
            )
        } catch {
            return nil
        }
    }

    private nonisolated static func latestFocusedSessionState(
        in text: String
    ) -> ClaudeFocusedSessionState? {
        for line in text.split(whereSeparator: \.isNewline).reversed() {
            guard let markerRange = line.range(of: focusLogMarker) else {
                continue
            }
            let rawValue = line[markerRange.upperBound...]
                .split(whereSeparator: \.isWhitespace)
                .first
                .map(String.init)
            guard let rawValue else { continue }
            if rawValue == "null" {
                return ClaudeFocusedSessionState.none
            }
            guard rawValue.count <= 64,
                  rawValue.hasPrefix("local_"),
                  UUID(uuidString: String(rawValue.dropFirst(6))) != nil else {
                continue
            }
            return .session(rawValue)
        }
        return nil
    }

    private nonisolated static func normalizedName(
        _ rawName: String?,
        nameSource: String?
    ) -> String? {
        guard nameSource != "derived", let rawName else { return nil }
        let name = rawName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty else { return nil }
        return String(name.prefix(256))
    }

    private nonisolated static func normalizedDesktopTitle(
        _ rawTitle: String?
    ) -> String? {
        guard let rawTitle else { return nil }
        let title = rawTitle.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !title.isEmpty else { return nil }
        return String(title.prefix(256))
    }
}

private struct ClaudeDesktopSessionIndexEntry: Sendable {
    let title: String?
    let sourceURL: URL
    let desktopSessionID: String?
    let lastActivityAt: Double?
    let lastFocusedAt: Double?
    let isArchived: Bool
}

private struct ClaudeDesktopSessionMetadata: Decodable, Sendable {
    let sessionID: String?
    let cliSessionID: String
    let title: String?
    let isArchived: Bool?
    let lastActivityAt: Double?
    let lastFocusedAt: Double?

    enum CodingKeys: String, CodingKey {
        case sessionID = "sessionId"
        case cliSessionID = "cliSessionId"
        case title
        case isArchived
        case lastActivityAt
        case lastFocusedAt
    }
}

private enum ClaudeFocusedSessionState: Sendable, Equatable {
    case session(String)
    case none

    var sessionID: String? {
        switch self {
        case let .session(sessionID): sessionID
        case .none: nil
        }
    }
}

private struct ClaudeFocusLogReadResult: Sendable {
    let latestState: ClaudeFocusedSessionState?
    let endOffset: UInt64
    let fileNumber: UInt64?
    let didReset: Bool
}

private struct ClaudeActiveSessionMetadata: Decodable {
    let sessionID: String
    let name: String?
    let nameSource: String?

    enum CodingKeys: String, CodingKey {
        case sessionID = "sessionId"
        case name
        case nameSource
    }
}
