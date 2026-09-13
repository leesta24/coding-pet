import AppKit
import SwiftUI

/// Shared visual language: quiet neutral surfaces, one accent, pill-shaped
/// labels and buttons, dashed hairline dividers.
enum Theme {
    /// Page and outer-panel background (off-white / near-black).
    static let surface = Color.dynamic(
        light: NSColor(white: 0.965, alpha: 1),
        dark: NSColor(white: 0.125, alpha: 1)
    )
    /// Elevated card sitting on `surface`.
    static let card = Color.dynamic(
        light: .white,
        dark: NSColor(white: 0.175, alpha: 1)
    )
    static let border = Color.dynamic(
        light: NSColor(white: 0, alpha: 0.08),
        dark: NSColor(white: 1, alpha: 0.10)
    )
    static let hairline = Color.dynamic(
        light: NSColor(white: 0, alpha: 0.12),
        dark: NSColor(white: 1, alpha: 0.14)
    )
    /// Neutral fill for tags, hover states, and secondary buttons.
    static let fill = Color.primary.opacity(0.06)
    /// Primary button background and its label color.
    static let inverse = Color.dynamic(
        light: NSColor(white: 0.11, alpha: 1),
        dark: .white
    )
    static let inverseText = Color.dynamic(
        light: .white,
        dark: NSColor(white: 0.10, alpha: 1)
    )

    static let accent = Color(red: 0.16, green: 0.49, blue: 0.33)
    static let warning = Color(red: 0.80, green: 0.48, blue: 0.08)
    static let danger = Color(red: 0.80, green: 0.25, blue: 0.25)

    static let panelRadius: CGFloat = 20
    static let cardRadius: CGFloat = 12
}

extension Color {
    static func dynamic(light: NSColor, dark: NSColor) -> Color {
        Color(nsColor: NSColor(name: nil) { appearance in
            appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua ? dark : light
        })
    }
}

extension SessionStatus {
    var displayName: String {
        switch self {
        case .running: "Working"
        case .needsInput: "Waiting"
        case .ready: "Ready"
        case .blocked: "Blocked"
        }
    }

    var symbolName: String {
        switch self {
        case .running: "bolt"
        case .needsInput: "exclamationmark.circle"
        case .ready: "checkmark.circle"
        case .blocked: "xmark.circle"
        }
    }

    var tint: Color {
        switch self {
        case .running: .secondary
        case .needsInput: Theme.warning
        case .ready: Theme.accent
        case .blocked: Theme.danger
        }
    }
}

/// Small capsule label, e.g. "Approved" / "Planned" in the reference design.
struct TagPill: View {
    let text: String
    var tint: Color = .secondary
    var monospaced = false

    var body: some View {
        Text(text)
            .font(.system(size: 11, weight: .medium, design: monospaced ? .monospaced : .default))
            .foregroundStyle(tint)
            .padding(.horizontal, 8)
            .padding(.vertical, 3)
            .background(tint == .secondary ? Theme.fill : tint.opacity(0.11), in: Capsule())
            .fixedSize()
    }
}

struct StatusPill: View {
    let status: SessionStatus

    var body: some View {
        TagPill(text: status.displayName, tint: status.tint)
            .accessibilityLabel(status.displayName)
    }
}

struct DashedDivider: View {
    var body: some View {
        HairlineShape()
            .stroke(Theme.hairline, style: StrokeStyle(lineWidth: 1, dash: [3, 3]))
            .frame(height: 1)
            .accessibilityHidden(true)
    }

    private struct HairlineShape: Shape {
        func path(in rect: CGRect) -> Path {
            var path = Path()
            path.move(to: CGPoint(x: rect.minX, y: rect.midY))
            path.addLine(to: CGPoint(x: rect.maxX, y: rect.midY))
            return path
        }
    }
}

struct PillButtonStyle: ButtonStyle {
    enum Prominence {
        case primary
        case secondary
    }

    var prominence: Prominence = .secondary

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 12, weight: .medium))
            .foregroundStyle(prominence == .primary ? Theme.inverseText : .primary)
            .padding(.horizontal, 12)
            .frame(height: 28)
            .background(
                prominence == .primary ? Theme.inverse : Theme.fill,
                in: Capsule()
            )
            .opacity(configuration.isPressed ? 0.72 : 1)
            .animation(.easeOut(duration: 0.10), value: configuration.isPressed)
    }
}

extension View {
    /// White card with a hairline border, used on top of `Theme.surface`.
    func themeCard(cornerRadius: CGFloat = Theme.cardRadius) -> some View {
        self
            .background(Theme.card, in: RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .strokeBorder(Theme.border, lineWidth: 1)
            )
    }
}
