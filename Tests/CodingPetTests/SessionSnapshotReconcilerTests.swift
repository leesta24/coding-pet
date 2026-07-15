import Foundation
import Testing
import CodingPetBridge
@testable import CodingPet

struct SessionSnapshotReconcilerTests {
    @Test
    func excludesArchivedCodexAndTerminalSnapshotsButKeepsClaude() {
        let activeCodex = event(provider: .codex, name: "UserPromptSubmit", sessionID: "active")
        let archivedCodex = event(provider: .codex, name: "PostToolUse", sessionID: "archived")
        let claude = event(provider: .claudeCode, name: "PermissionRequest", sessionID: "claude")
        let claudeStopped = event(provider: .claudeCode, name: "Stop", sessionID: "claude-ready")
        let stopped = event(provider: .codex, name: "Stop", sessionID: "stopped")
        let started = event(provider: .claudeCode, name: "SessionStart", sessionID: "started")

        let result = SessionSnapshotReconciler.reconcile(
            [activeCodex, archivedCodex, claude, claudeStopped, stopped, started],
            activeCodexThreadIDs: ["active"]
        )

        #expect(result.restorableEvents == [activeCodex, claude, claudeStopped])
        #expect(result.staleRoutes == [
            HookSessionRoute(provider: .codex, sessionID: "archived"),
            HookSessionRoute(provider: .codex, sessionID: "stopped"),
            HookSessionRoute(provider: .claudeCode, sessionID: "started")
        ])
    }

    @Test
    func unavailableCatalogPreservesActiveCodexAndClaudeReadySnapshots() {
        let codex = event(provider: .codex, name: "PreToolUse", sessionID: "unknown")
        let stopped = event(provider: .claudeCode, name: "Stop", sessionID: "stopped")

        let result = SessionSnapshotReconciler.reconcile(
            [codex, stopped],
            activeCodexThreadIDs: nil
        )

        #expect(result.restorableEvents == [codex, stopped])
        #expect(result.staleRoutes.isEmpty)
    }

    private func event(
        provider: HookProvider,
        name: String,
        sessionID: String
    ) -> HookEventEnvelope {
        HookEventEnvelope(
            provider: provider,
            eventName: name,
            timestamp: Date(timeIntervalSince1970: 1),
            parentProcessID: nil,
            sessionID: sessionID,
            cwd: "/tmp/project"
        )
    }
}
