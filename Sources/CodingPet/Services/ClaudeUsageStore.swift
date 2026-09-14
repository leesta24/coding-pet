import Combine
import Foundation
import CodingPetBridge

/// Claude Code usage windows, pushed by CodingPetHook each time Claude Code
/// refreshes its status line. No network access is involved.
@MainActor
final class ClaudeUsageStore: ObservableObject {
    @Published private(set) var snapshot: UsageSnapshot?

    init(initialSnapshot: UsageSnapshot? = nil) {
        snapshot = initialSnapshot
    }

    func apply(_ event: HookEventEnvelope) {
        guard event.isStatusLine, let limits = event.rateLimits else { return }
        let windows = [
            Self.window(limits.fiveHour, label: "5h"),
            Self.window(limits.sevenDay, label: "Week")
        ].compactMap { $0 }
        snapshot = windows.isEmpty ? nil : UsageSnapshot(windows: windows)
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
