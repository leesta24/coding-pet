import SwiftUI

extension AgentProvider {
    var shortDisplayName: String {
        switch self {
        case .codex: "Codex"
        case .claudeCode: "Claude"
        }
    }
}

/// Second line of a session row or bubble: `Claude · Editing files · 2m 37s`.
/// The summary is dropped when it only repeats the status shown in the pill.
struct SessionDetailLine: View {
    let session: AgentSession

    var body: some View {
        TimelineView(.periodic(from: .now, by: 1)) { context in
            HStack(spacing: 5) {
                Text(session.provider.shortDisplayName)
                    .fontWeight(.medium)
                if let summary = SessionDetailFormatter.meaningfulSummary(for: session) {
                    separator
                    Text(summary)
                        .lineLimit(1)
                }
                separator
                Text(SessionDetailFormatter.elapsedText(
                    from: session.elapsedReferenceDate,
                    to: context.date
                ))
                .monospacedDigit()
            }
        }
        .font(.system(size: 11))
        .foregroundStyle(.secondary)
        .lineLimit(1)
    }

    private var separator: some View {
        Text("·")
            .foregroundStyle(.tertiary)
            .accessibilityHidden(true)
    }
}

enum SessionDetailFormatter {
    static func meaningfulSummary(for session: AgentSession) -> String? {
        let summary = session.summary.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !summary.isEmpty else { return nil }
        let generic = [
            "working",
            "completed — ready to review",
            session.status.displayName.lowercased()
        ]
        return generic.contains(summary.lowercased()) ? nil : summary
    }

    /// Compact, single-token durations: `12s`, `2m 37s`, `1h 05m`, `3d`.
    static func elapsedText(from start: Date, to now: Date) -> String {
        let seconds = max(Int(now.timeIntervalSince(start).rounded(.down)), 0)
        switch seconds {
        case ..<60:
            return "\(seconds)s"
        case ..<3_600:
            return "\(seconds / 60)m \(seconds % 60)s"
        case ..<86_400:
            return String(format: "%dh %02dm", seconds / 3_600, (seconds % 3_600) / 60)
        default:
            return "\(seconds / 86_400)d"
        }
    }
}
