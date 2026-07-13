enum BotState: String, Equatable, Sendable {
    case idle
    case running
    case needsInput
    case ready
    case blocked
}

enum BotStateReducer {
    static func reduce<S: Sequence>(_ sessions: S) -> BotState where S.Element == AgentSession {
        let statuses = Set(sessions.map(\.status))

        if statuses.contains(.needsInput) { return .needsInput }
        if statuses.contains(.blocked) { return .blocked }
        if statuses.contains(.ready) { return .ready }
        if statuses.contains(.running) { return .running }
        return .idle
    }
}

