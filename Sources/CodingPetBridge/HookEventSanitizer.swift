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
        parentProcessID: Int32?
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
}

private struct SourcePayload: Decodable {
    let hookEventName: String?
    let sessionID: String?
    let cwd: String?
    let source: String?
    let notificationType: String?

    enum CodingKeys: String, CodingKey {
        case hookEventName = "hook_event_name"
        case sessionID = "session_id"
        case cwd
        case source
        case notificationType = "notification_type"
    }
}
