import CodingPetBridge

struct ClaudeCodeEventAdapter: AgentSessionEventAdapter {
    func normalizedState(for event: HookEventEnvelope) -> NormalizedSessionState? {
        guard event.provider == .claudeCode else { return nil }

        switch event.eventName {
        case "UserPromptSubmit":
            return NormalizedSessionState(status: .running, summary: "Working")
        case "PreToolUse":
            return NormalizedSessionState(
                status: .running,
                summary: event.activityKind?.claudeSummary ?? "Working"
            )
        case "PostToolUse":
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

private extension HookActivityKind {
    var claudeSummary: String {
        switch self {
        case .command: "Running command"
        case .editing: "Editing files"
        case .writing: "Writing files"
        case .reading: "Reading files"
        case .searching: "Searching project"
        case .browsing: "Browsing the web"
        case .delegating: "Delegating task"
        case .planning: "Planning"
        }
    }
}
