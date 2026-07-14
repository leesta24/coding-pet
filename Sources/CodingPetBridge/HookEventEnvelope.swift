import Foundation

public enum HookProvider: String, Codable, CaseIterable, Sendable {
    case codex
    case claudeCode = "claude-code"
}

public struct HookEventEnvelope: Codable, Equatable, Sendable {
    public static let currentProtocolVersion = 1

    public let protocolVersion: Int
    public let provider: HookProvider
    public let eventName: String
    public let eventSubtype: String?
    public let timestamp: Date
    public let parentProcessID: Int32?
    public let sessionID: String
    public let cwd: String

    public init(
        protocolVersion: Int = currentProtocolVersion,
        provider: HookProvider,
        eventName: String,
        eventSubtype: String? = nil,
        timestamp: Date,
        parentProcessID: Int32?,
        sessionID: String,
        cwd: String
    ) {
        self.protocolVersion = protocolVersion
        self.provider = provider
        self.eventName = eventName
        self.eventSubtype = eventSubtype
        self.timestamp = timestamp
        self.parentProcessID = parentProcessID
        self.sessionID = sessionID
        self.cwd = cwd
    }

    /// Lifecycle boundaries that mean the provider is no longer actively
    /// working or explicitly waiting for user input.
    public var clearsActiveSession: Bool {
        switch eventName {
        case "SessionStart", "Stop", "SessionEnd", "StopFailure":
            true
        default:
            false
        }
    }
}

public enum HookEventCodec {
    public static func encode(_ event: HookEventEnvelope) throws -> Data {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.sortedKeys]
        return try encoder.encode(event)
    }

    public static func decode(_ data: Data) throws -> HookEventEnvelope {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return try decoder.decode(HookEventEnvelope.self, from: data)
    }
}
