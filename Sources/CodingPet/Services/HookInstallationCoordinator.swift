import Foundation

struct HookInstallationReport {
    let trustedCodexHookCount: Int
    let removedAgentPeekHandlerCount: Int
    let removedAgentPeekStateCount: Int
}

struct HookInstallationCoordinator {
    enum Error: Swift.Error {
        case hookExecutableUnavailable

        var localizedDescription: String {
            switch self {
            case .hookExecutableUnavailable:
                "CodingPetHook was not found beside the CodingPet executable."
            }
        }
    }

    let homeDirectory: URL
    let hookExecutableURL: URL
    private let trustManager: CodexHookTrustManager

    init(
        homeDirectory: URL = FileManager.default.homeDirectoryForCurrentUser,
        hookExecutableURL: URL,
        codexExecutableURL: URL? = nil,
        trustManager: CodexHookTrustManager? = nil
    ) {
        self.homeDirectory = homeDirectory
        self.hookExecutableURL = hookExecutableURL
        self.trustManager = trustManager
            ?? CodexHookTrustManager(codexExecutableURL: codexExecutableURL)
    }

    @discardableResult
    func install() throws -> HookInstallationReport {
        try validateHookExecutable()
        try codexInstaller.validateInstall(removingAgentPeekHandlers: true)
        try claudeInstaller.validateInstall(removingAgentPeekHandlers: true)

        let snapshot = try trustManager.snapshot(cwd: homeDirectory)
        let removedCodexHandlers = try codexInstaller.install(removingAgentPeekHandlers: true)
        let removedClaudeHandlers: Int
        do {
            removedClaudeHandlers = try claudeInstaller.install(removingAgentPeekHandlers: true)
        } catch {
            try? codexInstaller.uninstall()
            throw error
        }

        let activation: CodexHookActivationReport
        do {
            activation = try trustManager.activateCodingPetHooks(
                cwd: homeDirectory,
                removingAgentPeekKeys: snapshot.agentPeekKeys
            )
        } catch {
            try? codexInstaller.uninstall()
            try? claudeInstaller.uninstall()
            throw error
        }

        return HookInstallationReport(
            trustedCodexHookCount: activation.trustedHookCount,
            removedAgentPeekHandlerCount: removedCodexHandlers + removedClaudeHandlers,
            removedAgentPeekStateCount: activation.removedAgentPeekStateCount
        )
    }

    @discardableResult
    func install(_ provider: HookConfigurationProvider) throws -> HookInstallationReport {
        try validateHookExecutable()

        switch provider {
        case .codex:
            try codexInstaller.validateInstall(removingAgentPeekHandlers: true)
            let snapshot = try trustManager.snapshot(cwd: homeDirectory)
            let removedHandlers = try codexInstaller.install(removingAgentPeekHandlers: true)
            do {
                let activation = try trustManager.activateCodingPetHooks(
                    cwd: homeDirectory,
                    removingAgentPeekKeys: snapshot.agentPeekKeys
                )
                return HookInstallationReport(
                    trustedCodexHookCount: activation.trustedHookCount,
                    removedAgentPeekHandlerCount: removedHandlers,
                    removedAgentPeekStateCount: activation.removedAgentPeekStateCount
                )
            } catch {
                try? codexInstaller.uninstall()
                throw error
            }

        case .claudeCode:
            try claudeInstaller.validateInstall(removingAgentPeekHandlers: true)
            let removedHandlers = try claudeInstaller.install(removingAgentPeekHandlers: true)
            return HookInstallationReport(
                trustedCodexHookCount: 0,
                removedAgentPeekHandlerCount: removedHandlers,
                removedAgentPeekStateCount: 0
            )
        }
    }

    func uninstall() throws {
        let snapshot = try trustManager.snapshot(cwd: homeDirectory)
        try codexInstaller.uninstall()
        try claudeInstaller.uninstall()
        try trustManager.removeTrustedHookKeys(snapshot.codingPetKeys)
    }

    func uninstall(_ provider: HookConfigurationProvider) throws {
        switch provider {
        case .codex:
            let snapshot = try trustManager.snapshot(cwd: homeDirectory)
            try codexInstaller.uninstall()
            try trustManager.removeTrustedHookKeys(snapshot.codingPetKeys)
        case .claudeCode:
            try claudeInstaller.uninstall()
        }
    }

    func installationStatuses() -> [HookConfigurationProvider: HookInstallationStatus] {
        [
            .codex: codexInstaller.installationStatus(),
            .claudeCode: claudeInstaller.installationStatus()
        ]
    }

    private var codexInstaller: HookConfigurationInstaller {
        HookConfigurationInstaller(
            provider: .codex,
            configURL: homeDirectory.appending(path: ".codex/hooks.json"),
            hookExecutableURL: hookExecutableURL
        )
    }

    private var claudeInstaller: HookConfigurationInstaller {
        HookConfigurationInstaller(
            provider: .claudeCode,
            configURL: homeDirectory.appending(path: ".claude/settings.json"),
            hookExecutableURL: hookExecutableURL
        )
    }

    private func validateHookExecutable() throws {
        guard FileManager.default.isExecutableFile(atPath: hookExecutableURL.path) else {
            throw Error.hookExecutableUnavailable
        }
    }
}
