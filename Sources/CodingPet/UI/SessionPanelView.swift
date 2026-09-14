import AppKit
import SwiftUI

enum SessionPanelLayout {
    static let width: CGFloat = 404
    static let maximumVisibleRows = 4
    static let rowHeight: CGFloat = 52
    static let emptyHeight: CGFloat = 170
    /// Usage line (16pt) plus its spacing below the header.
    static let usageRowHeight: CGFloat = 22

    static func size(sessionCount: Int, showsUsage: Bool = false) -> NSSize {
        let usageHeight = showsUsage ? usageRowHeight : 0
        guard sessionCount > 0 else {
            return NSSize(width: width, height: emptyHeight + usageHeight)
        }
        let visibleRows = min(sessionCount, maximumVisibleRows)
        return NSSize(
            width: width,
            height: 80 + usageHeight + CGFloat(visibleRows) * rowHeight
        )
    }

    static func listHeight(sessionCount: Int) -> CGFloat {
        CGFloat(min(sessionCount, maximumVisibleRows)) * rowHeight
    }
}

struct SessionPanelView: View {
    @EnvironmentObject private var store: SessionStore

    let onSelect: (AgentSession) -> Void
    let onOpenSettings: () -> Void
    let usageSnapshot: UsageSnapshot?
    let claudeUsageSnapshot: UsageSnapshot?

    init(
        usageSnapshot: UsageSnapshot? = nil,
        claudeUsageSnapshot: UsageSnapshot? = nil,
        onSelect: @escaping (AgentSession) -> Void,
        onOpenSettings: @escaping () -> Void = {}
    ) {
        self.usageSnapshot = usageSnapshot
        self.claudeUsageSnapshot = claudeUsageSnapshot
        self.onSelect = onSelect
        self.onOpenSettings = onOpenSettings
    }

    private var showsUsage: Bool {
        usageSnapshot != nil || claudeUsageSnapshot != nil
    }

    var body: some View {
        let size = SessionPanelLayout.size(
            sessionCount: sortedSessions.count,
            showsUsage: showsUsage
        )

        VStack(spacing: 6) {
            header
                .frame(height: 26)

            if showsUsage {
                usageRow
                    .frame(height: SessionPanelLayout.usageRowHeight - 6)
            }

            if sortedSessions.isEmpty {
                emptyState
            } else {
                sessionList
            }
        }
        .padding(12)
        .frame(width: 380, height: size.height - 24)
        .background(Theme.surface, in: RoundedRectangle(cornerRadius: Theme.panelRadius, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: Theme.panelRadius, style: .continuous)
                .strokeBorder(Theme.border, lineWidth: 1)
        )
        .shadow(color: .black.opacity(0.12), radius: 12, y: 6)
        .padding(12)
        .frame(width: size.width, height: size.height)
    }

    private var header: some View {
        HStack(spacing: 6) {
            Text("Sessions")
                .font(.system(size: 14, weight: .semibold))
                .fixedSize()
                .padding(.leading, 2)

            if !sortedSessions.isEmpty {
                TagPill(
                    text: "\(sortedSessions.count) active",
                    monospaced: true
                )
                .accessibilityLabel("\(sortedSessions.count) active sessions")
            }

            Spacer()

            settingsButton
        }
    }

    private var usageRow: some View {
        HStack(spacing: 16) {
            if let usageSnapshot {
                UsageSummaryView(providerName: "Codex", snapshot: usageSnapshot)
            }
            if let claudeUsageSnapshot {
                UsageSummaryView(providerName: "Claude", snapshot: claudeUsageSnapshot)
            }
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 6)
        .animation(.easeOut(duration: 0.18), value: usageSnapshot)
        .animation(.easeOut(duration: 0.18), value: claudeUsageSnapshot)
    }

    private var settingsButton: some View {
        Button(action: onOpenSettings) {
            Image(systemName: "gearshape")
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(.secondary)
                .frame(width: 26, height: 26)
        }
        .buttonStyle(PanelIconButtonStyle())
        .help("Open CodingPet Settings")
        .accessibilityLabel("Open CodingPet Settings")
    }

    private var sessionList: some View {
        ScrollView {
            LazyVStack(spacing: 0) {
                ForEach(Array(sortedSessions.enumerated()), id: \.element.id) { index, session in
                    Button {
                        onSelect(session)
                    } label: {
                        SessionRow(session: session)
                    }
                    .buttonStyle(.plain)
                    .help(
                        SessionNavigator.supportsDirectActivation(session)
                            ? "Open \(session.displayName)"
                            : "No application target is available for \(session.displayName)"
                    )

                    if index < sortedSessions.count - 1 {
                        DashedDivider()
                            .padding(.horizontal, 14)
                    }
                }
            }
        }
        .scrollIndicators(.never)
        .frame(height: SessionPanelLayout.listHeight(sessionCount: sortedSessions.count))
        .themeCard()
    }

    private var emptyState: some View {
        VStack(spacing: 6) {
            Image(systemName: "terminal")
                .font(.system(size: 16, weight: .regular))
                .foregroundStyle(.tertiary)
            Text("No active sessions")
                .font(.system(size: 13, weight: .medium))
            Text("Start Codex or Claude Code in a terminal.")
                .font(.system(size: 11.5))
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .themeCard()
        .accessibilityElement(children: .combine)
    }

    private var sortedSessions: [AgentSession] {
        store.activeSessions.sorted {
            if priority($0.status) != priority($1.status) {
                return priority($0.status) < priority($1.status)
            }
            return $0.updatedAt > $1.updatedAt
        }
    }

    private func priority(_ status: SessionStatus) -> Int {
        switch status {
        case .needsInput: 0
        case .blocked: 1
        case .ready: 2
        case .running: 3
        }
    }
}

private struct UsageSummaryView: View {
    let providerName: String
    let snapshot: UsageSnapshot

    var body: some View {
        HStack(spacing: 6) {
            Text(providerName)
                .foregroundStyle(.secondary)

            ForEach(Array(snapshot.windows.prefix(2).enumerated()), id: \.offset) { index, window in
                if index > 0 {
                    Text("·")
                        .foregroundStyle(.tertiary)
                        .accessibilityHidden(true)
                }

                Text(window.label)
                    .foregroundStyle(.tertiary)
                Text("\(window.remainingPercent)%")
                    .foregroundStyle(valueColor(for: window.remainingPercent))
                    .monospacedDigit()
            }
        }
        .font(.system(size: 11, weight: .medium))
        .fixedSize(horizontal: true, vertical: false)
        .accessibilityElement(children: .combine)
        .accessibilityLabel(accessibilityLabel)
    }

    private func valueColor(for remainingPercent: Int) -> Color {
        remainingPercent <= 20 ? Theme.warning : .primary.opacity(0.72)
    }

    private var accessibilityLabel: String {
        let windows = snapshot.windows.prefix(2).map {
            "\($0.label) \($0.remainingPercent) percent remaining"
        }
        return "\(providerName) usage, " + windows.joined(separator: ", ")
    }
}

private struct PanelIconButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .background(
                Color.primary.opacity(configuration.isPressed ? 0.08 : 0),
                in: RoundedRectangle(cornerRadius: 7, style: .continuous)
            )
            .animation(.easeOut(duration: 0.12), value: configuration.isPressed)
    }
}

private struct SessionRow: View {
    let session: AgentSession
    @State private var isHovered = false

    var body: some View {
        // Top-aligned so the status indicator sits on the title line; the
        // provider lives on the detail line so titles never push it around.
        HStack(alignment: .top, spacing: 12) {
            VStack(alignment: .leading, spacing: 3) {
                Text(session.displayName)
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(.primary)
                    .lineLimit(1)
                    .frame(height: 18)

                SessionDetailLine(session: session)
            }

            Spacer(minLength: 8)

            SessionStatusIndicator(status: session.status, animationsEnabled: true)
                .frame(height: 18)

            Image(
                systemName: SessionNavigator.supportsDirectActivation(session)
                    ? "arrow.up.right"
                    : "info.circle"
            )
            .font(.system(size: 10, weight: .medium))
            .foregroundStyle(.secondary)
            .opacity(isHovered ? 0.9 : 0.35)
            .frame(height: 18)
        }
        .padding(.horizontal, 14)
        .frame(height: SessionPanelLayout.rowHeight)
        .background(Color.primary.opacity(isHovered ? 0.035 : 0))
        .contentShape(Rectangle())
        .onHover { isHovered = $0 }
        .animation(.easeOut(duration: 0.14), value: isHovered)
        .accessibilityElement(children: .combine)
        .accessibilityLabel(
            "\(session.displayName), \(session.provider.displayName), " +
            "\(session.status.displayName), \(session.summary)"
        )
    }
}
