import Foundation

enum AgentProvider: String, Codable, CaseIterable, Sendable {
    case codex
    case claudeCode

    var displayName: String {
        switch self {
        case .codex: "Codex"
        case .claudeCode: "Claude Code"
        }
    }
}

enum SessionStatus: String, Codable, CaseIterable, Sendable {
    case running
    case needsInput
    case ready
    case blocked
}

struct TerminalTarget: Codable, Hashable, Sendable {
    var bundleIdentifier: String?
    var processIdentifier: Int32?
    var tty: String?
}

struct AgentSession: Identifiable, Codable, Hashable, Sendable {
    let id: String
    let provider: AgentProvider
    let projectName: String
    let cwd: String
    var status: SessionStatus
    var summary: String
    var updatedAt: Date
    var terminal: TerminalTarget?
}

extension Array where Element == AgentSession {
    static var demo: [AgentSession] {
        [
            AgentSession(
                id: "codex-demo",
                provider: .codex,
                projectName: "agent-pet",
                cwd: FileManager.default.currentDirectoryPath,
                status: .needsInput,
                summary: "Waiting for approval",
                updatedAt: .now,
                terminal: TerminalTarget(
                    bundleIdentifier: "com.apple.Terminal",
                    processIdentifier: nil,
                    tty: nil
                )
            ),
            AgentSession(
                id: "claude-demo",
                provider: .claudeCode,
                projectName: "landing-page",
                cwd: FileManager.default.homeDirectoryForCurrentUser.path,
                status: .running,
                summary: "Running tests",
                updatedAt: .now.addingTimeInterval(-32),
                terminal: nil
            )
        ]
    }
}

