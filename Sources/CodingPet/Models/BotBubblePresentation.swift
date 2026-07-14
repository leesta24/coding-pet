import Foundation

struct BotBubblePresentation: Equatable {
    static let maximumVisibleRows = 2

    let sessions: [AgentSession]
    let compactAttentionCount: Int

    init(
        sessions: [AgentSession],
        runningBubblesEnabled: Bool,
        pendingBubblesEnabled: Bool,
        readyBubblesEnabled: Bool
    ) {
        compactAttentionCount = sessions.count { session in
            switch session.status {
            case .needsInput:
                !pendingBubblesEnabled
            case .ready:
                !readyBubblesEnabled
            case .running, .blocked:
                false
            }
        }

        self.sessions = sessions
            .filter { session in
                switch session.status {
                case .needsInput:
                    pendingBubblesEnabled
                case .running:
                    runningBubblesEnabled
                case .ready:
                    readyBubblesEnabled
                case .blocked:
                    false
                }
            }
            .sorted(by: Self.precedes)
    }

    private static func precedes(_ lhs: AgentSession, _ rhs: AgentSession) -> Bool {
        let lhsPriority = priority(lhs.status)
        let rhsPriority = priority(rhs.status)
        if lhsPriority != rhsPriority {
            return lhsPriority < rhsPriority
        }
        if lhs.updatedAt != rhs.updatedAt {
            return lhs.updatedAt > rhs.updatedAt
        }
        return lhs.id < rhs.id
    }

    private static func priority(_ status: SessionStatus) -> Int {
        switch status {
        case .needsInput: 0
        case .ready: 1
        case .running: 2
        case .blocked: 3
        }
    }
}
