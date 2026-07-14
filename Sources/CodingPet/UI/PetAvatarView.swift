import SwiftUI

struct PetAvatarView: View {
    let appearance: PetAppearance
    let state: BotState
    var size: CGFloat = 76
    var animationsEnabled = true

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        AtlasPetView(
            atlas: PetSpriteAtlas.available(for: appearance),
            state: state,
            animationsEnabled: animationsEnabled && !reduceMotion
        )
        .frame(width: size, height: size)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(appearance.accessibilityName), \(state.accessibilityStatus)")
    }
}

private struct AtlasPetView: View {
    let atlas: PetSpriteAtlas?
    let state: BotState
    let animationsEnabled: Bool

    var body: some View {
        if animationsEnabled {
            TimelineView(.animation(minimumInterval: 1.0 / 30.0)) { context in
                frame(at: context.date.timeIntervalSinceReferenceDate)
            }
        } else {
            frame(at: 0)
        }
    }

    @ViewBuilder
    private func frame(at elapsed: TimeInterval) -> some View {
        let animation = PetSpriteAnimation.animation(for: state)
        let column = animationsEnabled ? animation.frameIndex(elapsed: elapsed) : 0
        if let image = atlas?.frame(row: animation.row, column: column) {
            Image(nsImage: image)
                .interpolation(.high)
                .resizable()
                .scaledToFit()
        } else {
            PetFallbackView(state: state)
        }
    }
}

private struct PetFallbackView: View {
    let state: BotState

    var body: some View {
        Image(systemName: "pawprint.fill")
            .font(.system(size: 30, weight: .medium))
            .foregroundStyle(state.petAccent)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(state.petAccent.opacity(0.10), in: Circle())
    }
}

extension BotState {
    var petAccent: Color {
        switch self {
        case .idle: Color(red: 0.46, green: 0.50, blue: 0.58)
        case .running: Color(red: 0.18, green: 0.64, blue: 1.00)
        case .needsInput: Color(red: 1.00, green: 0.58, blue: 0.20)
        case .ready: Color(red: 0.20, green: 0.80, blue: 0.52)
        case .blocked: Color(red: 1.00, green: 0.30, blue: 0.38)
        }
    }

    var accessibilityStatus: String {
        switch self {
        case .idle: "idle"
        case .running: "agent working"
        case .needsInput: "agent needs input"
        case .ready: "agent task ready"
        case .blocked: "agent task blocked"
        }
    }
}
