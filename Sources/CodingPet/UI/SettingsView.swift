import AppKit
import SwiftUI
import UniformTypeIdentifiers

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
            Rectangle()
                .fill(Theme.border)
                .frame(width: 1)
            detail
        }
        .frame(width: 760, height: 700)
        .background(Theme.surface)
    }

    private var sidebar: some View {
        VStack(alignment: .leading, spacing: 18) {
            HStack(spacing: 10) {
                PetAvatarView(
                    appearance: appearanceStore.selection,
                    state: sessionStore.botState,
                    size: 36,
                    animationsEnabled: appearanceStore.animationsEnabled
                )
                VStack(alignment: .leading, spacing: 1) {
                    Text("CodingPet")
                        .font(.system(size: 14, weight: .semibold))
                    Text("Settings")
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                }
            }
            .padding(.leading, 4)

            VStack(spacing: 2) {
                ForEach(SettingsDestination.allCases) { destination in
                    Button {
                        selection = destination
                    } label: {
                        HStack(spacing: 9) {
                            Image(systemName: destination.symbolName)
                                .font(.system(size: 13, weight: .regular))
                                .foregroundStyle(selection == destination ? .primary : .secondary)
                                .frame(width: 18)
                            Text(destination.title)
                                .font(.system(size: 13, weight: .medium))
                                .fixedSize(horizontal: true, vertical: false)
                            Spacer()
                        }
                        .padding(.horizontal, 10)
                        .frame(height: 30)
                        .contentShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                        .background(
                            selection == destination ? Color.primary.opacity(0.07) : .clear,
                            in: RoundedRectangle(cornerRadius: 8, style: .continuous)
                        )
                    }
                    .buttonStyle(.plain)
                    .accessibilityAddTraits(selection == destination ? .isSelected : [])
                }
            }

            Spacer()

            Button(role: .destructive, action: onQuit) {
                HStack(spacing: 8) {
                    Image(systemName: "power")
                    Text("Quit")
                    Spacer()
                }
                .frame(maxWidth: .infinity)
            }
            .buttonStyle(PillButtonStyle())
            .keyboardShortcut("q", modifiers: .command)
            .help("Quit CodingPet")

            Text("Local-first companion")
                .font(.system(size: 11))
                .foregroundStyle(.tertiary)
                .padding(.leading, 4)
        }
        .padding(16)
        .frame(width: 200)
        .frame(maxHeight: .infinity, alignment: .topLeading)
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
        case .appearance: "paintpalette"
        case .bubbles: "bubble.left"
        case .integrations: "link"
        case .about: "hand.raised"
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
            SettingsSection("Conversation bubbles") {
                SettingsGroup {
                    bubbleToggle(
                        title: "Running sessions",
                        detail: "Show working sessions as conversation bubbles. When off, running sessions stay hidden.",
                        status: .running,
                        isOn: $bubbleSettingsStore.runningBubblesEnabled
                    )
                    DashedDivider()
                    bubbleToggle(
                        title: "Pending input",
                        detail: "Show sessions explicitly waiting for you. When off, they collapse into the compact count.",
                        status: .needsInput,
                        isOn: $bubbleSettingsStore.pendingBubblesEnabled
                    )
                    DashedDivider()
                    bubbleToggle(
                        title: "Ready sessions",
                        detail: "Show completed sessions with unread activity. When off, they collapse into the compact count.",
                        status: .ready,
                        isOn: $bubbleSettingsStore.readyBubblesEnabled
                    )
                }
            }

            SettingsSection("How it works") {
                SettingsGroup {
                    SettingsRow(
                        symbol: "arrow.up.to.line",
                        title: "Pending input, Ready, then Running determines bubble order."
                    )
                    DashedDivider()
                    SettingsRow(
                        symbol: "rectangle.stack",
                        title: "At most two full bubbles appear at once."
                    )
                    DashedDivider()
                    SettingsRow(
                        symbol: "lock.shield",
                        title: "Bubbles use local session metadata, never transcript text."
                    )
                }
            }
        }
    }

    private func bubbleToggle(
        title: String,
        detail: String,
        status: SessionStatus,
        isOn: Binding<Bool>
    ) -> some View {
        SettingsRow(
            symbol: status.symbolName,
            symbolTint: status.tint,
            title: title,
            detail: detail
        ) {
            Toggle(title, isOn: isOn)
                .labelsHidden()
                .toggleStyle(.switch)
                .tint(Theme.accent)
        }
    }
}

private struct AppearanceSettingsView: View {
    @EnvironmentObject private var sessionStore: SessionStore
    @EnvironmentObject private var appearanceStore: PetAppearanceStore
    @State private var importReference = ""

    private let columns = [
        GridItem(.flexible(), spacing: 12),
        GridItem(.flexible(), spacing: 12)
    ]

    var body: some View {
        SettingsPage(
            title: "Appearance",
            subtitle: "Choose the companion that stays with your coding sessions."
        ) {
            SettingsSection("Pet library") {
                LazyVGrid(columns: columns, spacing: 12) {
                    ForEach(appearanceStore.availableAppearances) { appearance in
                        appearanceCard(appearance)
                    }
                }
            }

            SettingsSection("Import from codex-pets.net") {
                importSection
            }

            SettingsSection("Display") {
                SettingsGroup {
                    SettingsRow(
                        symbol: "arrow.up.left.and.arrow.down.right",
                        title: "Bot size",
                        detail: "Adjust how large the pet appears on screen."
                    ) {
                        HStack(spacing: 12) {
                            Slider(
                                value: botSizeBinding,
                                in: PetAppearanceStore.botSizeRange
                            )
                            .tint(Theme.accent)
                            .frame(width: 170)
                            .accessibilityLabel("Bot size")
                            .accessibilityValue("\(Int(appearanceStore.botSize)) points")

                            TagPill(text: "\(Int(appearanceStore.botSize)) pt", monospaced: true)
                                .frame(width: 52, alignment: .trailing)
                                .accessibilityHidden(true)
                        }
                    }
                    DashedDivider()
                    SettingsRow(
                        symbol: "waveform.path",
                        title: "Status animations",
                        detail: "Animate activity; macOS Reduce Motion still takes priority."
                    ) {
                        Toggle("Status animations", isOn: $appearanceStore.animationsEnabled)
                            .labelsHidden()
                            .toggleStyle(.switch)
                            .tint(Theme.accent)
                    }
                }
            }
        }
    }

    private var botSizeBinding: Binding<Double> {
        Binding(
            get: { appearanceStore.botSize },
            set: { appearanceStore.setBotSize(($0 / 4).rounded() * 4) }
        )
    }

    private var importSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 10) {
                TextField("Pet link or ID, e.g. codex-pets.net/#/pets/yuumi", text: $importReference)
                    .textFieldStyle(.roundedBorder)
                    .disabled(appearanceStore.isImporting)
                    .onSubmit(importFromReference)

                Button(action: importFromReference) {
                    if appearanceStore.isImporting {
                        ProgressView()
                            .controlSize(.small)
                            .frame(width: 44)
                    } else {
                        Text("Import")
                            .frame(width: 44)
                    }
                }
                .buttonStyle(PillButtonStyle(prominence: .primary))
                .disabled(appearanceStore.isImporting || trimmedImportReference.isEmpty)
                .accessibilityLabel("Import pet from codex-pets.net")
            }

            HStack {
                Button("Import .codex-pet.zip…", action: importFromArchive)
                    .buttonStyle(PillButtonStyle())
                    .disabled(appearanceStore.isImporting)
                Spacer()
                Link("Browse pets", destination: PetPackageImporter.siteBaseURL)
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(Theme.accent)
            }

            if let progress = appearanceStore.importProgress {
                VStack(alignment: .leading, spacing: 6) {
                    Text(progress.title)
                        .font(.system(size: 12))
                        .foregroundStyle(.secondary)
                        .monospacedDigit()
                    if let fraction = progress.fraction {
                        ProgressView(value: fraction)
                    } else {
                        ProgressView()
                    }
                }
                .progressViewStyle(.linear)
                .tint(Theme.accent)
                .accessibilityElement(children: .combine)
                .accessibilityLabel(progress.title)
            } else if let feedback = appearanceStore.importFeedback {
                let tint = feedback.kind == .success ? Theme.accent : Theme.danger
                Label(
                    feedback.message,
                    systemImage: feedback.kind == .success
                        ? "checkmark.circle"
                        : "exclamationmark.triangle"
                )
                .font(.system(size: 12))
                .foregroundStyle(tint)
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(tint.opacity(0.08), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
            }

            Text("Downloads pet.json and spritesheet.webp from codex-pets.net into ~/Library/Application Support/CodingPet/Pets only when you ask. Pets are shared by their creators; check each pet's page for usage rights.")
                .font(.system(size: 11.5))
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(14)
        .themeCard()
    }

    private var trimmedImportReference: String {
        importReference.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func importFromReference() {
        let reference = trimmedImportReference
        guard !reference.isEmpty, !appearanceStore.isImporting else { return }
        Task {
            await appearanceStore.importPet(reference: reference)
            if appearanceStore.importFeedback?.kind == .success {
                importReference = ""
            }
        }
    }

    private func importFromArchive() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.zip]
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = false
        panel.message = "Choose a .codex-pet.zip sprite kit"
        guard panel.runModal() == .OK, let url = panel.url else { return }
        Task { await appearanceStore.importPackage(at: url) }
    }

    private func appearanceCard(_ appearance: PetAppearance) -> some View {
        let isSelected = appearanceStore.selection == appearance
        return Button {
            appearanceStore.selection = appearance
        } label: {
            VStack(spacing: 10) {
                PetAvatarView(
                    appearance: appearance,
                    state: sessionStore.botState,
                    size: 120,
                    animationsEnabled: appearanceStore.animationsEnabled
                )
                .padding(.vertical, 12)
                .frame(maxWidth: .infinity)
                .background(Theme.surface, in: RoundedRectangle(cornerRadius: 9, style: .continuous))

                HStack(spacing: 8) {
                    Text(appearance.displayName)
                        .font(.system(size: 13, weight: .medium))
                    Spacer()
                    if isSelected {
                        TagPill(text: "Current", tint: Theme.accent)
                            .accessibilityHidden(true)
                    }
                }
                .padding(.horizontal, 2)
            }
            .padding(10)
            .frame(maxWidth: .infinity)
            .background(Theme.card, in: RoundedRectangle(cornerRadius: Theme.cardRadius, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: Theme.cardRadius, style: .continuous)
                    .strokeBorder(
                        isSelected ? Theme.accent : Theme.border,
                        lineWidth: isSelected ? 1.5 : 1
                    )
            )
            .contentShape(RoundedRectangle(cornerRadius: Theme.cardRadius, style: .continuous))
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Use \(appearance.accessibilityName)")
        .accessibilityValue(isSelected ? "Current pet" : "Available pet")
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }
}

struct IntegrationSettingsView: View {
    @EnvironmentObject private var integrationStore: IntegrationSettingsStore

    var body: some View {
        SettingsPage(
            title: "Integrations",
            subtitle: "Connect supported CLIs with local, non-blocking lifecycle hooks."
        ) {
            SettingsGroup {
                providerRow(
                    provider: .codex,
                    title: "Codex CLI",
                    detail: "~/.codex/hooks.json",
                    symbolName: "chevron.left.forwardslash.chevron.right"
                )
                DashedDivider()
                providerRow(
                    provider: .claudeCode,
                    title: "Claude Code",
                    detail: "~/.claude/settings.json",
                    symbolName: "terminal"
                )
            }

            if let feedback = integrationStore.feedback {
                let tint = feedback.kind == .success ? Theme.accent : Theme.danger
                Label(
                    feedback.message,
                    systemImage: feedback.kind == .success
                        ? "checkmark.circle"
                        : "exclamationmark.triangle"
                )
                .font(.system(size: 12))
                .foregroundStyle(tint)
                .padding(.horizontal, 14)
                .padding(.vertical, 10)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(tint.opacity(0.08), in: RoundedRectangle(cornerRadius: Theme.cardRadius, style: .continuous))
            }

            Button {
                integrationStore.refresh()
            } label: {
                Label("Refresh", systemImage: "arrow.clockwise")
            }
            .buttonStyle(PillButtonStyle())

            Label(
                "Codex installation records exact local hook hashes as trusted. Claude Code installs independently. CodingPet never approves or modifies a tool request.",
                systemImage: "lock.shield"
            )
            .font(.system(size: 11.5))
            .foregroundStyle(.secondary)
            .fixedSize(horizontal: false, vertical: true)
        }
        .onAppear { integrationStore.refresh() }
    }

    private func providerRow(
        provider: HookConfigurationProvider,
        title: String,
        detail: String,
        symbolName: String
    ) -> some View {
        let status = integrationStore.statuses[provider] ?? .notInstalled
        return SettingsRow(
            symbol: symbolName,
            symbolTint: status.color,
            title: title,
            detail: detail,
            monospacedDetail: true
        ) {
            HStack(spacing: 10) {
                TagPill(text: status.title, tint: status.color)
                providerAction(provider: provider, title: title, status: status)
            }
        }
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
            .buttonStyle(PillButtonStyle())
            .accessibilityLabel("Uninstall \(title) hooks")

        case .needsRepair:
            Button("Repair") {
                integrationStore.installOrRepair(provider)
            }
            .buttonStyle(PillButtonStyle(prominence: .primary))
            .accessibilityLabel("Repair \(title) hooks")

        case .notInstalled:
            Button("Install") {
                integrationStore.installOrRepair(provider)
            }
            .buttonStyle(PillButtonStyle(prominence: .primary))
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
            HStack(spacing: 16) {
                PetAvatarView(
                    appearance: appearanceStore.selection,
                    state: sessionStore.botState,
                    size: 80,
                    animationsEnabled: appearanceStore.animationsEnabled
                )
                VStack(alignment: .leading, spacing: 4) {
                    Text("CodingPet")
                        .font(.system(size: 18, weight: .semibold))
                    Text(appVersion)
                        .font(.system(size: 12))
                        .foregroundStyle(.secondary)
                    Text("macOS 14+ · Apple silicon")
                        .font(.system(size: 12))
                        .foregroundStyle(.secondary)
                }
            }

            SettingsGroup {
                SettingsRow(
                    symbol: "internaldrive",
                    title: "Local-only data",
                    detail: "Session metadata and preferences stay on this Mac. The only network request is a pet download from codex-pets.net that you start yourself."
                )
                DashedDivider()
                SettingsRow(
                    symbol: "eye.slash",
                    title: "No account or telemetry",
                    detail: "CodingPet does not upload prompts, code, diffs, or tool output."
                )
                DashedDivider()
                SettingsRow(
                    symbol: "terminal",
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
}

private struct SettingsPage<Content: View>: View {
    let title: String
    let subtitle: String
    @ViewBuilder let content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .font(.system(size: 20, weight: .semibold))
                Text(subtitle)
                    .font(.system(size: 12.5))
                    .foregroundStyle(.secondary)
            }
            content
            Spacer(minLength: 0)
        }
        .padding(28)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }
}

private struct SettingsSection<Content: View>: View {
    let title: String
    @ViewBuilder let content: Content

    init(_ title: String, @ViewBuilder content: () -> Content) {
        self.title = title
        self.content = content()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title)
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(.secondary)
                .padding(.leading, 2)
            content
        }
    }
}

/// White card holding rows separated by `DashedDivider`.
private struct SettingsGroup<Content: View>: View {
    @ViewBuilder let content: Content

    var body: some View {
        VStack(spacing: 0) {
            content
        }
        .padding(.horizontal, 14)
        .themeCard()
    }
}

private struct SettingsRow<Trailing: View>: View {
    let symbol: String
    var symbolTint: Color = .secondary
    let title: String
    var detail: String? = nil
    var monospacedDetail = false
    @ViewBuilder let trailing: Trailing

    init(
        symbol: String,
        symbolTint: Color = .secondary,
        title: String,
        detail: String? = nil,
        monospacedDetail: Bool = false,
        @ViewBuilder trailing: () -> Trailing = { EmptyView() }
    ) {
        self.symbol = symbol
        self.symbolTint = symbolTint
        self.title = title
        self.detail = detail
        self.monospacedDetail = monospacedDetail
        self.trailing = trailing()
    }

    var body: some View {
        HStack(alignment: .center, spacing: 12) {
            Image(systemName: symbol)
                .font(.system(size: 14, weight: .medium))
                .foregroundStyle(symbolTint)
                .frame(width: 20)

            VStack(alignment: .leading, spacing: 3) {
                Text(title)
                    .font(.system(size: 13, weight: .medium))
                    .fixedSize(horizontal: false, vertical: true)
                if let detail {
                    Text(detail)
                        .font(.system(size: 11.5, design: monospacedDetail ? .monospaced : .default))
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }

            Spacer(minLength: 16)

            trailing
        }
        .padding(.vertical, 13)
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

    var color: Color {
        switch self {
        case .notInstalled: .secondary
        case .installed: Theme.accent
        case .needsRepair: Theme.warning
        }
    }
}
