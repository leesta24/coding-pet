import SwiftUI

struct BotView: View {
    @EnvironmentObject private var store: SessionStore
    @EnvironmentObject private var appearanceStore: PetAppearanceStore
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var isBobbing = false
    @State private var isHovered = false

    let onTap: () -> Void

    private var botSize: CGFloat { CGFloat(appearanceStore.botSize) }

    var body: some View {
        Button(action: onTap) {
            PetAvatarView(
                appearance: appearanceStore.selection,
                state: store.botState,
                size: botSize,
                animationsEnabled: appearanceStore.animationsEnabled
            )
            .offset(y: isBobbing ? -3 : 3)
            .frame(width: botSize + 8, height: botSize + 8)
            .contentShape(Rectangle())
            .scaleEffect(isHovered ? 1.045 : 1)
        }
        .buttonStyle(.plain)
        .help("Show CodingPet sessions")
        .onHover { isHovered = $0 }
        .animation(.spring(response: 0.24, dampingFraction: 0.72), value: isHovered)
        .animation(.spring(response: 0.28, dampingFraction: 0.78), value: appearanceStore.selection)
        .onAppear {
            updateAnimation()
        }
        .onChange(of: appearanceStore.animationsEnabled) { _, _ in updateAnimation() }
        .onChange(of: reduceMotion) { _, _ in updateAnimation() }
    }

    private func updateAnimation() {
        guard appearanceStore.animationsEnabled, !reduceMotion else {
            withAnimation(nil) {
                isBobbing = false
            }
            return
        }
        isBobbing = false
        withAnimation(.easeInOut(duration: 1.15).repeatForever(autoreverses: true)) {
            isBobbing = true
        }
    }
}
