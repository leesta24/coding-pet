import Combine
import Foundation

@MainActor
final class SessionStore: ObservableObject {
    @Published private(set) var sessions: [AgentSession]

    init(sessions: [AgentSession] = []) {
        self.sessions = sessions
    }

    var botState: BotState {
        BotStateReducer.reduce(sessions)
    }

    var attentionCount: Int {
        sessions.count { $0.status == .needsInput || $0.status == .blocked }
    }

    func replaceSessions(_ sessions: [AgentSession]) {
        self.sessions = sessions
    }

    func upsert(_ session: AgentSession) {
        if let index = sessions.firstIndex(where: { $0.id == session.id }) {
            sessions[index] = session
        } else {
            sessions.append(session)
        }
    }
}

