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
        let turnStartedAt: Date?
        if event.eventName == "UserPromptSubmit" {
            turnStartedAt = event.timestamp
        } else if state.status == .running || state.status == .needsInput {
            turnStartedAt = existing?.turnStartedAt ?? event.timestamp
        } else {
            turnStartedAt = nil
        }
        return AgentSession(
            id: sessionIdentifier(provider: event.provider, sessionID: event.sessionID),
            provider: provider,
            projectName: projectName(for: event.cwd),
            sessionName: existing?.sessionName,
            cwd: event.cwd,
            status: state.status,
            summary: state.summary,
            updatedAt: event.timestamp,
            turnStartedAt: turnStartedAt,
            terminal: terminal,
            codexThreadIsPersisted: existing?.codexThreadIsPersisted
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
        return name.isEmpty || name == "/" ? "Codex task" : name
    }

    private static func terminalTarget(
        for event: HookEventEnvelope,
        existing: AgentSession?
    ) -> TerminalTarget? {
        let bundleIdentifier = bundleIdentifier(for: event)
            ?? existing?.terminal?.bundleIdentifier
        guard event.parentProcessID != nil
                || bundleIdentifier != nil
                || existing?.terminal != nil else {
            return nil
        }
        return TerminalTarget(
            bundleIdentifier: bundleIdentifier,
            processIdentifier: event.parentProcessID ?? existing?.terminal?.processIdentifier,
            tty: existing?.terminal?.tty
        )
    }

    private static func bundleIdentifier(for event: HookEventEnvelope) -> String? {
        guard event.provider == .claudeCode else { return nil }
        if event.clientSurface == .desktop {
            return "com.anthropic.claudefordesktop"
        }
        return switch event.terminalApplication {
        case .appleTerminal: "com.apple.Terminal"
        case .iTerm: "com.googlecode.iterm2"
        case .warp: "dev.warp.Warp-Stable"
        case .visualStudioCode: "com.microsoft.VSCode"
        case .visualStudioCodeInsiders: "com.microsoft.VSCodeInsiders"
        case .cursor: "com.todesktop.230313mzl4w4u92"
        case .ghostty: "com.mitchellh.ghostty"
        case .wezTerm: "com.github.wez.wezterm"
        case .kitty: "net.kovidgoyal.kitty"
        case .alacritty: "org.alacritty"
        case nil: nil
        }
    }
}
