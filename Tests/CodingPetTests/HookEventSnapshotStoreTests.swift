import Foundation
import Testing
import CodingPetBridge

struct HookEventSnapshotStoreTests {
    @Test
    func storesOnlyLatestSanitizedEnvelopePerSessionAndCanRemoveIt() throws {
        let directory = FileManager.default.temporaryDirectory
            .appending(path: "codingpet-snapshots-\(UUID().uuidString)", directoryHint: .isDirectory)
        defer { try? FileManager.default.removeItem(at: directory) }
        let store = HookEventSnapshotStore(directoryURL: directory)
        let first = event(name: "UserPromptSubmit", timestamp: Date(timeIntervalSince1970: 1))
        let latest = event(name: "PostToolUse", timestamp: Date(timeIntervalSince1970: 2))

        #expect(store.persist(first))
        #expect(store.persist(latest))
        #expect(store.persist(first))
        #expect(store.snapshots() == [latest])

        #expect(store.remove(provider: latest.provider, sessionID: latest.sessionID))
        #expect(store.snapshots().isEmpty)
    }

    @Test
    func ignoresMalformedAndOversizedFiles() throws {
        let directory = FileManager.default.temporaryDirectory
            .appending(path: "codingpet-snapshots-\(UUID().uuidString)", directoryHint: .isDirectory)
        defer { try? FileManager.default.removeItem(at: directory) }
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        try Data("not-json".utf8).write(to: directory.appending(path: "bad.json"))
        try Data(repeating: 0x41, count: 16_385).write(to: directory.appending(path: "large.json"))

        #expect(HookEventSnapshotStore(directoryURL: directory).snapshots().isEmpty)
    }

    @Test(arguments: ["SessionStart", "Stop", "SessionEnd", "StopFailure"])
    func inactiveBoundariesDeleteTheStoredSnapshot(eventName: String) throws {
        let directory = FileManager.default.temporaryDirectory
            .appending(path: "codingpet-snapshots-\(UUID().uuidString)", directoryHint: .isDirectory)
        defer { try? FileManager.default.removeItem(at: directory) }
        let store = HookEventSnapshotStore(directoryURL: directory)
        let active = event(name: "UserPromptSubmit", timestamp: Date(timeIntervalSince1970: 1))
        let inactive = event(name: eventName, timestamp: Date(timeIntervalSince1970: 2))

        #expect(store.persist(active))
        #expect(store.persist(inactive))
        #expect(store.snapshots().isEmpty)
    }

    @Test
    func olderInactiveBoundaryDoesNotDeleteANewerActiveSnapshot() throws {
        let directory = FileManager.default.temporaryDirectory
            .appending(path: "codingpet-snapshots-\(UUID().uuidString)", directoryHint: .isDirectory)
        defer { try? FileManager.default.removeItem(at: directory) }
        let store = HookEventSnapshotStore(directoryURL: directory)
        let active = event(name: "UserPromptSubmit", timestamp: Date(timeIntervalSince1970: 2))
        let staleStop = event(name: "Stop", timestamp: Date(timeIntervalSince1970: 1))

        #expect(store.persist(active))
        #expect(store.persist(staleStop))
        #expect(store.snapshots() == [active])
    }

    @Test
    func claudeStopPersistsReadySnapshotUntilSessionEnd() throws {
        let directory = FileManager.default.temporaryDirectory
            .appending(path: "codingpet-snapshots-\(UUID().uuidString)", directoryHint: .isDirectory)
        defer { try? FileManager.default.removeItem(at: directory) }
        let store = HookEventSnapshotStore(directoryURL: directory)
        let active = event(
            provider: .claudeCode,
            name: "UserPromptSubmit",
            timestamp: Date(timeIntervalSince1970: 1)
        )
        let stopped = event(
            provider: .claudeCode,
            name: "Stop",
            timestamp: Date(timeIntervalSince1970: 2)
        )
        let ended = event(
            provider: .claudeCode,
            name: "SessionEnd",
            timestamp: Date(timeIntervalSince1970: 3)
        )

        #expect(store.persist(active))
        #expect(store.persist(stopped))
        #expect(store.snapshots() == [stopped])
        #expect(store.persist(ended))
        #expect(store.snapshots().isEmpty)
    }

    private func event(
        provider: HookProvider = .codex,
        name: String,
        timestamp: Date
    ) -> HookEventEnvelope {
        HookEventEnvelope(
            provider: provider,
            eventName: name,
            timestamp: timestamp,
            parentProcessID: 123,
            sessionID: "session-1",
            cwd: "/tmp/project"
        )
    }
}
