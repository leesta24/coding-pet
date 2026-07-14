import Combine
import Foundation

@MainActor
final class IntegrationSettingsStore: ObservableObject {
    struct Feedback: Equatable {
        enum Kind: Equatable {
            case success
            case error
        }

        let kind: Kind
        let message: String
    }

    @Published private(set) var statuses: [HookConfigurationProvider: HookInstallationStatus]
    @Published private(set) var feedback: Feedback?

    private let coordinator: HookInstallationCoordinator

    init(coordinator: HookInstallationCoordinator) {
        self.coordinator = coordinator
        statuses = Dictionary(
            uniqueKeysWithValues: HookConfigurationProvider.allCases.map { ($0, .notInstalled) }
        )
    }

    func refresh() {
        statuses = coordinator.installationStatuses()
    }

    func installOrRepair(_ provider: HookConfigurationProvider) {
        do {
            let report = try coordinator.install(provider)
            let cleanup = report.removedAgentPeekHandlerCount > 0
                ? " AgentPeek hooks were removed."
                : ""
            let message: String
            switch provider {
            case .codex:
                message = "Installed and trusted \(report.trustedCodexHookCount) Codex hooks.\(cleanup)"
            case .claudeCode:
                message = "Claude Code hooks were installed.\(cleanup)"
            }
            feedback = Feedback(
                kind: .success,
                message: message
            )
        } catch {
            feedback = Feedback(
                kind: .error,
                message: "Could not install \(Self.name(for: provider)) hooks: \(Self.message(for: error))"
            )
        }
        refresh()
    }

    func uninstall(_ provider: HookConfigurationProvider) {
        do {
            try coordinator.uninstall(provider)
            feedback = Feedback(
                kind: .success,
                message: "\(Self.name(for: provider)) hooks were removed."
            )
        } catch {
            feedback = Feedback(
                kind: .error,
                message: "Could not remove \(Self.name(for: provider)) hooks: \(Self.message(for: error))"
            )
        }
        refresh()
    }

    private static func name(for provider: HookConfigurationProvider) -> String {
        switch provider {
        case .codex: "Codex CLI"
        case .claudeCode: "Claude Code"
        }
    }

    private static func message(for error: any Error) -> String {
        if let error = error as? HookConfigurationInstaller.Error {
            return error.localizedDescription
        }
        if let error = error as? HookInstallationCoordinator.Error {
            return error.localizedDescription
        }
        if let error = error as? CodexHookTrustManager.Error {
            return error.localizedDescription
        }
        return error.localizedDescription
    }
}
