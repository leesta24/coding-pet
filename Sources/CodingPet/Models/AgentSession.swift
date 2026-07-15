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

    var isActive: Bool {
        self == .running || self == .needsInput || self == .ready
    }
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
    var sessionName: String? = nil
    let cwd: String
    var status: SessionStatus
    var summary: String
    var updatedAt: Date
    var turnStartedAt: Date? = nil
    var terminal: TerminalTarget?
    var codexThreadIsPersisted: Bool? = nil

    var displayName: String {
        if let sessionName, !sessionName.isEmpty {
            return sessionName
        }
        if provider == .claudeCode {
            return "Untitled session"
        }
        let trimmedProjectName = projectName.trimmingCharacters(
            in: .whitespacesAndNewlines
        )
        return trimmedProjectName.isEmpty || trimmedProjectName == "/"
            ? "Codex task"
            : trimmedProjectName
    }

    var providerSessionID: String {
        guard let separator = id.firstIndex(of: ":") else { return id }
        return String(id[id.index(after: separator)...])
    }

    var elapsedReferenceDate: Date {
        status == .running ? turnStartedAt ?? updatedAt : updatedAt
    }
}

extension Array where Element == AgentSession {
    static var demo: [AgentSession] {
        [
            AgentSession(
                id: "codex-demo",
                provider: .codex,
                projectName: "coding-pet",
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
