import CodingPetBridge

struct CodexEventAdapter: AgentSessionEventAdapter {
    func normalizedState(for event: HookEventEnvelope) -> NormalizedSessionState? {
        guard event.provider == .codex else { return nil }

        switch event.eventName {
        case "UserPromptSubmit":
            return NormalizedSessionState(status: .running, summary: "Working")
        case "PreToolUse", "PostToolUse":
            return NormalizedSessionState(status: .running, summary: "Working")
        case "PermissionRequest":
            return NormalizedSessionState(status: .needsInput, summary: "Waiting for permission")
        default:
            return nil
        }
    }
}
