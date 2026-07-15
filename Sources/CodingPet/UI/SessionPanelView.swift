import AppKit
import SwiftUI

enum SessionPanelLayout {
    static let width: CGFloat = 404
    static let maximumVisibleRows = 4
    static let rowHeight: CGFloat = 52
    static let emptyHeight: CGFloat = 170

    static func size(sessionCount: Int) -> NSSize {
        guard sessionCount > 0 else {
            return NSSize(width: width, height: emptyHeight)
        }
        let visibleRows = min(sessionCount, maximumVisibleRows)
        return NSSize(
            width: width,
            height: 80 + CGFloat(visibleRows) * rowHeight
        )
    }

    static func listHeight(sessionCount: Int) -> CGFloat {
        CGFloat(min(sessionCount, maximumVisibleRows)) * rowHeight
    }
}

struct SessionPanelView: View {
    @EnvironmentObject private var store: SessionStore
    @Environment(\.colorScheme) private var colorScheme

    let onSelect: (AgentSession) -> Void
    let onOpenSettings: () -> Void
    let usageSnapshot: CodexUsageSnapshot?

    init(
        usageSnapshot: CodexUsageSnapshot? = nil,
        onSelect: @escaping (AgentSession) -> Void,
        onOpenSettings: @escaping () -> Void = {}
    ) {
        self.usageSnapshot = usageSnapshot
        self.onSelect = onSelect
        self.onOpenSettings = onOpenSettings
    }

    var body: some View {
        let size = SessionPanelLayout.size(sessionCount: sortedSessions.count)

        VStack(spacing: 6) {
            HStack(spacing: 12) {
                if let usageSnapshot {
                    CodexUsageSummaryView(snapshot: usageSnapshot)
                        .transition(.opacity)
                }
                Spacer()
                settingsButton
            }
            .frame(height: 30)
            .animation(.easeOut(duration: 0.18), value: usageSnapshot)

            if sortedSessions.isEmpty {
                emptyState
            } else {
                sessionList
            }
        }
        .padding(10)
        .frame(width: 380, height: size.height - 24)
        .background(panelBackground)
        .overlay(panelBorder)
        .clipShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
        .shadow(color: .black.opacity(0.16), radius: 14, y: 7)
        .padding(12)
        .frame(width: size.width, height: size.height)
    }

    private var settingsButton: some View {
        Button(action: onOpenSettings) {
            Image(systemName: "gearshape.fill")
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(.secondary)
                .frame(width: 28, height: 28)
                .background(.primary.opacity(0.045), in: Circle())
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
                        session.provider == .claudeCode
                            ? "Claude Code sessions cannot be opened directly"
                            : "Open \(session.displayName)"
                    )

                    if index < sortedSessions.count - 1 {
                        Divider()
                            .opacity(0.42)
                            .padding(.leading, 44)
                    }
                }
            }
        }
        .scrollIndicators(.never)
        .frame(height: SessionPanelLayout.listHeight(sessionCount: sortedSessions.count))
        .background(.primary.opacity(colorScheme == .dark ? 0.045 : 0.022))
        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .stroke(.primary.opacity(0.055), lineWidth: 1)
        )
    }

    private var emptyState: some View {
        VStack(spacing: 7) {
            Image(systemName: "terminal")
                .font(.system(size: 16, weight: .medium))
                .foregroundStyle(.tertiary)
            Text("No active sessions")
                .font(.system(size: 13, weight: .semibold))
            Text("Start Codex or Claude Code in a terminal.")
                .font(.system(size: 11))
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .accessibilityElement(children: .combine)
    }

    private var panelBackground: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 22, style: .continuous)
                .fill(.ultraThinMaterial)
            RoundedRectangle(cornerRadius: 22, style: .continuous)
                .fill(
                    colorScheme == .dark
                        ? Color(red: 0.045, green: 0.052, blue: 0.068).opacity(0.88)
                        : Color.white.opacity(0.84)
                )
            LinearGradient(
                colors: [
                    store.botState.petAccent.opacity(0.045),
                    .clear
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
        }
    }

    private var panelBorder: some View {
        RoundedRectangle(cornerRadius: 22, style: .continuous)
            .strokeBorder(
                colorScheme == .dark
                    ? Color.white.opacity(0.10)
                    : Color.white.opacity(0.70),
                lineWidth: 1
            )
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

private struct CodexUsageSummaryView: View {
    let snapshot: CodexUsageSnapshot

    var body: some View {
        HStack(spacing: 6) {
            Text("Codex")
                .foregroundStyle(.secondary)

            ForEach(Array(snapshot.windows.prefix(2).enumerated()), id: \.offset) { index, window in
                if index > 0 {
                    Circle()
                        .fill(.tertiary.opacity(0.42))
                        .frame(width: 2.5, height: 2.5)
                        .accessibilityHidden(true)
                }

                Text(window.label)
                    .foregroundStyle(.tertiary)
                Text("\(window.remainingPercent)%")
                    .foregroundStyle(valueColor(for: window.remainingPercent))
                    .monospacedDigit()
            }
        }
        .font(.system(size: 10.5, weight: .medium))
        .fixedSize(horizontal: true, vertical: false)
        .accessibilityElement(children: .combine)
        .accessibilityLabel(accessibilityLabel)
    }

    private func valueColor(for remainingPercent: Int) -> Color {
        remainingPercent <= 20 ? .orange : .primary.opacity(0.72)
    }

    private var accessibilityLabel: String {
        let windows = snapshot.windows.prefix(2).map {
            "\($0.label) \($0.remainingPercent) percent remaining"
        }
        return "Codex usage, " + windows.joined(separator: ", ")
    }
}

private struct PanelIconButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .background(
                Color.primary.opacity(configuration.isPressed ? 0.07 : 0),
                in: Circle()
            )
            .scaleEffect(configuration.isPressed ? 0.96 : 1)
            .animation(.easeOut(duration: 0.12), value: configuration.isPressed)
    }
}

private struct SessionRow: View {
    @Environment(\.colorScheme) private var colorScheme

    let session: AgentSession
    @State private var isHovered = false

    var body: some View {
        HStack(spacing: 10) {
            statusMark

            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 7) {
                    Text(session.displayName)
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(.primary)
                        .lineLimit(1)

                    ProviderBadge(provider: session.provider)
                }

                HStack(spacing: 5) {
                    Text(session.summary)
                        .lineLimit(1)
                    Text("·")
                    Text(session.updatedAt, style: .relative)
                        .monospacedDigit()
                }
                .font(.system(size: 10.5, weight: .regular))
                .foregroundStyle(.secondary)
            }

            Spacer(minLength: 8)

            Text(session.status.displayName)
                .font(.system(size: 9.5, weight: .semibold))
                .foregroundStyle(statusColor)

            Image(
                systemName: session.provider == .claudeCode
                    ? "info.circle"
                    : "arrow.up.forward"
            )
                .font(.system(size: 9, weight: .semibold))
                .foregroundStyle(.secondary)
                .opacity(isHovered ? 0.90 : 0.34)
                .offset(x: isHovered ? 1.5 : 0, y: isHovered ? -1.5 : 0)
        }
        .padding(.horizontal, 12)
        .frame(height: SessionPanelLayout.rowHeight)
        .background(rowBackground)
        .contentShape(Rectangle())
        .onHover { isHovered = $0 }
        .animation(.easeOut(duration: 0.14), value: isHovered)
        .accessibilityElement(children: .combine)
        .accessibilityLabel(
            "\(session.displayName), \(session.provider.displayName), " +
            "\(session.status.displayName), \(session.summary)"
        )
    }

    private var statusMark: some View {
        ZStack {
            Circle()
                .fill(statusColor.opacity(0.10))
            Circle()
                .stroke(statusColor.opacity(0.22), lineWidth: 1)
            Image(systemName: session.status.compactSymbolName)
                .font(.system(size: 7.5, weight: .bold))
                .foregroundStyle(statusColor)
        }
        .frame(width: 22, height: 22)
    }

    private var statusColor: Color {
        switch session.status {
        case .running: BotState.running.petAccent
        case .needsInput: BotState.needsInput.petAccent
        case .ready: BotState.ready.petAccent
        case .blocked: BotState.blocked.petAccent
        }
    }

    private var rowBackground: some View {
        ZStack {
            session.provider.visualTint
                .opacity(colorScheme == .dark ? 0.065 : 0.042)
            Color.primary.opacity(isHovered ? 0.045 : 0)
        }
    }
}

private extension SessionStatus {
    var displayName: String {
        switch self {
        case .running: "Working"
        case .needsInput: "Input"
        case .ready: "Ready"
        case .blocked: "Blocked"
        }
    }

    var compactSymbolName: String {
        switch self {
        case .running: "bolt.fill"
        case .needsInput: "exclamationmark"
        case .ready: "checkmark"
        case .blocked: "xmark"
        }
    }
}
