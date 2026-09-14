import Foundation

/// Usage limit windows reported by Claude Code's status line JSON
/// (`rate_limits.five_hour`, `rate_limits.seven_day`, `rate_limits.spend_limit`).
public struct HookRateLimitWindow: Codable, Equatable, Sendable {
    public let usedPercentage: Double
    public let resetsAt: Date?

    public init(usedPercentage: Double, resetsAt: Date?) {
        self.usedPercentage = usedPercentage
        self.resetsAt = resetsAt
    }
}

public struct HookRateLimits: Codable, Equatable, Sendable {
    public let fiveHour: HookRateLimitWindow?
    public let sevenDay: HookRateLimitWindow?
    public let spendLimit: HookRateLimitWindow?

    public init(
        fiveHour: HookRateLimitWindow? = nil,
        sevenDay: HookRateLimitWindow? = nil,
        spendLimit: HookRateLimitWindow? = nil
    ) {
        self.fiveHour = fiveHour
        self.sevenDay = sevenDay
        self.spendLimit = spendLimit
    }

    public var isEmpty: Bool {
        fiveHour == nil && sevenDay == nil && spendLimit == nil
    }
}

/// Turns the JSON Claude Code pipes to its status line command into a
/// `StatusLine` envelope carrying only the usage windows and routing fields.
public enum StatusLinePayloadParser {
    public static let eventName = "StatusLine"

    /// Returns nil when the payload carries no usage windows, so callers can
    /// skip the socket round-trip entirely.
    public static func envelope(
        from data: Data,
        timestamp: Date = .now
    ) -> HookEventEnvelope? {
        guard let payload = try? JSONDecoder().decode(Payload.self, from: data),
              let limits = payload.rateLimits else {
            return nil
        }
        let rateLimits = HookRateLimits(
            fiveHour: limits.fiveHour?.window,
            sevenDay: limits.sevenDay?.window,
            spendLimit: limits.spendLimit?.window
        )
        guard !rateLimits.isEmpty else { return nil }
        return HookEventEnvelope(
            provider: .claudeCode,
            eventName: eventName,
            timestamp: timestamp,
            parentProcessID: nil,
            sessionID: payload.sessionID ?? "status-line",
            cwd: payload.cwd ?? "",
            rateLimits: rateLimits
        )
    }

    private struct Payload: Decodable {
        struct Limits: Decodable {
            let fiveHour: Window?
            let sevenDay: Window?
            let spendLimit: Window?

            enum CodingKeys: String, CodingKey {
                case fiveHour = "five_hour"
                case sevenDay = "seven_day"
                case spendLimit = "spend_limit"
            }
        }

        struct Window: Decodable {
            let usedPercentage: Double?
            let resetsAt: Double?

            enum CodingKeys: String, CodingKey {
                case usedPercentage = "used_percentage"
                case resetsAt = "resets_at"
            }

            var window: HookRateLimitWindow? {
                guard let usedPercentage, usedPercentage.isFinite else { return nil }
                return HookRateLimitWindow(
                    usedPercentage: usedPercentage,
                    resetsAt: resetsAt.map(Date.init(timeIntervalSince1970:))
                )
            }
        }

        let sessionID: String?
        let cwd: String?
        let rateLimits: Limits?

        enum CodingKeys: String, CodingKey {
            case sessionID = "session_id"
            case cwd
            case rateLimits = "rate_limits"
        }
    }
}
