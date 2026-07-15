import AppKit

@MainActor
enum SessionNavigator {
    static func activate(_ session: AgentSession) {
        guard supportsDirectActivation(session) else { return }

        if session.provider == .codex {
            if let threadURL = codexThreadURL(for: session),
               NSWorkspace.shared.open(threadURL) {
                return
            }
            activateApplication(bundleIdentifier: codexBundleIdentifier)
            return
        }

        if let bundleIdentifier = preferredBundleIdentifier(for: session) {
            activateApplication(bundleIdentifier: bundleIdentifier)
            return
        }

        if let pid = session.terminal?.processIdentifier,
           let application = NSRunningApplication(processIdentifier: pid) {
            application.activate()
            return
        }

        if let bundleIdentifier = session.terminal?.bundleIdentifier,
           let application = NSRunningApplication
               .runningApplications(withBundleIdentifier: bundleIdentifier)
               .first {
            application.activate()
            return
        }

        NSWorkspace.shared.open(URL(fileURLWithPath: session.cwd))
    }

    static func supportsDirectActivation(_ session: AgentSession) -> Bool {
        session.provider == .codex || preferredBundleIdentifier(for: session) != nil
    }

    static func preferredBundleIdentifier(for session: AgentSession) -> String? {
        if session.provider == .codex {
            return codexBundleIdentifier
        }
        guard
              let bundleIdentifier = session.terminal?.bundleIdentifier,
              supportedClaudeTargets.contains(bundleIdentifier) else {
            return nil
        }
        return bundleIdentifier
    }

    static func codexThreadURL(for session: AgentSession) -> URL? {
        guard session.provider == .codex,
              session.codexThreadIsPersisted == true else {
            return nil
        }

        let prefix = "codex:"
        guard session.id.hasPrefix(prefix) else { return nil }

        let threadID = String(session.id.dropFirst(prefix.count))
        guard UUID(uuidString: threadID) != nil else { return nil }

        return URL(string: "codex://threads/\(threadID)")
    }

    private static let codexBundleIdentifier = "com.openai.codex"

    private static let supportedClaudeTargets: Set<String> = [
        "com.anthropic.claudefordesktop",
        "com.apple.Terminal",
        "com.googlecode.iterm2",
        "dev.warp.Warp-Stable",
        "com.microsoft.VSCode",
        "com.microsoft.VSCodeInsiders",
        "com.todesktop.230313mzl4w4u92",
        "com.mitchellh.ghostty",
        "com.github.wez.wezterm",
        "net.kovidgoyal.kitty",
        "org.alacritty"
    ]

    private static func activateApplication(bundleIdentifier: String) {
        if let application = NSRunningApplication
            .runningApplications(withBundleIdentifier: bundleIdentifier)
            .first {
            application.activate()
            return
        }
        guard let applicationURL = NSWorkspace.shared
            .urlForApplication(withBundleIdentifier: bundleIdentifier) else {
            return
        }
        let configuration = NSWorkspace.OpenConfiguration()
        configuration.activates = true
        NSWorkspace.shared.openApplication(
            at: applicationURL,
            configuration: configuration
        )
    }
}
