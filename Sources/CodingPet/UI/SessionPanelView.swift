import SwiftUI

struct SessionPanelView: View {
    @EnvironmentObject private var store: SessionStore

    let onSelect: (AgentSession) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                Text("Agent Sessions")
                    .font(.system(size: 18, weight: .semibold, design: .rounded))
                Spacer()
                Text("\(store.sessions.count)")
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(.secondary)
            }

            if store.sessions.isEmpty {
                ContentUnavailableView(
                    "No active sessions",
                    systemImage: "terminal",
                    description: Text("Start Codex or Claude Code in a terminal.")
                )
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                ScrollView {
                    LazyVStack(spacing: 8) {
                        ForEach(sortedSessions) { session in
                            Button {
                                onSelect(session)
                            } label: {
                                SessionRow(session: session)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }
            }
        }
        .padding(18)
        .frame(width: 360, height: 320)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 24, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 24, style: .continuous)
                .stroke(.white.opacity(0.18), lineWidth: 1)
        )
    }

    private var sortedSessions: [AgentSession] {
        store.sessions.sorted {
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

private struct SessionRow: View {
    let session: AgentSession

    var body: some View {
        HStack(spacing: 12) {
            Circle()
                .fill(statusColor)
                .frame(width: 10, height: 10)

            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 7) {
                    Text(session.projectName)
                        .font(.system(size: 14, weight: .semibold))
                    Text(session.provider.displayName)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
                Text(session.summary)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }

            Spacer()

            Image(systemName: "arrow.up.forward.app")
                .foregroundStyle(.secondary)
        }
        .padding(12)
        .background(.white.opacity(0.07), in: RoundedRectangle(cornerRadius: 14))
        .contentShape(RoundedRectangle(cornerRadius: 14))
    }

    private var statusColor: Color {
        switch session.status {
        case .running: .blue
        case .needsInput: .orange
        case .ready: .green
        case .blocked: .red
        }
    }
}

