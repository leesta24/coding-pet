import Combine
import Foundation
import CodingPetBridge

struct SessionBubbleVersion: Equatable {
    let status: SessionStatus
    let updatedAt: Date

    init(_ session: AgentSession) {
        status = session.status
        updatedAt = session.updatedAt
    }

    /// Running updates can arrive for every tool/message event, so dismissing
    /// one silences that session's running bubble until its state escalates.
    /// Attention states keep version-based dismissal so a genuinely newer
    /// attention event can notify again.
    func suppresses(_ session: AgentSession) -> Bool {
        guard status == session.status else { return false }
        return status == .running || updatedAt == session.updatedAt
    }
}

@MainActor
final class SessionStore: ObservableObject {
    @Published private(set) var sessions: [AgentSession]
    @Published private(set) var dismissedBubbleVersions: [String: SessionBubbleVersion] = [:]
    private var acknowledgedReadyVersions: [String: Date] = [:]

    init(sessions: [AgentSession] = []) {
        self.sessions = sessions
    }

    var activeSessions: [AgentSession] {
        sessions.filter { $0.status.isActive }
    }

    var bubbleSessions: [AgentSession] {
        sessions.filter {
            dismissedBubbleVersions[$0.id]?.suppresses($0) != true
        }
    }

    /// Hook-owned Codex rows whose lifecycle can be closed by a terminal turn.
    /// Unread Ready rows are a projection of Codex app state and must remain
    /// visible until Codex clears their unread marker.
    var codexLifecycleSessions: [AgentSession] {
        sessions.filter {
            $0.provider == .codex
                && ($0.status == .running || $0.status == .needsInput)
        }
    }

    var botState: BotState {
        BotStateReducer.reduce(activeSessions)
    }

    var attentionCount: Int {
        activeSessions.count {
            $0.status == .needsInput || $0.status == .ready
        }
    }

    func replaceSessions(_ sessions: [AgentSession]) {
        self.sessions = sessions
        pruneDismissedBubbleVersions()
    }

    func upsert(_ session: AgentSession) {
        if let index = sessions.firstIndex(where: { $0.id == session.id }) {
            sessions[index] = session
        } else {
            sessions.append(session)
        }
    }

    func updateSessionName(_ name: String, for id: String) {
        guard let index = sessions.firstIndex(where: { $0.id == id }) else { return }
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        sessions[index].sessionName = trimmed
    }

    func markCodexThreadPersisted(for id: String) {
        guard let index = sessions.firstIndex(where: { $0.id == id }),
              sessions[index].provider == .codex else {
            return
        }
        sessions[index].codexThreadIsPersisted = true
    }

    func updateRunningSummary(
        _ summary: String,
        for id: String,
        matching eventTimestamp: Date
    ) {
        guard let index = sessions.firstIndex(where: { $0.id == id }),
              sessions[index].status == .running,
              sessions[index].updatedAt == eventTimestamp else {
            return
        }
        let trimmed = summary.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        sessions[index].summary = trimmed
    }

    func apply(_ event: HookEventEnvelope) {
        let id = SessionEventRouter.sessionIdentifier(
            provider: event.provider,
            sessionID: event.sessionID
        )
        let existing = sessions.first { $0.id == id }
        guard existing?.updatedAt ?? .distantPast <= event.timestamp else { return }

        if event.clearsActiveSession {
            sessions.removeAll { $0.id == id }
            dismissedBubbleVersions.removeValue(forKey: id)
            return
        }

        guard let session = SessionEventRouter.session(for: event, existing: existing) else {
            return
        }
        upsert(session)
    }

    @discardableResult
    func removeSessions(
        provider: AgentProvider,
        notIn activeProviderSessionIDs: Set<String>
    ) -> [AgentSession] {
        var retained: [AgentSession] = []
        var removed: [AgentSession] = []
        for session in sessions {
            if session.provider == provider,
               !activeProviderSessionIDs.contains(session.providerSessionID) {
                removed.append(session)
            } else {
                retained.append(session)
            }
        }
        sessions = retained
        for session in removed {
            dismissedBubbleVersions.removeValue(forKey: session.id)
        }
        return removed
    }

    @discardableResult
    func removeDeadClaudeSessions(
        isAlive: (Int32) -> Bool = ProcessLivenessChecker.isAlive
    ) -> [AgentSession] {
        var retained: [AgentSession] = []
        var removed: [AgentSession] = []
        for session in sessions {
            let isLiveLifecycleState = session.status == .running
                || session.status == .needsInput
            if session.provider == .claudeCode,
               isLiveLifecycleState,
               let processIdentifier = session.terminal?.processIdentifier,
               !isAlive(processIdentifier) {
                removed.append(session)
            } else {
                retained.append(session)
            }
        }
        sessions = retained
        for session in removed {
            dismissedBubbleVersions.removeValue(forKey: session.id)
        }
        return removed
    }

    /// Removes a provider session only when it has not received a newer hook
    /// event than the lifecycle boundary being reconciled.
    @discardableResult
    func removeSession(
        provider: AgentProvider,
        providerSessionID: String,
        notUpdatedAfter cutoff: Date
    ) -> AgentSession? {
        guard let index = sessions.firstIndex(where: {
            $0.provider == provider
                && $0.providerSessionID == providerSessionID
                && $0.updatedAt <= cutoff
        }) else {
            return nil
        }
        let removed = sessions.remove(at: index)
        dismissedBubbleVersions.removeValue(forKey: removed.id)
        return removed
    }

    /// Reconciles only Codex Ready rows. Running/input rows are owned by hook
    /// events and are never removed or overwritten by the unread projection.
    func reconcileCodexReadyThreadIDs(_ unreadThreadIDs: Set<String>) -> [String] {
        sessions.removeAll {
            $0.provider == .codex
                && $0.status == .ready
                && !unreadThreadIDs.contains($0.providerSessionID)
        }
        pruneDismissedBubbleVersions()
        acknowledgedReadyVersions = acknowledgedReadyVersions.filter {
            unreadThreadIDs.contains($0.key)
        }

        return unreadThreadIDs.sorted().filter { threadID in
            !sessions.contains {
                $0.provider == .codex && $0.providerSessionID == threadID
            }
        }
    }

    func upsertCodexReadyThread(_ metadata: CodexThreadMetadata) {
        let id = SessionEventRouter.sessionIdentifier(
            provider: .codex,
            sessionID: metadata.id
        )
        if let existing = sessions.first(where: { $0.id == id }),
           existing.status != .ready {
            return
        }
        if let acknowledgedAt = acknowledgedReadyVersions[metadata.id],
           acknowledgedAt >= metadata.updatedAt {
            return
        }

        let projectName = URL(fileURLWithPath: metadata.cwd).lastPathComponent
        upsert(AgentSession(
            id: id,
            provider: .codex,
            projectName: projectName.isEmpty ? metadata.cwd : projectName,
            sessionName: metadata.name,
            cwd: metadata.cwd,
            status: .ready,
            summary: "Completed — unread activity",
            updatedAt: metadata.updatedAt,
            terminal: nil,
            codexThreadIsPersisted: true
        ))
    }

    @discardableResult
    func acknowledge(_ session: AgentSession) -> Bool {
        guard session.status == .ready else { return false }
        if session.provider == .codex {
            acknowledgedReadyVersions[session.providerSessionID] = session.updatedAt
        }
        sessions.removeAll { $0.id == session.id }
        dismissedBubbleVersions.removeValue(forKey: session.id)
        return true
    }

    func dismissBubble(for session: AgentSession) {
        guard sessions.contains(where: { $0.id == session.id }) else { return }
        dismissedBubbleVersions[session.id] = SessionBubbleVersion(session)
    }

    private func pruneDismissedBubbleVersions() {
        let currentIDs = Set(sessions.map(\.id))
        dismissedBubbleVersions = dismissedBubbleVersions.filter {
            currentIDs.contains($0.key)
        }
    }
}
