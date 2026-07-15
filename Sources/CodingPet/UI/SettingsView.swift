import AppKit
import SwiftUI

struct SettingsView: View {
    @EnvironmentObject private var sessionStore: SessionStore
    @EnvironmentObject private var appearanceStore: PetAppearanceStore
    @EnvironmentObject private var bubbleSettingsStore: SessionBubbleSettingsStore
    @EnvironmentObject private var integrationStore: IntegrationSettingsStore
    @State private var selection: SettingsDestination = .appearance
    let onQuit: () -> Void

    init(onQuit: @escaping () -> Void = {}) {
        self.onQuit = onQuit
    }

    var body: some View {
        HStack(spacing: 0) {
            sidebar
            Divider()
            detail
        }
        .frame(width: 760, height: 700)
        .background(Color(nsColor: .windowBackgroundColor))
    }

    private var sidebar: some View {
        VStack(alignment: .leading, spacing: 18) {
            HStack(spacing: 10) {
                PetAvatarView(
                    appearance: appearanceStore.selection,
                    state: sessionStore.botState,
                    size: 38,
                    animationsEnabled: appearanceStore.animationsEnabled
                )
                VStack(alignment: .leading, spacing: 1) {
                    Text("CodingPet")
                        .font(.system(size: 15, weight: .bold, design: .rounded))
                    Text("Settings")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            VStack(spacing: 6) {
                ForEach(SettingsDestination.allCases) { destination in
                    Button {
                        selection = destination
                    } label: {
                        HStack(spacing: 10) {
                            Image(systemName: destination.symbolName)
                                .font(.system(size: 13, weight: .semibold))
                                .frame(width: 18)
                            Text(destination.title)
                                .font(.system(size: 12.5, weight: .semibold))
                            Spacer()
                        }
                        .padding(.horizontal, 10)
                        .frame(height: 34)
                        .foregroundStyle(selection == destination ? .primary : .secondary)
                        .background(
                            selection == destination
                                ? sessionStore.botState.petAccent.opacity(0.15)
                                : .clear,
                            in: RoundedRectangle(cornerRadius: 9, style: .continuous)
                        )
                    }
                    .buttonStyle(.plain)
                    .accessibilityAddTraits(selection == destination ? .isSelected : [])
                }
            }

            Spacer()

            Button(role: .destructive, action: onQuit) {
                HStack(spacing: 9) {
                    Image(systemName: "power")
                        .font(.system(size: 11.5, weight: .semibold))
                        .frame(width: 18)
                    Text("Quit")
                        .font(.system(size: 11.5, weight: .semibold))
                        .lineLimit(1)
                    Spacer()
                }
                .padding(.horizontal, 10)
                .frame(height: 32)
                .contentShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
            }
            .buttonStyle(.plain)
            .foregroundStyle(.secondary)
            .background(
                Color.primary.opacity(0.035),
                in: RoundedRectangle(cornerRadius: 8, style: .continuous)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .stroke(Color.primary.opacity(0.07), lineWidth: 1)
            )
            .keyboardShortcut("q", modifiers: .command)
            .help("Quit CodingPet")

            Text("Local-first companion")
                .font(.system(size: 10.5, weight: .medium))
                .foregroundStyle(.tertiary)
        }
        .padding(18)
        .frame(width: 178)
        .frame(maxHeight: .infinity, alignment: .topLeading)
        .background(Color.primary.opacity(0.028))
    }

    @ViewBuilder
    private var detail: some View {
        switch selection {
        case .appearance:
            AppearanceSettingsView()
        case .bubbles:
            SessionBubbleSettingsView()
        case .integrations:
            IntegrationSettingsView()
        case .about:
            AboutSettingsView()
        }
    }
}

private enum SettingsDestination: String, CaseIterable, Identifiable {
    case appearance
    case bubbles
    case integrations
    case about

    var id: Self { self }

    var title: String {
        switch self {
        case .appearance: "Appearance"
        case .bubbles: "Session Bubbles"
        case .integrations: "Integrations"
        case .about: "About & Privacy"
        }
    }

    var symbolName: String {
        switch self {
        case .appearance: "paintpalette.fill"
        case .bubbles: "ellipsis.bubble.fill"
        case .integrations: "point.3.connected.trianglepath.dotted"
        case .about: "hand.raised.fill"
        }
    }
}

struct SessionBubbleSettingsView: View {
    @EnvironmentObject private var bubbleSettingsStore: SessionBubbleSettingsStore

    var body: some View {
        SettingsPage(
            title: "Session Bubbles",
            subtitle: "Choose which live session updates appear beside your pet."
        ) {
            VStack(alignment: .leading, spacing: 10) {
                SettingsSectionLabel("CONVERSATION BUBBLES")

                bubbleToggle(
                    title: "Running sessions",
                    detail: "Show working sessions as conversation bubbles. When off, running sessions stay hidden.",
                    symbolName: "bolt.fill",
                    tint: Color(red: 0.17, green: 0.57, blue: 0.95),
                    isOn: $bubbleSettingsStore.runningBubblesEnabled
                )

                bubbleToggle(
                    title: "Pending input",
                    detail: "Show sessions explicitly waiting for you. When off, they collapse into the compact count.",
                    symbolName: "exclamationmark.bubble.fill",
                    tint: Color(red: 0.94, green: 0.25, blue: 0.29),
                    isOn: $bubbleSettingsStore.pendingBubblesEnabled
                )

                bubbleToggle(
                    title: "Ready sessions",
                    detail: "Show completed sessions with unread activity. When off, they collapse into the compact count.",
                    symbolName: "checkmark.circle.fill",
                    tint: Color(red: 0.18, green: 0.76, blue: 0.49),
                    isOn: $bubbleSettingsStore.readyBubblesEnabled
                )
            }

            VStack(alignment: .leading, spacing: 10) {
                SettingsSectionLabel("HOW IT WORKS")

                VStack(alignment: .leading, spacing: 14) {
                    Label("Pending input, Ready, then Running determines bubble order.", systemImage: "arrow.up.to.line")
                    Label("At most two full bubbles appear at once.", systemImage: "rectangle.stack.fill")
                    Label("Bubbles use local session metadata, never transcript text.", systemImage: "lock.shield.fill")
                }
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(.secondary)
                .settingsCard()
            }
        }
    }

    private func bubbleToggle(
        title: String,
        detail: String,
        symbolName: String,
        tint: Color,
        isOn: Binding<Bool>
    ) -> some View {
        HStack(spacing: 14) {
            Image(systemName: symbolName)
                .font(.system(size: 16, weight: .semibold))
                .foregroundStyle(tint)
                .frame(width: 40, height: 40)
                .background(tint.opacity(0.12), in: RoundedRectangle(cornerRadius: 11))

            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .font(.system(size: 13.5, weight: .semibold))
                Text(detail)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Spacer(minLength: 16)

            Toggle("", isOn: isOn)
                .labelsHidden()
                .toggleStyle(CodingPetSwitchStyle(tint: tint))
        }
        .settingsCard()
    }
}

private struct AppearanceSettingsView: View {
    @EnvironmentObject private var sessionStore: SessionStore
    @EnvironmentObject private var appearanceStore: PetAppearanceStore

    private let columns = [
        GridItem(.flexible(), spacing: 14),
        GridItem(.flexible(), spacing: 14)
    ]

    var body: some View {
        SettingsPage(
            title: "Appearance",
            subtitle: "Choose the companion that stays with your coding sessions."
        ) {
            VStack(alignment: .leading, spacing: 10) {
                SettingsSectionLabel("PET LIBRARY")
                LazyVGrid(columns: columns, spacing: 14) {
                    ForEach(appearanceStore.availableAppearances) { appearance in
                        appearanceCard(appearance)
                    }
                }
            }

            VStack(alignment: .leading, spacing: 10) {
                SettingsSectionLabel("DISPLAY")
                VStack(spacing: 14) {
                    HStack(alignment: .top, spacing: 14) {
                        Image(systemName: "arrow.up.left.and.arrow.down.right")
                            .font(.system(size: 15, weight: .semibold))
                            .foregroundStyle(sessionStore.botState.petAccent)
                            .frame(width: 36, height: 36)
                            .background(
                                sessionStore.botState.petAccent.opacity(0.12),
                                in: RoundedRectangle(cornerRadius: 10)
                            )
                            .padding(.top, 1)

                        VStack(alignment: .leading, spacing: 6) {
                            HStack {
                                Text("Bot size")
                                    .font(.system(size: 13, weight: .semibold))
                                Spacer()
                                Text("\(Int(appearanceStore.botSize)) pt")
                                    .font(.system(size: 10.5, weight: .bold, design: .rounded))
                                    .foregroundStyle(sessionStore.botState.petAccent)
                                    .padding(.horizontal, 8)
                                    .padding(.vertical, 4)
                                    .background(
                                        sessionStore.botState.petAccent.opacity(0.10),
                                        in: Capsule()
                                    )
                            }

                            VStack(spacing: 2) {
                                BotSizeSlider(
                                    value: botSizeBinding,
                                    range: PetAppearanceStore.botSizeRange,
                                    step: 4,
                                    tint: sessionStore.botState.petAccent
                                )

                                HStack {
                                    Text("\(Int(PetAppearanceStore.botSizeRange.lowerBound)) pt")
                                    Spacer()
                                    Text("\(Int(PetAppearanceStore.botSizeRange.upperBound)) pt")
                                }
                                .font(.system(size: 9, weight: .medium, design: .rounded))
                                .foregroundStyle(.tertiary)
                            }
                        }
                    }

                    Divider()

                    HStack(spacing: 14) {
                        Image(systemName: "waveform.path")
                            .font(.system(size: 16, weight: .semibold))
                            .foregroundStyle(sessionStore.botState.petAccent)
                            .frame(width: 36, height: 36)
                            .background(
                                sessionStore.botState.petAccent.opacity(0.12),
                                in: RoundedRectangle(cornerRadius: 10)
                            )

                        VStack(alignment: .leading, spacing: 3) {
                            Text("Status animations")
                                .font(.system(size: 13, weight: .semibold))
                            Text("Animate activity; macOS Reduce Motion still takes priority.")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }

                        Spacer()

                        Toggle("", isOn: $appearanceStore.animationsEnabled)
                            .labelsHidden()
                            .toggleStyle(CodingPetSwitchStyle(tint: sessionStore.botState.petAccent))
                    }
                }
                .settingsCard()
            }
        }
    }

    private var botSizeBinding: Binding<Double> {
        Binding(
            get: { appearanceStore.botSize },
            set: { appearanceStore.setBotSize($0) }
        )
    }

    private func appearanceCard(_ appearance: PetAppearance) -> some View {
        let isSelected = appearanceStore.selection == appearance
        return Button {
            appearanceStore.selection = appearance
        } label: {
            VStack(spacing: 0) {
                ZStack(alignment: .topTrailing) {
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .fill(
                            isSelected
                                ? sessionStore.botState.petAccent.opacity(0.10)
                                : Color.primary.opacity(0.028)
                        )

                    PetAvatarView(
                        appearance: appearance,
                        state: sessionStore.botState,
                        size: 126,
                        animationsEnabled: appearanceStore.animationsEnabled
                    )
                    .padding(.vertical, 12)

                    if isSelected {
                        Image(systemName: "checkmark")
                            .font(.system(size: 10, weight: .black))
                            .foregroundStyle(.white)
                            .frame(width: 22, height: 22)
                            .background(sessionStore.botState.petAccent, in: Circle())
                            .padding(10)
                            .accessibilityHidden(true)
                    }
                }

                HStack(spacing: 8) {
                    Text(appearance.displayName)
                        .font(.system(size: 13.5, weight: .bold, design: .rounded))
                    Spacer()
                    Text(isSelected ? "Current" : "")
                        .font(.system(size: 10.5, weight: .semibold))
                        .foregroundStyle(sessionStore.botState.petAccent)
                        .accessibilityHidden(true)
                }
                .padding(.horizontal, 4)
                .padding(.top, 10)
            }
            .padding(9)
            .frame(maxWidth: .infinity)
            .background(
                isSelected
                    ? sessionStore.botState.petAccent.opacity(0.075)
                    : Color.primary.opacity(0.018),
                in: RoundedRectangle(cornerRadius: 18, style: .continuous)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .stroke(
                        isSelected
                            ? sessionStore.botState.petAccent.opacity(0.78)
                            : Color.primary.opacity(0.09),
                        lineWidth: isSelected ? 2 : 1
                    )
            )
            .contentShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Use \(appearance.accessibilityName)")
        .accessibilityValue(isSelected ? "Current pet" : "Available pet")
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }
}

struct IntegrationSettingsView: View {
    @EnvironmentObject private var sessionStore: SessionStore
    @EnvironmentObject private var integrationStore: IntegrationSettingsStore

    var body: some View {
        SettingsPage(
            title: "Integrations",
            subtitle: "Connect supported CLIs with local, non-blocking lifecycle hooks."
        ) {
            VStack(spacing: 10) {
                providerCard(
                    provider: .codex,
                    title: "Codex CLI",
                    detail: "~/.codex/hooks.json",
                    symbolName: "chevron.left.forwardslash.chevron.right"
                )
                providerCard(
                    provider: .claudeCode,
                    title: "Claude Code",
                    detail: "~/.claude/settings.json",
                    symbolName: "terminal.fill"
                )
            }

            if let feedback = integrationStore.feedback {
                Label(
                    feedback.message,
                    systemImage: feedback.kind == .success
                        ? "checkmark.circle.fill"
                        : "exclamationmark.triangle.fill"
                )
                .font(.caption)
                .foregroundStyle(feedback.kind == .success ? .green : .red)
                .padding(12)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(
                    (feedback.kind == .success ? Color.green : Color.red).opacity(0.09),
                    in: RoundedRectangle(cornerRadius: 12)
                )
            }

            HStack {
                Button {
                    integrationStore.refresh()
                } label: {
                    Label("Refresh", systemImage: "arrow.clockwise")
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            Label(
                "Codex installation records exact local hook hashes as trusted. Claude Code installs independently. CodingPet never approves or modifies a tool request.",
                systemImage: "lock.shield.fill"
            )
            .font(.caption)
            .foregroundStyle(.secondary)
            .fixedSize(horizontal: false, vertical: true)
        }
        .onAppear { integrationStore.refresh() }
    }

    private func providerCard(
        provider: HookConfigurationProvider,
        title: String,
        detail: String,
        symbolName: String
    ) -> some View {
        let status = integrationStore.statuses[provider] ?? .notInstalled
        return HStack(spacing: 14) {
            Image(systemName: symbolName)
                .font(.system(size: 16, weight: .semibold))
                .foregroundStyle(status.color)
                .frame(width: 40, height: 40)
                .background(status.color.opacity(0.12), in: RoundedRectangle(cornerRadius: 11))

            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .font(.system(size: 13.5, weight: .semibold))
                Text(detail)
                    .font(.system(size: 10.5, design: .monospaced))
                    .foregroundStyle(.secondary)
            }

            Spacer()

            Label(status.title, systemImage: status.symbolName)
                .font(.system(size: 10.5, weight: .bold))
                .foregroundStyle(status.color)
                .padding(.horizontal, 9)
                .padding(.vertical, 5)
                .background(status.color.opacity(0.10), in: Capsule())

            providerAction(provider: provider, title: title, status: status)
        }
        .settingsCard()
    }

    @ViewBuilder
    private func providerAction(
        provider: HookConfigurationProvider,
        title: String,
        status: HookInstallationStatus
    ) -> some View {
        switch status {
        case .installed:
            Button("Uninstall", role: .destructive) {
                integrationStore.uninstall(provider)
            }
            .accessibilityLabel("Uninstall \(title) hooks")

        case .needsRepair:
            Button("Repair") {
                integrationStore.installOrRepair(provider)
            }
            .buttonStyle(.borderedProminent)
            .tint(.orange)
            .accessibilityLabel("Repair \(title) hooks")

        case .notInstalled:
            Button("Install") {
                integrationStore.installOrRepair(provider)
            }
            .buttonStyle(.borderedProminent)
            .tint(sessionStore.botState.petAccent)
            .accessibilityLabel("Install \(title) hooks")
        }
    }
}

private struct AboutSettingsView: View {
    @EnvironmentObject private var sessionStore: SessionStore
    @EnvironmentObject private var appearanceStore: PetAppearanceStore

    var body: some View {
        SettingsPage(
            title: "About & Privacy",
            subtitle: "A local companion for Codex CLI and Claude Code sessions."
        ) {
            HStack(spacing: 18) {
                PetAvatarView(
                    appearance: appearanceStore.selection,
                    state: sessionStore.botState,
                    size: 88,
                    animationsEnabled: appearanceStore.animationsEnabled
                )
                VStack(alignment: .leading, spacing: 5) {
                    Text("CodingPet")
                        .font(.system(size: 22, weight: .bold, design: .rounded))
                    Text(appVersion)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Text("macOS 14+ • Apple silicon")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            VStack(spacing: 10) {
                privacyRow(
                    symbol: "internaldrive.fill",
                    title: "Local-only data",
                    detail: "Session metadata and preferences stay on this Mac."
                )
                privacyRow(
                    symbol: "eye.slash.fill",
                    title: "No account or telemetry",
                    detail: "CodingPet does not upload prompts, code, diffs, or tool output."
                )
                privacyRow(
                    symbol: "terminal.fill",
                    title: "The CLI stays in control",
                    detail: "Approvals and replies always remain in the originating terminal."
                )
            }
        }
    }

    private var appVersion: String {
        if let version = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String {
            return "Version \(version)"
        }
        return "Development build"
    }

    private func privacyRow(symbol: String, title: String, detail: String) -> some View {
        HStack(spacing: 14) {
            Image(systemName: symbol)
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(sessionStore.botState.petAccent)
                .frame(width: 38, height: 38)
                .background(
                    sessionStore.botState.petAccent.opacity(0.11),
                    in: RoundedRectangle(cornerRadius: 10)
                )
            VStack(alignment: .leading, spacing: 3) {
                Text(title)
                    .font(.system(size: 13, weight: .semibold))
                Text(detail)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer()
        }
        .settingsCard()
    }
}

private struct SettingsPage<Content: View>: View {
    let title: String
    let subtitle: String
    @ViewBuilder let content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 22) {
            VStack(alignment: .leading, spacing: 5) {
                Text(title)
                    .font(.system(size: 24, weight: .bold, design: .rounded))
                Text(subtitle)
                    .font(.system(size: 12.5, weight: .medium))
                    .foregroundStyle(.secondary)
            }
            content
            Spacer(minLength: 0)
        }
        .padding(28)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }
}

private struct SettingsSectionLabel: View {
    let title: String

    init(_ title: String) {
        self.title = title
    }

    var body: some View {
        Text(title)
            .font(.system(size: 9.5, weight: .bold, design: .rounded))
            .tracking(1.05)
            .foregroundStyle(.secondary)
    }
}

private extension View {
    func settingsCard() -> some View {
        self
            .padding(14)
            .background(
                Color.primary.opacity(0.035),
                in: RoundedRectangle(cornerRadius: 14, style: .continuous)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .stroke(Color.primary.opacity(0.075), lineWidth: 1)
            )
    }
}

private struct CodingPetSwitchStyle: ToggleStyle {
    let tint: Color

    func makeBody(configuration: Configuration) -> some View {
        ZStack(alignment: configuration.isOn ? .trailing : .leading) {
            Capsule()
                .fill(configuration.isOn ? tint : Color.primary.opacity(0.14))
                .frame(width: 38, height: 22)

            Circle()
                .fill(.white)
                .frame(width: 18, height: 18)
                .padding(2)
                .shadow(color: .black.opacity(0.16), radius: 1.5, y: 1)
        }
        .contentShape(Capsule())
        .onTapGesture {
            configuration.isOn.toggle()
        }
        .animation(
            .spring(response: 0.22, dampingFraction: 0.82),
            value: configuration.isOn
        )
        .accessibilityValue(configuration.isOn ? "On" : "Off")
    }
}

private struct BotSizeSlider: View {
    @Binding var value: Double
    let range: ClosedRange<Double>
    let step: Double
    let tint: Color
    private let thumbSize: CGFloat = 16

    private var progress: CGFloat {
        CGFloat((value - range.lowerBound) / (range.upperBound - range.lowerBound))
    }

    var body: some View {
        GeometryReader { proxy in
            let width = proxy.size.width
            let travel = max(width - thumbSize, 1)
            let thumbCenterX = thumbSize / 2 + travel * progress

            ZStack {
                Canvas { context, size in
                    let trackY = (size.height - 4) / 2
                    let trackRect = CGRect(
                        x: 0,
                        y: trackY,
                        width: size.width,
                        height: 4
                    )
                    context.fill(
                        Path(roundedRect: trackRect, cornerRadius: 2),
                        with: .color(Color.primary.opacity(0.12))
                    )

                    let activeRect = CGRect(
                        x: 0,
                        y: trackY,
                        width: thumbCenterX,
                        height: 4
                    )
                    context.fill(
                        Path(roundedRect: activeRect, cornerRadius: 2),
                        with: .color(tint)
                    )
                }

                Circle()
                    .fill(.background)
                    .frame(width: thumbSize, height: thumbSize)
                    .overlay(Circle().stroke(tint, lineWidth: 2.5))
                    .shadow(color: .black.opacity(0.14), radius: 2, y: 1)
                    .position(x: thumbCenterX, y: proxy.size.height / 2)
            }
            .frame(width: width, height: proxy.size.height)
            .contentShape(Rectangle())
            .gesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { gesture in
                        updateValue(at: gesture.location.x, width: width)
                    }
            )
        }
        .frame(height: 22)
        .accessibilityElement()
        .accessibilityLabel("Bot size")
        .accessibilityValue("\(Int(value)) points")
        .accessibilityAdjustableAction { direction in
            switch direction {
            case .increment:
                value = min(value + step, range.upperBound)
            case .decrement:
                value = max(value - step, range.lowerBound)
            @unknown default:
                break
            }
        }
    }

    private func updateValue(at location: CGFloat, width: CGFloat) {
        let travel = max(width - thumbSize, 1)
        let normalized = min(max((location - thumbSize / 2) / travel, 0), 1)
        let rawValue = range.lowerBound
            + Double(normalized) * (range.upperBound - range.lowerBound)
        let steps = ((rawValue - range.lowerBound) / step).rounded()
        value = min(max(range.lowerBound + steps * step, range.lowerBound), range.upperBound)
    }
}

private extension HookInstallationStatus {
    var title: String {
        switch self {
        case .notInstalled: "Not installed"
        case .installed: "Installed"
        case .needsRepair: "Needs repair"
        }
    }

    var symbolName: String {
        switch self {
        case .notInstalled: "minus.circle.fill"
        case .installed: "checkmark.circle.fill"
        case .needsRepair: "exclamationmark.triangle.fill"
        }
    }

    var color: Color {
        switch self {
        case .notInstalled: .secondary
        case .installed: .green
        case .needsRepair: .orange
        }
    }
}
