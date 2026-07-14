import Foundation
import Testing
@testable import CodingPet

struct HookConfigurationInstallerTests {
    @Test
    func installationStatusDistinguishesMissingInstalledAndDamagedState() throws {
        let directory = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let configURL = directory.appending(path: "hooks.json")
        let installer = HookConfigurationInstaller(
            provider: .codex,
            configURL: configURL,
            hookExecutableURL: URL(fileURLWithPath: "/tmp/CodingPetHook")
        )

        #expect(installer.installationStatus() == .notInstalled)

        try installer.install()
        #expect(installer.installationStatus() == .installed)

        try FileManager.default.removeItem(at: installer.backupURL)
        #expect(installer.installationStatus() == .needsRepair)
    }

    @Test
    func codexInstallMergesAndUninstallRestoresExactBytes() throws {
        let directory = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let configURL = directory.appending(path: "hooks.json")
        let original = Data(#"""
{
  "theme": "dark",
  "hooks": {
    "Stop": [{"hooks": [{"type": "command", "command": "/existing-hook"}]}]
  }
}
"""#.utf8)
        try original.write(to: configURL)
        let installer = HookConfigurationInstaller(
            provider: .codex,
            configURL: configURL,
            hookExecutableURL: URL(fileURLWithPath: "/Applications/Coding Pet/CodingPetHook")
        )

        try installer.install()

        #expect(try Data(contentsOf: installer.backupURL) == original)
        let installed = try jsonObject(at: configURL)
        #expect(installed["theme"] as? String == "dark")
        #expect(codingPetHandlerCount(in: installed) == 7)
        #expect(existingCommandCount(in: installed, command: "/existing-hook") == 1)

        try installer.uninstall()

        #expect(try Data(contentsOf: configURL) == original)
        #expect(!FileManager.default.fileExists(atPath: installer.backupURL.path))
        #expect(!FileManager.default.fileExists(atPath: installer.metadataURL.path))
    }

    @Test
    func reinstallIsIdempotentAndKeepsFirstBackup() throws {
        let directory = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let configURL = directory.appending(path: "settings.json")
        let original = Data(#"{"permissions":{"allow":["Read"]}}"#.utf8)
        try original.write(to: configURL)
        let installer = HookConfigurationInstaller(
            provider: .claudeCode,
            configURL: configURL,
            hookExecutableURL: URL(fileURLWithPath: "/tmp/CodingPetHook")
        )

        try installer.install()
        try installer.install()

        #expect(try Data(contentsOf: installer.backupURL) == original)
        let installed = try jsonObject(at: configURL)
        #expect(codingPetHandlerCount(in: installed) == 9)
        let notificationGroups = try hookGroups(named: "Notification", in: installed)
        #expect(notificationGroups.count == 1)
        #expect(notificationGroups.first?["matcher"] as? String == "permission_prompt|idle_prompt|elicitation_dialog")
    }

    @Test
    func uninstallPreservesUnrelatedEditsMadeAfterInstall() throws {
        let directory = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let configURL = directory.appending(path: "settings.json")
        try Data(#"{"hooks":{},"theme":"light"}"#.utf8).write(to: configURL)
        let installer = HookConfigurationInstaller(
            provider: .claudeCode,
            configURL: configURL,
            hookExecutableURL: URL(fileURLWithPath: "/tmp/CodingPetHook")
        )
        try installer.install()
        var edited = try jsonObject(at: configURL)
        edited["theme"] = "dark"
        edited["userAddedAfterInstall"] = true
        try JSONSerialization.data(withJSONObject: edited, options: [.prettyPrinted, .sortedKeys])
            .write(to: configURL)

        try installer.uninstall()

        let uninstalled = try jsonObject(at: configURL)
        #expect(uninstalled["theme"] as? String == "dark")
        #expect(uninstalled["userAddedAfterInstall"] as? Bool == true)
        #expect(codingPetHandlerCount(in: uninstalled) == 0)
    }

    @Test
    func configCreatedByInstallerIsRemovedOnCleanUninstall() throws {
        let directory = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let configURL = directory.appending(path: "hooks.json")
        let installer = HookConfigurationInstaller(
            provider: .codex,
            configURL: configURL,
            hookExecutableURL: URL(fileURLWithPath: "/tmp/CodingPetHook")
        )

        try installer.install()
        #expect(FileManager.default.fileExists(atPath: configURL.path))

        try installer.uninstall()
        #expect(!FileManager.default.fileExists(atPath: configURL.path))
    }

    @Test
    func invalidJSONIsNotModifiedOrBackedUp() throws {
        let directory = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let configURL = directory.appending(path: "hooks.json")
        let invalid = Data("{ invalid".utf8)
        try invalid.write(to: configURL)
        let installer = HookConfigurationInstaller(
            provider: .codex,
            configURL: configURL,
            hookExecutableURL: URL(fileURLWithPath: "/tmp/CodingPetHook")
        )

        #expect(throws: HookConfigurationInstaller.Error.self) {
            try installer.install()
        }
        #expect(try Data(contentsOf: configURL) == invalid)
        #expect(!FileManager.default.fileExists(atPath: installer.backupURL.path))
        #expect(!FileManager.default.fileExists(atPath: installer.metadataURL.path))
    }

    @Test
    func coordinatorPreflightsBothProvidersBeforeWritingEitherConfig() throws {
        let home = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: home) }
        let codexDirectory = home.appending(path: ".codex", directoryHint: .isDirectory)
        let claudeDirectory = home.appending(path: ".claude", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: codexDirectory, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: claudeDirectory, withIntermediateDirectories: true)
        let codexURL = codexDirectory.appending(path: "hooks.json")
        let claudeURL = claudeDirectory.appending(path: "settings.json")
        let codexOriginal = Data(#"{"hooks":{}}"#.utf8)
        let claudeInvalid = Data("{ invalid".utf8)
        try codexOriginal.write(to: codexURL)
        try claudeInvalid.write(to: claudeURL)
        let executableURL = home.appending(path: "CodingPetHook")
        FileManager.default.createFile(atPath: executableURL.path, contents: Data())
        try FileManager.default.setAttributes(
            [.posixPermissions: NSNumber(value: UInt16(0o700))],
            ofItemAtPath: executableURL.path
        )
        let coordinator = HookInstallationCoordinator(
            homeDirectory: home,
            hookExecutableURL: executableURL
        )

        #expect(throws: (any Swift.Error).self) {
            try coordinator.install()
        }

        #expect(try Data(contentsOf: codexURL) == codexOriginal)
        #expect(try Data(contentsOf: claudeURL) == claudeInvalid)
        #expect(!FileManager.default.fileExists(
            atPath: codexDirectory.appending(path: ".hooks.json.codingpet.backup").path
        ))
    }

    @Test
    func claudeOnlyInstallAndUninstallDoesNotReadOrModifyCodex() throws {
        let home = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: home) }
        let codexDirectory = home.appending(path: ".codex", directoryHint: .isDirectory)
        let claudeDirectory = home.appending(path: ".claude", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: codexDirectory, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: claudeDirectory, withIntermediateDirectories: true)
        let codexURL = codexDirectory.appending(path: "hooks.json")
        let claudeURL = claudeDirectory.appending(path: "settings.json")
        let invalidCodex = Data("{ invalid".utf8)
        let originalClaude = Data(#"{"theme":"dark"}"#.utf8)
        try invalidCodex.write(to: codexURL)
        try originalClaude.write(to: claudeURL)
        let executableURL = home.appending(path: "CodingPetHook")
        FileManager.default.createFile(atPath: executableURL.path, contents: Data())
        try FileManager.default.setAttributes(
            [.posixPermissions: NSNumber(value: UInt16(0o700))],
            ofItemAtPath: executableURL.path
        )
        let coordinator = HookInstallationCoordinator(
            homeDirectory: home,
            hookExecutableURL: executableURL,
            codexExecutableURL: home.appending(path: "missing-codex")
        )

        let report = try coordinator.install(.claudeCode)

        #expect(report.trustedCodexHookCount == 0)
        #expect(coordinator.installationStatuses()[.claudeCode] == .installed)
        #expect(coordinator.installationStatuses()[.codex] == .notInstalled)
        #expect(try Data(contentsOf: codexURL) == invalidCodex)
        #expect(codingPetHandlerCount(in: try jsonObject(at: claudeURL)) == 9)

        try coordinator.uninstall(.claudeCode)

        #expect(try Data(contentsOf: codexURL) == invalidCodex)
        #expect(try Data(contentsOf: claudeURL) == originalClaude)
        #expect(coordinator.installationStatuses()[.claudeCode] == .notInstalled)
    }

    @Test
    func codexOnlyInstallAndUninstallDoesNotReadOrModifyClaude() throws {
        let home = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: home) }
        let codexDirectory = home.appending(path: ".codex", directoryHint: .isDirectory)
        let claudeDirectory = home.appending(path: ".claude", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: codexDirectory, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: claudeDirectory, withIntermediateDirectories: true)
        let codexURL = codexDirectory.appending(path: "hooks.json")
        let claudeURL = claudeDirectory.appending(path: "settings.json")
        let originalCodex = Data(#"{"theme":"dark"}"#.utf8)
        let invalidClaude = Data("{ invalid".utf8)
        try originalCodex.write(to: codexURL)
        try invalidClaude.write(to: claudeURL)
        let executableURL = home.appending(path: "CodingPetHook")
        FileManager.default.createFile(atPath: executableURL.path, contents: Data())
        try FileManager.default.setAttributes(
            [.posixPermissions: NSNumber(value: UInt16(0o700))],
            ofItemAtPath: executableURL.path
        )
        let untrustedHooks = coordinatorCodingPetHooks(trustStatus: "untrusted")
        let trustedHooks = coordinatorCodingPetHooks(trustStatus: "trusted")
        let trustedState = Dictionary(uniqueKeysWithValues: (0..<6).map {
            ("codingpet:\($0)", ["trusted_hash": "sha256:new-\($0)"])
        })
        let fake = CoordinatorFakeCodexSession(responses: [
            ["data": [["hooks": []]]],
            ["data": [["hooks": untrustedHooks]]],
            ["config": ["hooks": ["state": [:]]]],
            ["status": "ok"],
            ["data": [["hooks": trustedHooks]]],
            ["data": [["hooks": trustedHooks]]],
            ["config": ["hooks": ["state": trustedState]]],
            ["status": "ok"]
        ])
        let coordinator = HookInstallationCoordinator(
            homeDirectory: home,
            hookExecutableURL: executableURL,
            trustManager: CodexHookTrustManager(sessionFactory: { fake })
        )

        let report = try coordinator.install(.codex)

        #expect(report.trustedCodexHookCount == 6)
        #expect(coordinator.installationStatuses()[.codex] == .installed)
        #expect(coordinator.installationStatuses()[.claudeCode] == .notInstalled)
        #expect(try Data(contentsOf: claudeURL) == invalidClaude)
        #expect(codingPetHandlerCount(in: try jsonObject(at: codexURL)) == 7)

        try coordinator.uninstall(.codex)

        #expect(try Data(contentsOf: codexURL) == originalCodex)
        #expect(try Data(contentsOf: claudeURL) == invalidClaude)
        #expect(coordinator.installationStatuses()[.codex] == .notInstalled)
    }

    @MainActor
    @Test
    func integrationStoreUpdatesOnlyTheSelectedProvider() throws {
        let home = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: home) }
        let executableURL = home.appending(path: "CodingPetHook")
        FileManager.default.createFile(atPath: executableURL.path, contents: Data())
        try FileManager.default.setAttributes(
            [.posixPermissions: NSNumber(value: UInt16(0o700))],
            ofItemAtPath: executableURL.path
        )
        let store = IntegrationSettingsStore(
            coordinator: HookInstallationCoordinator(
                homeDirectory: home,
                hookExecutableURL: executableURL,
                codexExecutableURL: home.appending(path: "missing-codex")
            )
        )
        store.refresh()

        store.installOrRepair(.claudeCode)

        #expect(store.statuses[.claudeCode] == .installed)
        #expect(store.statuses[.codex] == .notInstalled)
        #expect(store.feedback?.kind == .success)
        #expect(store.feedback?.message.contains("Claude Code hooks were installed") == true)

        store.uninstall(.claudeCode)

        #expect(store.statuses[.claudeCode] == .notInstalled)
        #expect(store.statuses[.codex] == .notInstalled)
        #expect(store.feedback?.message == "Claude Code hooks were removed.")
    }

    @Test
    func installPreservesASymlinkedConfigurationFile() throws {
        let directory = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let targetURL = directory.appending(path: "dotfiles/claude-settings.json")
        try FileManager.default.createDirectory(
            at: targetURL.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        let original = Data(#"{"theme":"linked"}"#.utf8)
        try original.write(to: targetURL)
        let configURL = directory.appending(path: "settings.json")
        try FileManager.default.createSymbolicLink(at: configURL, withDestinationURL: targetURL)
        let installer = HookConfigurationInstaller(
            provider: .claudeCode,
            configURL: configURL,
            hookExecutableURL: URL(fileURLWithPath: "/tmp/CodingPetHook")
        )

        try installer.install()
        let attributes = try FileManager.default.attributesOfItem(atPath: configURL.path)
        #expect(attributes[.type] as? FileAttributeType == .typeSymbolicLink)

        try installer.uninstall()
        let restoredAttributes = try FileManager.default.attributesOfItem(atPath: configURL.path)
        #expect(restoredAttributes[.type] as? FileAttributeType == .typeSymbolicLink)
        #expect(try Data(contentsOf: targetURL) == original)
    }

    @Test
    func installRemovesAgentPeekHandlersWithoutRestoringThemOnUninstall() throws {
        let directory = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let configURL = directory.appending(path: "hooks.json")
        try Data(#"""
        {
          "hooks": {
            "Stop": [{"hooks": [
              {"type":"command","command":"'/Applications/AgentPeek.app/Contents/Resources/AgentPeekBridge' --bridge-hook-event codex"},
              {"type":"command","command":"/keep-me"}
            ]}]
          }
        }
        """#.utf8).write(to: configURL)
        let installer = HookConfigurationInstaller(
            provider: .codex,
            configURL: configURL,
            hookExecutableURL: URL(fileURLWithPath: "/tmp/CodingPetHook")
        )

        let removedCount = try installer.install(removingAgentPeekHandlers: true)

        #expect(removedCount == 1)
        #expect(agentPeekHandlerCount(in: try jsonObject(at: configURL)) == 0)
        #expect(agentPeekHandlerCount(in: try jsonObject(at: installer.backupURL)) == 0)
        #expect(existingCommandCount(in: try jsonObject(at: configURL), command: "/keep-me") == 1)

        try installer.uninstall()

        let restored = try jsonObject(at: configURL)
        #expect(agentPeekHandlerCount(in: restored) == 0)
        #expect(existingCommandCount(in: restored, command: "/keep-me") == 1)
    }

    @Test
    func repairingAnExistingInstallSanitizesItsOriginalBackup() throws {
        let directory = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let configURL = directory.appending(path: "hooks.json")
        try Data(#"""
        {"hooks":{"Stop":[{"hooks":[
          {"type":"command","command":"AgentPeekBridge --bridge-hook-event codex"}
        ]}]}}
        """#.utf8).write(to: configURL)
        let installer = HookConfigurationInstaller(
            provider: .codex,
            configURL: configURL,
            hookExecutableURL: URL(fileURLWithPath: "/tmp/CodingPetHook")
        )
        try installer.install()
        #expect(agentPeekHandlerCount(in: try jsonObject(at: installer.backupURL)) == 1)

        try installer.install(removingAgentPeekHandlers: true)
        #expect(agentPeekHandlerCount(in: try jsonObject(at: installer.backupURL)) == 0)

        try installer.uninstall()
        #expect(agentPeekHandlerCount(in: try jsonObject(at: configURL)) == 0)
    }

    private func temporaryDirectory() throws -> URL {
        let url = FileManager.default.temporaryDirectory
            .appending(path: "codingpet-installer-tests-\(UUID().uuidString)", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    private func jsonObject(at url: URL) throws -> [String: Any] {
        try #require(
            JSONSerialization.jsonObject(with: Data(contentsOf: url)) as? [String: Any]
        )
    }

    private func hookGroups(named event: String, in root: [String: Any]) throws -> [[String: Any]] {
        let hooks = try #require(root["hooks"] as? [String: Any])
        return try #require(hooks[event] as? [[String: Any]])
    }

    private func codingPetHandlerCount(in root: [String: Any]) -> Int {
        guard let hooks = root["hooks"] as? [String: Any] else { return 0 }
        return hooks.values.reduce(into: 0) { count, value in
            guard let groups = value as? [[String: Any]] else { return }
            for group in groups {
                guard let handlers = group["hooks"] as? [[String: Any]] else { continue }
                count += handlers.count {
                    $0["statusMessage"] as? String == HookConfigurationInstaller.ownershipMarker
                }
            }
        }
    }

    private func existingCommandCount(in root: [String: Any], command: String) -> Int {
        guard let hooks = root["hooks"] as? [String: Any] else { return 0 }
        return hooks.values.reduce(into: 0) { count, value in
            guard let groups = value as? [[String: Any]] else { return }
            for group in groups {
                guard let handlers = group["hooks"] as? [[String: Any]] else { continue }
                count += handlers.count { $0["command"] as? String == command }
            }
        }
    }

    private func agentPeekHandlerCount(in root: [String: Any]) -> Int {
        guard let hooks = root["hooks"] as? [String: Any] else { return 0 }
        return hooks.values.reduce(into: 0) { count, value in
            guard let groups = value as? [[String: Any]] else { return }
            for group in groups {
                guard let handlers = group["hooks"] as? [[String: Any]] else { continue }
                count += handlers.count {
                    ($0["command"] as? String)?.contains("AgentPeekBridge") == true
                        && ($0["command"] as? String)?.contains("--bridge-hook-event") == true
                }
            }
        }
    }

    private func coordinatorCodingPetHooks(trustStatus: String) -> [[String: Any]] {
        (0..<6).map { index in
            [
                "key": "codingpet:\(index)",
                "command": "'/tmp/CodingPetHook' --provider codex",
                "currentHash": "sha256:new-\(index)",
                "trustStatus": trustStatus,
                "statusMessage": HookConfigurationInstaller.ownershipMarker
            ]
        }
    }
}

private final class CoordinatorFakeCodexSession: CodexAppServerSessionProtocol {
    enum Error: Swift.Error {
        case missingResponse
    }

    private var responses: [[String: Any]]

    init(responses: [[String: Any]]) {
        self.responses = responses
    }

    func call(method: String, params: [String: Any]) throws -> [String: Any] {
        guard !responses.isEmpty else { throw Error.missingResponse }
        return responses.removeFirst()
    }

    func close() {}
}
