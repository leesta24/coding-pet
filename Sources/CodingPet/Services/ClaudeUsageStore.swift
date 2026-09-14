import Combine
import Foundation
import Security
import CodingPetBridge

protocol ClaudeUsageReading: Sendable {
    func snapshot() async -> UsageSnapshot?
}

/// Reads Claude Code's own OAuth session from the local keychain and asks
/// Anthropic's usage endpoint for the current windows. This is the same data
/// the `/usage` command shows. Nothing is written back and the token never
/// leaves the request to api.anthropic.com.
actor ClaudeUsageReader: ClaudeUsageReading {
    typealias CredentialProvider = @Sendable () -> Data?
    typealias DataLoader = @Sendable (URLRequest) async throws -> (data: Data, statusCode: Int)

    static let usageURL = URL(string: "https://api.anthropic.com/api/oauth/usage")!
    static let keychainService = "Claude Code-credentials"
    static let credentialsFileURL = FileManager.default.homeDirectoryForCurrentUser
        .appending(path: ".claude/.credentials.json")

    private let credentialProvider: CredentialProvider
    private let loader: DataLoader

    init(
        credentialProvider: @escaping CredentialProvider = ClaudeUsageReader.localCredentials,
        loader: @escaping DataLoader = ClaudeUsageReader.defaultLoader
    ) {
        self.credentialProvider = credentialProvider
        self.loader = loader
    }

    func snapshot() async -> UsageSnapshot? {
        guard let credentials = credentialProvider(),
              let token = Self.accessToken(from: credentials) else {
            return nil
        }
        var request = URLRequest(url: Self.usageURL)
        request.httpMethod = "GET"
        request.timeoutInterval = 10
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.setValue("oauth-2025-04-20", forHTTPHeaderField: "anthropic-beta")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        // The endpoint rate-limits unknown clients far more aggressively.
        request.setValue("claude-code/2.1.0", forHTTPHeaderField: "User-Agent")

        guard let response = try? await loader(request),
              (200..<300).contains(response.statusCode) else {
            return nil
        }
        return Self.parseSnapshot(from: response.data)
    }

    /// Extracts `claudeAiOauth.accessToken`, ignoring tokens that have expired.
    static func accessToken(from credentials: Data, now: Date = .now) -> String? {
        guard let root = try? JSONSerialization.jsonObject(with: credentials) as? [String: Any],
              let oauth = root["claudeAiOauth"] as? [String: Any],
              let token = oauth["accessToken"] as? String,
              !token.isEmpty else {
            return nil
        }
        if let expiresAt = (oauth["expiresAt"] as? NSNumber)?.doubleValue {
            // Stored in milliseconds since 1970.
            let expiry = Date(timeIntervalSince1970: expiresAt / 1_000)
            guard expiry > now else { return nil }
        }
        return token
    }

    /// `five_hour` and `seven_day` carry `utilization` (0–100) and an ISO 8601 `resets_at`.
    static func parseSnapshot(from data: Data) -> UsageSnapshot? {
        guard let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            return nil
        }
        let windows = [
            parseWindow(root["five_hour"], label: "5h"),
            parseWindow(root["seven_day"], label: "Week")
        ].compactMap { $0 }
        return windows.isEmpty ? nil : UsageSnapshot(windows: windows)
    }

    private static func parseWindow(_ value: Any?, label: String) -> UsageSnapshot.Window? {
        guard let object = value as? [String: Any],
              let utilization = (object["utilization"] as? NSNumber)?.doubleValue,
              utilization.isFinite else {
            return nil
        }
        let used = Int(utilization.rounded())
        return UsageSnapshot.Window(
            label: label,
            remainingPercent: 100 - min(max(used, 0), 100),
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

    /// Keychain first (where Claude Code stores its login), then the legacy file.
    static let localCredentials: CredentialProvider = {
        let query: [CFString: Any] = [
            kSecClass: kSecClassGenericPassword,
            kSecAttrService: keychainService,
            kSecReturnData: true,
            kSecMatchLimit: kSecMatchLimitOne
        ]
        var item: CFTypeRef?
        if SecItemCopyMatching(query as CFDictionary, &item) == errSecSuccess,
           let data = item as? Data {
            return data
        }
        return try? Data(contentsOf: credentialsFileURL)
    }

    private static let defaultLoader: DataLoader = { request in
        let (data, response) = try await URLSession.shared.data(for: request)
        return (data, (response as? HTTPURLResponse)?.statusCode ?? 200)
    }
}

/// Claude Code usage windows, refreshed from the usage endpoint when the panel
/// opens and also pushed by CodingPetHook from terminal status lines.
@MainActor
final class ClaudeUsageStore: ObservableObject {
    /// The usage endpoint rate-limits polling; a panel toggle within this
    /// interval reuses the last answer.
    static let minimumRefreshInterval: TimeInterval = 60

    @Published private(set) var snapshot: UsageSnapshot?

    /// Nil means "never fetch": only the app's real launch path wires a
    /// reader, so tests and previews never touch the keychain or the network.
    private let reader: (any ClaudeUsageReading)?
    private(set) var refreshTask: Task<Void, Never>?
    private var lastRefreshedAt: Date?

    init(
        reader: (any ClaudeUsageReading)? = nil,
        initialSnapshot: UsageSnapshot? = nil
    ) {
        self.reader = reader
        snapshot = initialSnapshot
    }

    func refresh(now: Date = .now) {
        guard let reader else { return }
        if let lastRefreshedAt,
           now.timeIntervalSince(lastRefreshedAt) < Self.minimumRefreshInterval {
            return
        }
        lastRefreshedAt = now
        refreshTask?.cancel()
        refreshTask = Task { [weak self, reader] in
            let latest = await reader.snapshot()
            guard !Task.isCancelled, let latest else { return }
            self?.snapshot = latest
        }
    }

    func apply(_ event: HookEventEnvelope) {
        guard event.isStatusLine, let limits = event.rateLimits else { return }
        let windows = [
            Self.window(limits.fiveHour, label: "5h"),
            Self.window(limits.sevenDay, label: "Week")
        ].compactMap { $0 }
        guard !windows.isEmpty else { return }
        snapshot = UsageSnapshot(windows: windows)
    }

    private static func window(
        _ limit: HookRateLimitWindow?,
        label: String
    ) -> UsageSnapshot.Window? {
        guard let limit else { return nil }
        let used = Int(limit.usedPercentage.rounded())
        return UsageSnapshot.Window(
            label: label,
            remainingPercent: 100 - min(max(used, 0), 100),
            resetsAt: limit.resetsAt
        )
    }
}
