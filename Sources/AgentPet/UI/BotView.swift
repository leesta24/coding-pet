import SwiftUI

struct BotView: View {
    @EnvironmentObject private var store: SessionStore
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var isBobbing = false

    let onTap: () -> Void

    var body: some View {
        Button(action: onTap) {
            ZStack(alignment: .topTrailing) {
                BotFace(state: store.botState)
                    .offset(y: isBobbing ? -3 : 3)

                if store.attentionCount > 0 {
                    Text("\(store.attentionCount)")
                        .font(.system(size: 12, weight: .bold, design: .rounded))
                        .foregroundStyle(.white)
                        .frame(minWidth: 22, minHeight: 22)
                        .background(.red, in: Circle())
                        .overlay(Circle().stroke(.white.opacity(0.85), lineWidth: 2))
                }
            }
            .frame(width: 92, height: 92)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .help("Show agent sessions")
        .onAppear {
            guard !reduceMotion else { return }
            withAnimation(.easeInOut(duration: 1.15).repeatForever(autoreverses: true)) {
                isBobbing = true
            }
        }
    }
}

private struct BotFace: View {
    let state: BotState

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 26, style: .continuous)
                .fill(
                    LinearGradient(
                        colors: [accent.opacity(0.95), accent.opacity(0.58)],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
                .shadow(color: accent.opacity(0.32), radius: 14, y: 7)

            VStack(spacing: 8) {
                HStack(spacing: 13) {
                    eye
                    eye
                }

                Capsule()
                    .fill(.white.opacity(0.94))
                    .frame(width: mouthWidth, height: 6)
            }
        }
        .padding(8)
        .accessibilityLabel(accessibilityLabel)
    }

    private var eye: some View {
        Circle()
            .fill(.white)
            .frame(width: 13, height: 18)
            .overlay(
                Circle()
                    .fill(.black.opacity(0.75))
                    .frame(width: 6, height: 8)
                    .offset(y: 2)
            )
    }

    private var accent: Color {
        switch state {
        case .idle: .gray
        case .running: .blue
        case .needsInput: .orange
        case .ready: .green
        case .blocked: .red
        }
    }

    private var mouthWidth: CGFloat {
        switch state {
        case .idle: 18
        case .running: 24
        case .needsInput: 12
        case .ready: 30
        case .blocked: 16
        }
    }

    private var accessibilityLabel: String {
        switch state {
        case .idle: "Agent Pet idle"
        case .running: "Agent working"
        case .needsInput: "Agent needs input"
        case .ready: "Agent task ready"
        case .blocked: "Agent task blocked"
        }
    }
}

