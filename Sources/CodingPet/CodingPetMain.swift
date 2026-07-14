import AppKit
import Darwin
import CodingPetBridge

@main
enum CodingPetMain {
    @MainActor
    static func main() {
        if runHookManagementCommandIfPresent() {
            return
        }

        let application = NSApplication.shared
        let delegate = AppDelegate()

        application.setActivationPolicy(.accessory)
        application.delegate = delegate
        application.run()
    }

    @MainActor
    private static func runHookManagementCommandIfPresent() -> Bool {
        let arguments = Set(CommandLine.arguments.dropFirst())
        let shouldInstall = arguments.contains("--install-hooks")
        let shouldUninstall = arguments.contains("--uninstall-hooks")
        guard shouldInstall || shouldUninstall else { return false }
        guard shouldInstall != shouldUninstall,
              let executableURL = Bundle.main.executableURL else {
            writeError("Specify exactly one of --install-hooks or --uninstall-hooks.")
            Darwin.exit(2)
        }

        let hookURL = AppBundlePaths.hookExecutableURL(for: executableURL)
        let coordinator = HookInstallationCoordinator(hookExecutableURL: hookURL)
        do {
            if shouldInstall {
                let report = try coordinator.install()
                print("CodingPet hooks installed and trusted (\(report.trustedCodexHookCount) Codex hooks).")
                if report.removedAgentPeekHandlerCount > 0 || report.removedAgentPeekStateCount > 0 {
                    print("AgentPeek hooks and their Codex trust entries were removed.")
                }
            } else {
                try coordinator.uninstall()
                print("CodingPet hooks uninstalled.")
            }
        } catch {
            writeError("CodingPet hook configuration failed: \(error)")
            Darwin.exit(1)
        }
        return true
    }

    private static func writeError(_ message: String) {
        FileHandle.standardError.write(Data("\(message)\n".utf8))
    }
}

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private struct CodexLifecycleCandidate: Sendable {
        let sessionID: String
        let updatedAt: Date
    }

    private static let lifecycleReconciliationInterval: UInt64 = 3_000_000_000
    private static let catalogReconciliationFrequency = 5

    private let sessionStore: SessionStore
    private let eventSnapshotStore = HookEventSnapshotStore()
    private let codexSessionNameResolver = CodexSessionNameResolver()
    private let codexActivityMessageResolver = CodexActivityMessageResolver()
    private let codexThreadCatalog = CodexThreadCatalog()
    private let codexUnreadStateReader = CodexUnreadStateReader()
    private var botWindowController: BotWindowController?
    private var hookEventListener: HookEventListener?
    private var sessionReconciliationTask: Task<Void, Never>?

    override init() {
        if CommandLine.arguments.contains("--demo") {
            sessionStore = SessionStore(sessions: .demo)
        } else {
            sessionStore = SessionStore()
        }
        super.init()
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        let resolver = codexSessionNameResolver
        let isDemo = CommandLine.arguments.contains("--demo")
        let storedEvents = isDemo ? [] : eventSnapshotStore.snapshots()
        hookEventListener = try? HookEventListener { [weak self] event in
            self?.apply(event, resolvingNameWith: resolver)
        }
        let snapshots = eventSnapshotStore
        botWindowController = BotWindowController(
            store: sessionStore,
            onAcknowledge: { session in
                snapshots.remove(
                    provider: session.provider == .codex ? .codex : .claudeCode,
                    sessionID: session.providerSessionID
                )
            }
        )
        botWindowController?.show()

        if !isDemo {
            startSessionReconciliation(storedEvents: storedEvents, resolver: resolver)
        }
    }

    func applicationWillTerminate(_ notification: Notification) {
        sessionReconciliationTask?.cancel()
        hookEventListener?.stop()
    }

    private func startSessionReconciliation(
        storedEvents: [HookEventEnvelope],
        resolver: CodexSessionNameResolver
    ) {
        let catalog = codexThreadCatalog
        sessionReconciliationTask = Task { [weak self] in
            let initialThreadIDs = await catalog.activeThreadIDs()
            guard !Task.isCancelled else { return }
            self?.restoreSnapshots(
                storedEvents,
                activeCodexThreadIDs: initialThreadIDs,
                resolver: resolver
            )
            await self?.synchronizeCodexReadySessions(using: catalog)

            var reconciliationCount = 0
            while !Task.isCancelled {
                try? await Task.sleep(
                    nanoseconds: Self.lifecycleReconciliationInterval
                )
                guard !Task.isCancelled else { return }

                await self?.synchronizeCodexReadySessions(using: catalog)

                let candidates = self?.codexLifecycleCandidates() ?? []
                for candidate in candidates {
                    guard let completedAt = await catalog
                        .latestTerminalTurnCompletionDate(
                            threadID: candidate.sessionID
                        ),
                          completedAt >= candidate.updatedAt else {
                        continue
                    }
                    guard !Task.isCancelled else { return }
                    self?.removeTerminatedCodexSession(
                        candidate,
                        completedAt: completedAt
                    )
                }

                reconciliationCount += 1
                if reconciliationCount
                    .isMultiple(of: Self.catalogReconciliationFrequency),
                   let activeThreadIDs = await catalog.activeThreadIDs() {
                    guard !Task.isCancelled else { return }
                    self?.removeStaleCodexSessions(
                        activeThreadIDs: activeThreadIDs
                    )
                }
            }
        }
    }

    private func synchronizeCodexReadySessions(
        using catalog: CodexThreadCatalog
    ) async {
        guard let unreadThreadIDs = await codexUnreadStateReader
            .localUnreadThreadIDs() else {
            return
        }
        let missingThreadIDs = sessionStore.reconcileCodexReadyThreadIDs(
            unreadThreadIDs
        )
        for threadID in missingThreadIDs {
            guard !Task.isCancelled else { return }
            guard let metadata = await catalog.metadata(threadID: threadID) else {
                continue
            }
            sessionStore.upsertCodexReadyThread(metadata)
        }
    }

    private func codexLifecycleCandidates() -> [CodexLifecycleCandidate] {
        sessionStore.codexLifecycleSessions.map { session in
            CodexLifecycleCandidate(
                sessionID: session.providerSessionID,
                updatedAt: session.updatedAt
            )
        }
    }

    private func removeTerminatedCodexSession(
        _ candidate: CodexLifecycleCandidate,
        completedAt: Date
    ) {
        guard sessionStore.removeSession(
            provider: .codex,
            providerSessionID: candidate.sessionID,
            notUpdatedAfter: completedAt
        ) != nil else {
            return
        }
        eventSnapshotStore.remove(
            provider: .codex,
            sessionID: candidate.sessionID
        )
    }

    private func restoreSnapshots(
        _ events: [HookEventEnvelope],
        activeCodexThreadIDs: Set<String>?,
        resolver: CodexSessionNameResolver
    ) {
        let reconciliation = SessionSnapshotReconciler.reconcile(
            events,
            activeCodexThreadIDs: activeCodexThreadIDs
        )
        for route in reconciliation.staleRoutes {
            eventSnapshotStore.remove(provider: route.provider, sessionID: route.sessionID)
        }
        for event in reconciliation.restorableEvents {
            apply(event, resolvingNameWith: resolver)
        }
    }

    private func removeStaleCodexSessions(activeThreadIDs: Set<String>) {
        let removed = sessionStore.removeSessions(provider: .codex, notIn: activeThreadIDs)
        for session in removed {
            eventSnapshotStore.remove(
                provider: .codex,
                sessionID: session.providerSessionID
            )
        }
    }

    private func apply(
        _ event: HookEventEnvelope,
        resolvingNameWith resolver: CodexSessionNameResolver
    ) {
        sessionStore.apply(event)
        guard event.provider == .codex,
              !event.clearsActiveSession else { return }

        let id = SessionEventRouter.sessionIdentifier(
            provider: event.provider,
            sessionID: event.sessionID
        )
        if event.eventName == "PreToolUse" || event.eventName == "PostToolUse" {
            let activityResolver = codexActivityMessageResolver
            Task { @MainActor [weak sessionStore] in
                guard let message = await activityResolver.latestMessage(
                    for: event.sessionID
                ) else {
                    return
                }
                sessionStore?.updateRunningSummary(
                    message,
                    for: id,
                    matching: event.timestamp
                )
            }
        }
        let refresh = event.eventName == "SessionStart"
            || event.eventName == "UserPromptSubmit"
        Task { @MainActor [weak sessionStore] in
            guard let name = await resolver.name(
                for: event.sessionID,
                refresh: refresh
            ) else {
                return
            }
            sessionStore?.updateSessionName(name, for: id)
        }
    }
}
