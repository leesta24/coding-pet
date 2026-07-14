import CodingPetBridge

struct NormalizedSessionState: Equatable {
    let status: SessionStatus
    let summary: String
}

protocol AgentSessionEventAdapter {
    func normalizedState(for event: HookEventEnvelope) -> NormalizedSessionState?
}
