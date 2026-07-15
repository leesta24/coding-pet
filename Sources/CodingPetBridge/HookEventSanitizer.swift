import Foundation

public enum HookEventSanitizer {
    public enum Error: Swift.Error {
        case malformedPayload
        case missingRoutingField
    }

    public static func sanitize(
        _ data: Data,
        provider: HookProvider,
        timestamp: Date = .now,
        parentProcessID: Int32?,
        environment: [String: String] = [:]
    ) throws -> HookEventEnvelope {
        let payload: SourcePayload
        do {
            payload = try JSONDecoder().decode(SourcePayload.self, from: data)
        } catch {
            throw Error.malformedPayload
        }

        guard let eventName = required(payload.hookEventName, maximumLength: 128),
              let sessionID = required(payload.sessionID, maximumLength: 512),
              let cwd = required(payload.cwd, maximumLength: 4_096) else {
            throw Error.missingRoutingField
        }

        return HookEventEnvelope(
            provider: provider,
            eventName: eventName,
            eventSubtype: safeSubtype(payload.notificationType ?? payload.source),
            activityKind: provider == .claudeCode
                ? activityKind(for: payload.toolName)
                : nil,
            clientSurface: provider == .claudeCode
                ? clientSurface(environment: environment)
                : nil,
            terminalApplication: provider == .claudeCode
                ? terminalApplication(environment["TERM_PROGRAM"])
                : nil,
            timestamp: timestamp,
            parentProcessID: parentProcessID,
            sessionID: sessionID,
            cwd: cwd
        )
    }

    private static func required(_ value: String?, maximumLength: Int) -> String? {
        guard let value else { return nil }
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, trimmed.count <= maximumLength else { return nil }
        return trimmed
    }

    private static func safeSubtype(_ value: String?) -> String? {
        guard let value = required(value, maximumLength: 64) else { return nil }
        let allowed = CharacterSet.alphanumerics.union(CharacterSet(charactersIn: "_-"))
        guard value.unicodeScalars.allSatisfy(allowed.contains) else { return nil }
        return value
    }

    private static func activityKind(for toolName: String?) -> HookActivityKind? {
        switch toolName?.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() {
        case "bash": .command
        case "edit", "notebookedit": .editing
        case "write": .writing
        case "read": .reading
        case "grep", "glob": .searching
        case "webfetch", "websearch": .browsing
        case "task", "agent": .delegating
        case "todowrite": .planning
        default: nil
        }
    }

    private static func clientSurface(
        environment: [String: String]
    ) -> HookClientSurface? {
        let entrypoint = environment["CLAUDE_CODE_ENTRYPOINT"]?.lowercased()
        if entrypoint?.contains("desktop") == true {
            return .desktop
        }
        guard let terminal = terminalApplication(environment["TERM_PROGRAM"]) else {
            return entrypoint == "cli" ? .terminal : nil
        }
        switch terminal {
        case .visualStudioCode, .visualStudioCodeInsiders, .cursor:
            return .editor
        default:
            return .terminal
        }
    }

    private static func terminalApplication(
        _ value: String?
    ) -> HookTerminalApplication? {
        switch value?.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() {
        case "apple_terminal", "terminal", "terminal.app": .appleTerminal
        case "iterm.app", "iterm2": .iTerm
        case "warpterminal", "warp": .warp
        case "vscode": .visualStudioCode
        case "vscode-insiders": .visualStudioCodeInsiders
        case "cursor": .cursor
        case "ghostty": .ghostty
        case "wezterm": .wezTerm
        case "kitty": .kitty
        case "alacritty": .alacritty
        default: nil
        }
    }
}

private struct SourcePayload: Decodable {
    let hookEventName: String?
    let sessionID: String?
    let cwd: String?
    let source: String?
    let notificationType: String?
    let toolName: String?

    enum CodingKeys: String, CodingKey {
        case hookEventName = "hook_event_name"
        case sessionID = "session_id"
        case cwd
        case source
        case notificationType = "notification_type"
        case toolName = "tool_name"
    }
}
