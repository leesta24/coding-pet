import SwiftUI

extension AgentProvider {
    var shortDisplayName: String {
        switch self {
        case .codex: "Codex"
        case .claudeCode: "Claude"
        }
    }
}

struct ProviderBadge: View {
    let provider: AgentProvider

    var body: some View {
        Text(provider.shortDisplayName)
            .font(.system(size: 10, weight: .medium, design: .monospaced))
            .foregroundStyle(.secondary)
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .background(Theme.fill, in: Capsule())
            .fixedSize()
            .accessibilityLabel(provider.displayName)
    }
}
