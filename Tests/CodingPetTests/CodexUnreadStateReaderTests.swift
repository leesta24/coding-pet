import Foundation
import Testing
@testable import CodingPet

struct CodexUnreadStateReaderTests {
    @Test
    func readsOnlyLocalUnreadThreadIDs() async throws {
        let file = try temporaryStateFile(contents: #"""
        {
          "electron-persisted-atom-state": {
            "unread-thread-ids-by-host-v1": {
              "local": ["thread-a", "thread-b", "thread-a"],
              "remote": ["remote-thread"]
            },
            "prompt-history": {"thread-a": ["private prompt"]}
          }
        }
        """#)
        defer { try? FileManager.default.removeItem(at: file.deletingLastPathComponent()) }

        let reader = CodexUnreadStateReader(stateURL: file)

        #expect(await reader.localUnreadThreadIDs() == ["thread-a", "thread-b"])
    }

    @Test
    func missingLocalHostMeansThereAreNoLocalUnreadThreads() async throws {
        let file = try temporaryStateFile(contents: #"""
        {
          "electron-persisted-atom-state": {
            "unread-thread-ids-by-host-v1": {"remote": ["thread"]}
          }
        }
        """#)
        defer { try? FileManager.default.removeItem(at: file.deletingLastPathComponent()) }

        #expect(await CodexUnreadStateReader(stateURL: file)
            .localUnreadThreadIDs() == [])
    }

    @Test
    func malformedMissingAndOversizedStateAreUnknown() async throws {
        let missing = FileManager.default.temporaryDirectory
            .appending(path: UUID().uuidString)
            .appending(path: "missing.json")
        #expect(await CodexUnreadStateReader(stateURL: missing)
            .localUnreadThreadIDs() == nil)

        let malformed = try temporaryStateFile(contents: "not-json")
        defer { try? FileManager.default.removeItem(at: malformed.deletingLastPathComponent()) }
        #expect(await CodexUnreadStateReader(stateURL: malformed)
            .localUnreadThreadIDs() == nil)

        let oversizedDirectory = FileManager.default.temporaryDirectory
            .appending(path: UUID().uuidString, directoryHint: .isDirectory)
        try FileManager.default.createDirectory(
            at: oversizedDirectory,
            withIntermediateDirectories: true
        )
        defer { try? FileManager.default.removeItem(at: oversizedDirectory) }
        let oversized = oversizedDirectory.appending(path: "state.json")
        try Data(repeating: 0x20, count: 4 * 1024 * 1024 + 1).write(to: oversized)
        #expect(await CodexUnreadStateReader(stateURL: oversized)
            .localUnreadThreadIDs() == nil)
    }

    private func temporaryStateFile(contents: String) throws -> URL {
        let directory = FileManager.default.temporaryDirectory
            .appending(path: UUID().uuidString, directoryHint: .isDirectory)
        try FileManager.default.createDirectory(
            at: directory,
            withIntermediateDirectories: true
        )
        let file = directory.appending(path: "state.json")
        try Data(contents.utf8).write(to: file)
        return file
    }
}
