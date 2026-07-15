import SwiftUI

extension AgentProvider {
    var shortDisplayName: String {
        switch self {
        case .codex: "Codex"
        case .claudeCode: "Claude"
        }
    }

    var visualTint: Color {
        switch self {
        case .codex:
            Color(red: 0.34, green: 0.64, blue: 0.94)
        case .claudeCode:
            Color(red: 0.91, green: 0.66, blue: 0.27)
        }
    }

    var labelTint: Color {
        switch self {
        case .codex:
            Color(red: 0.18, green: 0.48, blue: 0.84)
        case .claudeCode:
            Color(red: 0.82, green: 0.51, blue: 0.10)
        }
    }
}

struct ProviderBadge: View {
    let provider: AgentProvider

    var body: some View {
        Text(provider.shortDisplayName.uppercased())
            .font(.system(size: 8, weight: .semibold))
            .tracking(0.35)
            .foregroundStyle(provider.labelTint)
            .padding(.horizontal, 5)
            .padding(.vertical, 2)
            .background(provider.visualTint.opacity(0.10), in: Capsule())
            .overlay(
                Capsule()
                    .stroke(provider.visualTint.opacity(0.16), lineWidth: 0.5)
            )
            .fixedSize()
            .accessibilityLabel(provider.displayName)
    }
}
