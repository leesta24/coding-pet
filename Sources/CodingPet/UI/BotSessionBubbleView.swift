import AppKit
import SwiftUI

struct BotSessionBubbleView: View {
    @EnvironmentObject private var sessionStore: SessionStore
    @EnvironmentObject private var settingsStore: SessionBubbleSettingsStore
    @EnvironmentObject private var appearanceStore: PetAppearanceStore

    let onSelect: (AgentSession) -> Void
    let onDismiss: (AgentSession) -> Void
    let onSelectCompact: () -> Void

    init(
        onSelect: @escaping (AgentSession) -> Void = { _ in },
        onDismiss: @escaping (AgentSession) -> Void = { _ in },
        onSelectCompact: @escaping () -> Void = {}
    ) {
        self.onSelect = onSelect
        self.onDismiss = onDismiss
        self.onSelectCompact = onSelectCompact
    }

    var body: some View {
        let presentation = BotBubblePresentation(
            sessions: sessionStore.bubbleSessions,
            runningBubblesEnabled: settingsStore.runningBubblesEnabled,
            pendingBubblesEnabled: settingsStore.pendingBubblesEnabled,
            readyBubblesEnabled: settingsStore.readyBubblesEnabled
        )

        VStack(alignment: .trailing, spacing: 8) {
            Spacer(minLength: 0)

            if !presentation.sessions.isEmpty {
                if presentation.sessions.count > BotBubblePresentation.maximumVisibleRows {
                    ScrollableSessionBubbleStack(
                        sessions: presentation.sessions,
                        animationsEnabled: appearanceStore.animationsEnabled,
                        onSelect: onSelect,
                        onDismiss: onDismiss
                    )
                } else {
                    StaticSessionBubbleStack(
                        sessions: presentation.sessions,
                        animationsEnabled: appearanceStore.animationsEnabled,
                        onSelect: onSelect,
                        onDismiss: onDismiss
                    )
                }
            }

            if presentation.compactAttentionCount > 0 {
                Button(action: onSelectCompact) {
                    CompactAttentionBubble(count: presentation.compactAttentionCount)
                }
                .buttonStyle(BubbleButtonStyle())
                .help("Show sessions that need attention")
                .padding(.trailing, 8)
                .transition(
                    .scale(scale: 0.76, anchor: .bottomTrailing)
                    .combined(with: .opacity)
                )
            }
        }
        .padding(.horizontal, 12)
        .padding(.bottom, 8)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottomTrailing)
        .animation(.spring(response: 0.30, dampingFraction: 0.86), value: presentation)
    }
}

private struct StaticSessionBubbleStack: View {
    let sessions: [AgentSession]
    let animationsEnabled: Bool
    let onSelect: (AgentSession) -> Void
    let onDismiss: (AgentSession) -> Void

    var body: some View {
        VStack(spacing: 8) {
            ForEach(sessions) { session in
                DismissibleSessionBubble(
                    session: session,
                    animationsEnabled: animationsEnabled,
                    onSelect: { onSelect(session) },
                    onDismiss: { onDismiss(session) }
                )
                .transition(.move(edge: .bottom).combined(with: .opacity))
            }
        }
        .padding(.top, 8)
    }
}

private struct ScrollableSessionBubbleStack: View {
    let sessions: [AgentSession]
    let animationsEnabled: Bool
    let onSelect: (AgentSession) -> Void
    let onDismiss: (AgentSession) -> Void

    private var viewportHeight: CGFloat {
        let visibleRows = min(sessions.count, BotBubblePresentation.maximumVisibleRows)
        return 8
            + CGFloat(visibleRows) * 64
            + CGFloat(max(visibleRows - 1, 0)) * 8
    }

    var body: some View {
        HiddenScrollerSessionBubbleList(
            sessions: sessions,
            animationsEnabled: animationsEnabled,
            onSelect: onSelect,
            onDismiss: onDismiss
        )
        .frame(width: 304, height: viewportHeight)
    }
}

@MainActor
enum BotBubbleScrollViewFactory {
    static func make() -> NSScrollView {
        let scrollView = NSScrollView(frame: .zero)
        scrollView.drawsBackground = false
        scrollView.backgroundColor = .clear
        scrollView.contentView.drawsBackground = false
        scrollView.contentView.backgroundColor = .clear
        scrollView.hasVerticalScroller = false
        scrollView.hasHorizontalScroller = false
        scrollView.autohidesScrollers = true
        scrollView.scrollerStyle = .overlay
        scrollView.horizontalScrollElasticity = .none
        scrollView.verticalScrollElasticity = .automatic
        makeTransparent(scrollView)
        makeTransparent(scrollView.contentView)
        return scrollView
    }

    static func makeTransparent(_ view: NSView) {
        view.wantsLayer = true
        view.layer?.backgroundColor = NSColor.clear.cgColor
        view.layer?.isOpaque = false
    }
}

@MainActor
private struct HiddenScrollerSessionBubbleList: NSViewRepresentable {
    let sessions: [AgentSession]
    let animationsEnabled: Bool
    let onSelect: (AgentSession) -> Void
    let onDismiss: (AgentSession) -> Void

    private var contentHeight: CGFloat {
        8 + CGFloat(sessions.count) * 64 + CGFloat(max(sessions.count - 1, 0)) * 8
    }

    func makeCoordinator() -> Coordinator {
        Coordinator()
    }

    func makeNSView(context: Context) -> NSScrollView {
        let scrollView = BotBubbleScrollViewFactory.make()
        updateHostingView(context.coordinator.hostingView)
        scrollView.documentView = context.coordinator.hostingView
        return scrollView
    }

    func updateNSView(_ scrollView: NSScrollView, context: Context) {
        let previousOrigin = scrollView.contentView.bounds.origin
        updateHostingView(context.coordinator.hostingView)

        let maximumY = max(0, contentHeight - scrollView.contentView.bounds.height)
        scrollView.contentView.scroll(
            to: NSPoint(x: 0, y: min(max(previousOrigin.y, 0), maximumY))
        )
        scrollView.reflectScrolledClipView(scrollView.contentView)
    }

    private func updateHostingView(_ hostingView: NSHostingView<AnyView>) {
        hostingView.rootView = AnyView(content.background(Color.clear))
        hostingView.frame = NSRect(x: 0, y: 0, width: 304, height: contentHeight)
        BotBubbleScrollViewFactory.makeTransparent(hostingView)
    }

    private var content: some View {
        VStack(spacing: 8) {
            ForEach(sessions) { session in
                DismissibleSessionBubble(
                    session: session,
                    animationsEnabled: animationsEnabled,
                    onSelect: { onSelect(session) },
                    onDismiss: { onDismiss(session) }
                )
                .id(session.id)
                .transition(.move(edge: .bottom).combined(with: .opacity))
            }
        }
        .padding(.top, 8)
        .frame(width: 304, height: contentHeight, alignment: .top)
    }

    @MainActor
    final class Coordinator {
        let hostingView: NSHostingView<AnyView>

        init() {
            hostingView = NSHostingView(
                rootView: AnyView(EmptyView().background(Color.clear))
            )
            hostingView.isFlipped = true
            BotBubbleScrollViewFactory.makeTransparent(hostingView)
        }
    }
}

private struct DismissibleSessionBubble: View {
    let session: AgentSession
    let animationsEnabled: Bool
    let onSelect: () -> Void
    let onDismiss: () -> Void

    @State private var isHovered = false

    var body: some View {
        ZStack(alignment: .topLeading) {
            Button(action: onSelect) {
                SessionConversationBubble(
                    session: session,
                    animationsEnabled: animationsEnabled,
                    isHovered: isHovered
                )
            }
            .buttonStyle(BubbleButtonStyle())
            .help(
                SessionNavigator.supportsDirectActivation(session)
                    ? "Open \(session.displayName)"
                    : "No application target is available for \(session.displayName)"
            )

            Button(action: onDismiss) {
                Image(systemName: "xmark")
                    .font(.system(size: 8, weight: .bold))
                    .foregroundStyle(Color.primary.opacity(0.60))
                    .frame(width: 20, height: 20)
                    .background(Theme.card, in: Circle())
                    .overlay(Circle().stroke(Theme.border, lineWidth: 1))
                    .shadow(color: .black.opacity(0.12), radius: 3, y: 1.5)
            }
            .buttonStyle(.plain)
            .offset(x: 2, y: 2)
            .opacity(isHovered ? 1 : 0)
            .scaleEffect(isHovered ? 1 : 0.82)
            .allowsHitTesting(isHovered)
            .help("Dismiss \(session.displayName) bubble")
            .accessibilityLabel("Dismiss \(session.displayName) bubble")
        }
        .onHover { isHovered = $0 }
        .animation(.easeOut(duration: 0.14), value: isHovered)
    }
}

private struct BubbleButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .contentShape(Rectangle())
            .scaleEffect(configuration.isPressed ? 0.988 : 1)
            .opacity(configuration.isPressed ? 0.90 : 1)
            .animation(.easeOut(duration: 0.10), value: configuration.isPressed)
    }
}

private struct SessionConversationBubble: View {
    let session: AgentSession
    let animationsEnabled: Bool
    let isHovered: Bool

    private var fallbackSummary: String {
        switch session.status {
        case .needsInput: "Waiting for your input"
        case .ready: "Completed — unread activity"
        case .running: "Working"
        case .blocked: "Blocked"
        }
    }

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            statusIndicator
                .frame(height: 18)

            VStack(alignment: .leading, spacing: 3) {
                Text(session.displayName)
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(.primary)
                    .lineLimit(1)
                    .frame(height: 18)

                HStack(alignment: .firstTextBaseline, spacing: 5) {
                    ProviderBadge(provider: session.provider)
                    Text(session.summary.isEmpty ? fallbackSummary : session.summary)
                        .lineLimit(session.status == .running ? 2 : 1)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .font(.system(size: 11))
                .foregroundStyle(.secondary)
            }

            Spacer(minLength: 8)

            StatusPill(status: session.status)
        }
        .padding(.horizontal, 14)
        .frame(width: 304, height: 64)
        .background {
            ZStack {
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .fill(.ultraThinMaterial)
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .fill(Theme.card.opacity(0.92))
            }
        }
        .overlay(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .strokeBorder(Theme.border, lineWidth: 1)
        )
        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
        .shadow(
            color: .black.opacity(isHovered ? 0.14 : 0.10),
            radius: isHovered ? 10 : 8,
            y: isHovered ? 4 : 3
        )
        .accessibilityElement(children: .combine)
        .accessibilityLabel(
            "\(session.displayName), \(session.provider.displayName), " +
            "\(session.summary.isEmpty ? fallbackSummary : session.summary)"
        )
    }

    @ViewBuilder
    private var statusIndicator: some View {
        if session.status == .running {
            RunningActivityIndicator(
                accent: .secondary,
                animationsEnabled: animationsEnabled
            )
        } else {
            Image(systemName: session.status.symbolName)
                .font(.system(size: 15, weight: .medium))
                .foregroundStyle(session.status.tint)
                .frame(width: 18, height: 18)
                .accessibilityHidden(true)
        }
    }
}

private struct RunningActivityIndicator: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    let accent: Color
    let animationsEnabled: Bool

    var body: some View {
        TimelineView(
            .animation(
                minimumInterval: 1.0 / 30.0,
                paused: !animationsEnabled || reduceMotion
            )
        ) { timeline in
            ZStack {
                Circle()
                    .stroke(accent.opacity(0.18), lineWidth: 1.5)
                Circle()
                    .trim(from: 0.08, to: 0.70)
                    .stroke(
                        accent,
                        style: StrokeStyle(lineWidth: 1.5, lineCap: .round)
                    )
                    .rotationEffect(rotation(at: timeline.date))
            }
        }
        .frame(width: 14, height: 14)
        .padding(2)
        .accessibilityHidden(true)
    }

    private func rotation(at date: Date) -> Angle {
        guard animationsEnabled, !reduceMotion else { return .degrees(-70) }
        let progress = date.timeIntervalSinceReferenceDate
            .truncatingRemainder(dividingBy: 1.1) / 1.1
        return .degrees(progress * 360 - 90)
    }
}

private struct CompactAttentionBubble: View {
    let count: Int

    var body: some View {
        Text(count > 99 ? "99+" : "\(count)")
            .font(.system(size: 11, weight: .bold))
            .foregroundStyle(.white)
            .padding(.horizontal, count > 9 ? 7 : 0)
            .frame(minWidth: 28, minHeight: 30, alignment: .top)
            .padding(.top, 4)
            .background(
                CompactSpeechBubbleShape()
                    .fill(Theme.danger)
            )
            .overlay(
                CompactSpeechBubbleShape()
                    .stroke(.white.opacity(0.82), lineWidth: 1)
            )
            .shadow(color: .black.opacity(0.14), radius: 4, y: 2)
            .accessibilityLabel("\(count) sessions need attention")
    }
}

private struct CompactSpeechBubbleShape: Shape {
    func path(in rect: CGRect) -> Path {
        let bodyHeight = rect.height - 6
        let bodyRect = CGRect(x: 0, y: 0, width: rect.width, height: bodyHeight)
        var path = Path(
            roundedRect: bodyRect,
            cornerRadius: min(11, bodyHeight / 2)
        )
        path.move(to: CGPoint(x: rect.maxX - 10, y: bodyHeight - 1))
        path.addLine(to: CGPoint(x: rect.maxX - 4, y: rect.maxY))
        path.addLine(to: CGPoint(x: rect.maxX - 3, y: bodyHeight - 6))
        path.closeSubpath()
        return path
    }
}
