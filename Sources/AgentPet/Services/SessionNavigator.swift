import AppKit

@MainActor
enum SessionNavigator {
    static func activate(_ session: AgentSession) {
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
}

