import Foundation
import CodingPetBridge

enum SessionEventRouter {
    static func session(
        for event: HookEventEnvelope,
        existing: AgentSession?
    ) -> AgentSession? {
        guard event.protocolVersion == HookEventEnvelope.currentProtocolVersion,
              let state = adapter(for: event.provider).normalizedState(for: event) else {
            return nil
        }

        let provider = agentProvider(for: event.provider)
        let terminal = terminalTarget(for: event, existing: existing)
        return AgentSession(
            id: sessionIdentifier(provider: event.provider, sessionID: event.sessionID),
            provider: provider,
            projectName: projectName(for: event.cwd),
            sessionName: existing?.sessionName,
            cwd: event.cwd,
            status: state.status,
            summary: state.summary,
            updatedAt: event.timestamp,
            terminal: terminal
        )
    }

    static func sessionIdentifier(provider: HookProvider, sessionID: String) -> String {
        "\(provider.rawValue):\(sessionID)"
    }

    private static func adapter(for provider: HookProvider) -> any AgentSessionEventAdapter {
        switch provider {
        case .codex:
            CodexEventAdapter()
        case .claudeCode:
            ClaudeCodeEventAdapter()
        }
    }

    private static func agentProvider(for provider: HookProvider) -> AgentProvider {
        switch provider {
        case .codex: .codex
        case .claudeCode: .claudeCode
        }
    }

    private static func projectName(for cwd: String) -> String {
        let name = URL(fileURLWithPath: cwd).lastPathComponent
        return name.isEmpty ? cwd : name
    }

    private static func terminalTarget(
        for event: HookEventEnvelope,
        existing: AgentSession?
    ) -> TerminalTarget? {
        guard event.parentProcessID != nil || existing?.terminal != nil else { return nil }
        return TerminalTarget(
            bundleIdentifier: existing?.terminal?.bundleIdentifier,
            processIdentifier: event.parentProcessID ?? existing?.terminal?.processIdentifier,
            tty: existing?.terminal?.tty
        )
    }
}
