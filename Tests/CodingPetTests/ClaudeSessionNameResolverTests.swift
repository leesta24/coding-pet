import Foundation
import Testing
@testable import CodingPet

struct ClaudeSessionNameResolverTests {
    @Test
    func mapsClaudeDesktopTitlesByCLISessionIDInsteadOfSharedDirectory() async throws {
        let temporaryHome = FileManager.default.temporaryDirectory
            .appending(path: "claude-desktop-session-name-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: temporaryHome) }
        let desktopSessionsDirectory = temporaryHome
            .appending(
                path: "Library/Application Support/Claude/claude-code-sessions/account/environment",
                directoryHint: .isDirectory
            )
        let activeSessionsDirectory = temporaryHome
            .appending(path: ".claude/sessions", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(
            at: desktopSessionsDirectory,
            withIntermediateDirectories: true
        )
        try FileManager.default.createDirectory(
            at: activeSessionsDirectory,
            withIntermediateDirectories: true
        )

        let sharedDirectory = "/Users/example/Dev/today-cloud"
        let runningMetadataURL = desktopSessionsDirectory
            .appending(path: "local-running.json")
        try Data(
            #"{"sessionId":"local-running","cliSessionId":"running","title":"QA card multi-page support","cwd":"\#(sharedDirectory)","isArchived":false,"lastActivityAt":200}"#.utf8
        ).write(to: runningMetadataURL)
        try Data(
            #"{"sessionId":"local-other","cliSessionId":"other","title":"Untitled session","cwd":"\#(sharedDirectory)","isArchived":false,"lastActivityAt":100}"#.utf8
        ).write(to: desktopSessionsDirectory.appending(path: "local-other.json"))
        try Data(
            #"{"sessionId":"running","name":"today-cloud-13","nameSource":"derived","cwd":"\#(sharedDirectory)"}"#.utf8
        ).write(to: activeSessionsDirectory.appending(path: "42.json"))

        let resolver = ClaudeSessionNameResolver(homeDirectory: temporaryHome)

        #expect(await resolver.name(
            for: "running",
            processID: 42,
            refresh: true
        ) == "QA card multi-page support")
        #expect(await resolver.name(
            for: "other",
            processID: nil,
            refresh: true
        ) == "Untitled session")

        try Data(
            #"{"sessionId":"local-running","cliSessionId":"running","title":"Renamed QA card","cwd":"\#(sharedDirectory)","isArchived":false,"lastActivityAt":300}"#.utf8
        ).write(to: runningMetadataURL)
        #expect(await resolver.name(
            for: "running",
            processID: 42,
            refresh: true
        ) == "Renamed QA card")
    }

    @Test
    func recognizesClaudeReadySessionOnlyAfterItsCompletionIsFocused() async throws {
        let temporaryHome = FileManager.default.temporaryDirectory
            .appending(path: "claude-desktop-read-state-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: temporaryHome) }
        let desktopSessionsDirectory = temporaryHome
            .appending(
                path: "Library/Application Support/Claude/claude-code-sessions/account/environment",
                directoryHint: .isDirectory
            )
        try FileManager.default.createDirectory(
            at: desktopSessionsDirectory,
            withIntermediateDirectories: true
        )
        let metadataURL = desktopSessionsDirectory.appending(path: "local-ready.json")
        let resolver = ClaudeSessionNameResolver(homeDirectory: temporaryHome)
        let completedAt = Date(timeIntervalSince1970: 0.2)

        try Data(
            #"{"cliSessionId":"ready","title":"Ready task","isArchived":false,"lastActivityAt":200,"lastFocusedAt":100}"#.utf8
        ).write(to: metadataURL)
        #expect(await resolver.isReadySessionRead(
            sessionID: "ready",
            completedAt: completedAt
        ) == false)

        try Data(
            #"{"cliSessionId":"ready","title":"Ready task","isArchived":false,"lastActivityAt":200,"lastFocusedAt":300}"#.utf8
        ).write(to: metadataURL)
        #expect(await resolver.isReadySessionRead(
            sessionID: "ready",
            completedAt: completedAt
        ) == true)
    }

    @Test
    func recognizesCompletionWhileTheClaudeSessionIsAlreadySelected() async throws {
        let temporaryHome = FileManager.default.temporaryDirectory
            .appending(path: "claude-desktop-selected-session-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: temporaryHome) }
        let desktopSessionsDirectory = temporaryHome
            .appending(
                path: "Library/Application Support/Claude/claude-code-sessions/account/environment",
                directoryHint: .isDirectory
            )
        let logDirectory = temporaryHome
            .appending(path: "Library/Logs/Claude", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(
            at: desktopSessionsDirectory,
            withIntermediateDirectories: true
        )
        try FileManager.default.createDirectory(
            at: logDirectory,
            withIntermediateDirectories: true
        )

        let desktopSessionID = "local_11111111-1111-1111-1111-111111111111"
        try Data(
            #"{"sessionId":"local_11111111-1111-1111-1111-111111111111","cliSessionId":"ready","title":"Ready task","isArchived":false,"lastActivityAt":300,"lastFocusedAt":100}"#.utf8
        ).write(to: desktopSessionsDirectory.appending(path: "local-ready.json"))
        let logURL = logDirectory.appending(path: "main.log")
        try Data(
            "2026-07-14 21:26:39 [info] [CCD] LocalSessions.setFocusedSession: sessionId=\(desktopSessionID)\n".utf8
        ).write(to: logURL)
        let resolver = ClaudeSessionNameResolver(homeDirectory: temporaryHome)

        #expect(await resolver.isReadySessionRead(
            sessionID: "ready",
            completedAt: Date(timeIntervalSince1970: 0.3)
        ) == true)

        let handle = try FileHandle(forWritingTo: logURL)
        try handle.seekToEnd()
        try handle.write(contentsOf: Data(
            "2026-07-14 21:27:00 [info] [CCD] LocalSessions.setFocusedSession: sessionId=null\n".utf8
        ))
        try handle.close()

        #expect(await resolver.isReadySessionRead(
            sessionID: "ready",
            completedAt: Date(timeIntervalSince1970: 0.3)
        ) == false)
    }

    @Test
    func staleClaudeFocusCannotAcknowledgeANewerCompletion() async throws {
        let temporaryHome = FileManager.default.temporaryDirectory
            .appending(path: "claude-desktop-stale-focus-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: temporaryHome) }
        let desktopSessionsDirectory = temporaryHome
            .appending(
                path: "Library/Application Support/Claude/claude-code-sessions/account/environment",
                directoryHint: .isDirectory
            )
        try FileManager.default.createDirectory(
            at: desktopSessionsDirectory,
            withIntermediateDirectories: true
        )
        try Data(
            #"{"cliSessionId":"ready","title":"Ready task","isArchived":false,"lastActivityAt":100,"lastFocusedAt":150}"#.utf8
        ).write(to: desktopSessionsDirectory.appending(path: "local-ready.json"))
        let resolver = ClaudeSessionNameResolver(homeDirectory: temporaryHome)

        #expect(await resolver.isReadySessionRead(
            sessionID: "ready",
            completedAt: Date(timeIntervalSince1970: 0.3)
        ) == false)
    }

    @Test
    func readsMatchingNameFromProcessMetadataWithoutReadingTranscripts() throws {
        let temporaryHome = FileManager.default.temporaryDirectory
            .appending(path: "claude-session-name-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: temporaryHome) }
        let sessionsDirectory = temporaryHome
            .appending(path: ".claude/sessions", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(
            at: sessionsDirectory,
            withIntermediateDirectories: true
        )
        try Data(#"{"sessionId":"other","name":"Wrong session"}"#.utf8)
            .write(to: sessionsDirectory.appending(path: "10.json"))
        try Data(#"{"sessionId":"wanted","name":"  Review PR 5446  ","cwd":"/private/project"}"#.utf8)
            .write(to: sessionsDirectory.appending(path: "20.json"))

        let name = ClaudeSessionNameResolver.lookupName(
            sessionID: "wanted",
            processID: 20,
            sessionsDirectory: sessionsDirectory
        )

        #expect(name == "Review PR 5446")
    }

    @Test
    func ignoresMalformedOversizedAndMismatchedMetadata() throws {
        let temporaryDirectory = FileManager.default.temporaryDirectory
            .appending(path: "claude-session-metadata-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: temporaryDirectory) }
        try FileManager.default.createDirectory(
            at: temporaryDirectory,
            withIntermediateDirectories: true
        )
        try Data("not json".utf8).write(to: temporaryDirectory.appending(path: "1.json"))
        try Data(repeating: 0x20, count: 65 * 1_024)
            .write(to: temporaryDirectory.appending(path: "2.json"))
        try Data(#"{"sessionId":"other","name":"Other name"}"#.utf8)
            .write(to: temporaryDirectory.appending(path: "3.json"))

        #expect(ClaudeSessionNameResolver.lookupName(
            sessionID: "wanted",
            processID: nil,
            sessionsDirectory: temporaryDirectory
        ) == nil)
    }

    @Test
    func rejectsClaudeDerivedProcessNamesButAcceptsExplicitNames() throws {
        let temporaryDirectory = FileManager.default.temporaryDirectory
            .appending(path: "claude-session-source-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: temporaryDirectory) }
        try FileManager.default.createDirectory(
            at: temporaryDirectory,
            withIntermediateDirectories: true
        )
        try Data(#"{"sessionId":"derived","name":"today-cloud-13","nameSource":"derived"}"#.utf8)
            .write(to: temporaryDirectory.appending(path: "10.json"))
        try Data(#"{"sessionId":"named","name":"Review PR 5446"}"#.utf8)
            .write(to: temporaryDirectory.appending(path: "20.json"))

        #expect(ClaudeSessionNameResolver.lookupName(
            sessionID: "derived",
            processID: 10,
            sessionsDirectory: temporaryDirectory
        ) == nil)
        #expect(ClaudeSessionNameResolver.lookupName(
            sessionID: "named",
            processID: 20,
            sessionsDirectory: temporaryDirectory
        ) == "Review PR 5446")
    }

    @Test
    func cachesNamesUntilRefreshAndRetainsTheLastKnownName() async {
        let lookup = ClaudeNameLookupSequence(values: ["First title", "Renamed title", nil])
        let resolver = ClaudeSessionNameResolver { _, _ in lookup.next() }

        #expect(await resolver.name(for: "session", processID: 42) == "First title")
        #expect(await resolver.name(for: "session", processID: 42) == "First title")
        #expect(lookup.callCount == 1)
        #expect(await resolver.name(
            for: "session",
            processID: 42,
            refresh: true
        ) == "Renamed title")
        #expect(await resolver.name(
            for: "session",
            processID: 42,
            refresh: true
        ) == "Renamed title")
        #expect(lookup.callCount == 3)
    }
}

private final class ClaudeNameLookupSequence: @unchecked Sendable {
    private let lock = NSLock()
    private var values: [String?]
    private var calls = 0

    init(values: [String?]) {
        self.values = values
    }

    var callCount: Int {
        lock.withLock { calls }
    }

    func next() -> String? {
        lock.withLock {
            calls += 1
            return values.isEmpty ? nil : values.removeFirst()
        }
    }
}
