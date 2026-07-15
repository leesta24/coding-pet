import CodingPetBridge

struct ClaudeCodeEventAdapter: AgentSessionEventAdapter {
    func normalizedState(for event: HookEventEnvelope) -> NormalizedSessionState? {
        guard event.provider == .claudeCode else { return nil }

        switch event.eventName {
        case "UserPromptSubmit":
            return NormalizedSessionState(status: .running, summary: "Working")
        case "PreToolUse", "PostToolUse":
            return NormalizedSessionState(status: .running, summary: "Working")
        case "PermissionRequest":
            return NormalizedSessionState(status: .needsInput, summary: "Waiting for permission")
        case "Notification" where needsInputNotificationTypes.contains(event.eventSubtype):
            return NormalizedSessionState(status: .needsInput, summary: "Waiting for input")
        case "Stop":
            return NormalizedSessionState(status: .ready, summary: "Completed — ready to review")
        default:
            return nil
        }
    }

    private var needsInputNotificationTypes: Set<String?> {
        ["permission_prompt", "idle_prompt", "elicitation_dialog"]
    }
}
