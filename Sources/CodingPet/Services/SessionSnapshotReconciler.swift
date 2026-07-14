import Foundation
import CodingPetBridge

struct HookSessionRoute: Hashable, Sendable {
    let provider: HookProvider
    let sessionID: String
}

struct SessionSnapshotReconciliation: Equatable, Sendable {
    let restorableEvents: [HookEventEnvelope]
    let staleRoutes: Set<HookSessionRoute>
}

enum SessionSnapshotReconciler {
    static func reconcile(
        _ events: [HookEventEnvelope],
        activeCodexThreadIDs: Set<String>?
    ) -> SessionSnapshotReconciliation {
        var restorableEvents: [HookEventEnvelope] = []
        var staleRoutes: Set<HookSessionRoute> = []

        for event in events {
            let route = HookSessionRoute(provider: event.provider, sessionID: event.sessionID)
            if event.clearsActiveSession {
                staleRoutes.insert(route)
                continue
            }
            if event.provider == .codex,
               let activeCodexThreadIDs,
               !activeCodexThreadIDs.contains(event.sessionID) {
                staleRoutes.insert(route)
                continue
            }
            restorableEvents.append(event)
        }

        return SessionSnapshotReconciliation(
            restorableEvents: restorableEvents,
            staleRoutes: staleRoutes
        )
    }
}
