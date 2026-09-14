import Foundation

/// The usage endpoint behind Claude Code's `/usage` command. CodingPetHook
/// calls it only when it inherits `CLAUDE_CODE_OAUTH_TOKEN` from a Claude
/// Desktop-spawned session; the token is used for that one request and is
/// never written anywhere or forwarded to the app.
public enum ClaudeUsageEndpoint {
    public static let url = URL(string: "https://api.anthropic.com/api/oauth/usage")!
    public static let tokenEnvironmentKey = "CLAUDE_CODE_OAUTH_TOKEN"
    /// The endpoint rate-limits aggressively; hooks fire far more often than this.
    public static let minimumInterval: TimeInterval = 60
    public static var defaultStampURL: URL {
        FileManager.default.homeDirectoryForCurrentUser
            .appending(path: "Library/Application Support/CodingPet/claude-usage.stamp")
    }

    public static func request(token: String) -> URLRequest {
        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.timeoutInterval = 8
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.setValue("oauth-2025-04-20", forHTTPHeaderField: "anthropic-beta")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        // Unknown user agents land in a much stricter rate-limit bucket.
        request.setValue("claude-code/2.1.0", forHTTPHeaderField: "User-Agent")
        return request
    }

    /// `five_hour` / `seven_day` carry `utilization` (0–100) and ISO 8601 `resets_at`.
    public static func rateLimits(from data: Data) -> HookRateLimits? {
        guard let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            return nil
        }
        let limits = HookRateLimits(
            fiveHour: window(root["five_hour"]),
            sevenDay: window(root["seven_day"])
        )
        return limits.isEmpty ? nil : limits
    }

    /// Records an attempt and reports whether enough time passed since the last one.
    /// Uses the stamp file's modification date so concurrent hooks share the throttle.
    public static func claimAttempt(
        stampURL: URL = defaultStampURL,
        now: Date = .now
    ) -> Bool {
        let fileManager = FileManager.default
        if let modified = (try? fileManager.attributesOfItem(atPath: stampURL.path))?[.modificationDate] as? Date,
           now.timeIntervalSince(modified) < minimumInterval {
            return false
        }
        try? fileManager.createDirectory(
            at: stampURL.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        guard fileManager.createFile(atPath: stampURL.path, contents: Data()) else { return false }
        try? fileManager.setAttributes([.modificationDate: now], ofItemAtPath: stampURL.path)
        return true
    }

    /// Overwrites a single diagnostic line (time and HTTP outcome, never the
    /// token or the body) so a silent failure can be checked after the fact.
    public static func log(_ message: String, at url: URL? = nil) {
        let logURL = url ?? defaultStampURL.deletingLastPathComponent()
            .appending(path: "claude-usage.log")
        let line = "\(ISO8601DateFormatter().string(from: .now)) \(message)\n"
        try? Data(line.utf8).write(to: logURL, options: .atomic)
    }

    private static func window(_ value: Any?) -> HookRateLimitWindow? {
        guard let object = value as? [String: Any],
              let utilization = (object["utilization"] as? NSNumber)?.doubleValue,
              utilization.isFinite else {
            return nil
        }
        return HookRateLimitWindow(
            usedPercentage: utilization,
            resetsAt: resetDate(object["resets_at"])
        )
    }

    private static func resetDate(_ value: Any?) -> Date? {
        if let number = value as? NSNumber {
            return Date(timeIntervalSince1970: number.doubleValue)
        }
        guard let string = value as? String else { return nil }
        let fractional = ISO8601DateFormatter()
        fractional.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return fractional.date(from: string) ?? ISO8601DateFormatter().date(from: string)
    }
}
