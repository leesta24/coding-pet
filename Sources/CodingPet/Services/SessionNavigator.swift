import AppKit

@MainActor
enum SessionNavigator {
    static func activate(_ session: AgentSession) {
        if let threadURL = codexThreadURL(for: session),
           NSWorkspace.shared.open(threadURL) {
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

    static func codexThreadURL(for session: AgentSession) -> URL? {
        guard session.provider == .codex else { return nil }

        let prefix = "codex:"
        guard session.id.hasPrefix(prefix) else { return nil }

        let threadID = String(session.id.dropFirst(prefix.count))
        guard UUID(uuidString: threadID) != nil else { return nil }

        return URL(string: "codex://threads/\(threadID)")
    }
}
