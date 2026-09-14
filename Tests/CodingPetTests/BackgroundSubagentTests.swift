import Darwin
import Foundation
import Testing
@testable import CodingPet
import CodingPetBridge

@MainActor
struct BackgroundSubagentTests {
    private let base = Date(timeIntervalSince1970: 1_800_000_000)

    @Test
    func stopWhileSubagentsRunKeepsTheSessionWorkingUntilTheLastOneFinishes() {
        let store = SessionStore()
        store.apply(event("UserPromptSubmit", at: 0))
        store.apply(event("SubagentStart", at: 1))
        store.apply(event("SubagentStart", at: 2))
        store.apply(event("Stop", at: 3))

        let working = store.sessions.first
        #expect(working?.status == .running)
        #expect(working?.summary == AgentSession.backgroundTaskSummary)
        #expect(working?.turnStartedAt == base)

        store.apply(event("SubagentStop", at: 4))
        #expect(store.sessions.first?.status == .running)

        store.apply(event("SubagentStop", at: 5))
        let finished = store.sessions.first
        #expect(finished?.status == .ready)
        #expect(finished?.summary == AgentSession.completedSummary)
        #expect(finished?.updatedAt == base.addingTimeInterval(5))
    }

    @Test
    func stopWithoutBackgroundWorkStillFinishesImmediately() {
        let store = SessionStore()
        store.apply(event("UserPromptSubmit", at: 0))
        store.apply(event("SubagentStart", at: 1))
        store.apply(event("SubagentStop", at: 2))
        store.apply(event("Stop", at: 3))
        #expect(store.sessions.first?.status == .ready)

        // A stray SubagentStop never flips a finished session back.
        store.apply(event("SubagentStop", at: 4))
        #expect(store.sessions.first?.status == .ready)
        #expect(store.sessions.first?.updatedAt == base.addingTimeInterval(3))
    }

    @Test
    func sessionEndClearsTheBackgroundCounter() {
        let store = SessionStore()
        store.apply(event("UserPromptSubmit", at: 0))
        store.apply(event("SubagentStart", at: 1))
        store.apply(event("SessionEnd", at: 2))
        #expect(store.sessions.isEmpty)

        store.apply(event("UserPromptSubmit", at: 3))
        store.apply(event("Stop", at: 4))
        #expect(store.sessions.first?.status == .ready)
    }

    @Test
    func subagentEventsAreNotPersistedAsSessionSnapshots() {
        #expect(!event("SubagentStart", at: 0).describesSessionState)
        #expect(!event("SubagentStop", at: 0).describesSessionState)
        #expect(event("Stop", at: 0).describesSessionState)
    }

    /// The kernel exposes another process's environment only for non-platform
    /// binaries (the Claude executable qualifies; /bin/sleep and the test host
    /// do not), so this exercises the lookup against our own hook executable,
    /// which waits on stdin in status line mode until the pipe closes.
    @Test
    func processEnvironmentReaderWalksFromAChildToItsParent() throws {
        let repositoryRoot = URL(filePath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        let hookURL = repositoryRoot.appending(path: ".build/debug/CodingPetHook")
        try #require(FileManager.default.isExecutableFile(atPath: hookURL.path))
        let child = Process()
        child.executableURL = hookURL
        child.arguments = ["--statusline"]
        let stdin = Pipe()
        child.standardInput = stdin
        var environment = ProcessInfo.processInfo.environment
        environment["CODINGPET_CHILD_ONLY"] = "from-child"
        child.environment = environment
        try child.run()
        defer {
            try? stdin.fileHandleForWriting.close()
            child.waitUntilExit()
        }

        #expect(ProcessEnvironmentReader.parentProcessID(of: child.processIdentifier) == getpid())
        #expect(
            ProcessEnvironmentReader.value(of: "CODINGPET_CHILD_ONLY", inAncestorsOf: child.processIdentifier)
                == "from-child"
        )
        #expect(ProcessEnvironmentReader.value(of: "CODINGPET_MISSING", inAncestorsOf: child.processIdentifier) == nil)
        #expect(ProcessEnvironmentReader.environment(of: getpid())?["HOME"] != nil)
    }

    private func event(_ name: String, at offset: TimeInterval) -> HookEventEnvelope {
        HookEventEnvelope(
            provider: .claudeCode,
            eventName: name,
            timestamp: base.addingTimeInterval(offset),
            parentProcessID: nil,
            sessionID: "bg-session",
            cwd: "/tmp/project"
        )
    }
}
