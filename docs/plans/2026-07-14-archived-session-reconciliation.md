# Archived Session Reconciliation Implementation Plan

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.

**Goal:** Remove archived or deleted Codex sessions from CodingPet while preserving active sessions and safe fallback behavior.

**Architecture:** Query the local Codex app-server `thread/list` method with `archived: false` and `useStateDbOnly: true`, then reconcile metadata-only hook snapshots and in-memory sessions against the returned thread IDs. Treat an unavailable or malformed app-server response as “unknown” and retain existing Codex sessions. Make `SessionEnd` delete its snapshot immediately instead of persisting a terminal record.

**Tech Stack:** Swift 6.2, Foundation, Swift concurrency, Codex app-server JSON-RPC, Swift Testing.

---

### Task 1: Make terminal snapshots self-cleaning

**Files:**
- Modify: `Sources/CodingPetBridge/HookEventSnapshotStore.swift`
- Test: `Tests/CodingPetTests/HookEventSnapshotStoreTests.swift`

1. Add a failing test that persists an active event followed by `SessionEnd` and expects the snapshot to disappear.
2. Run `swift test --filter HookEventSnapshotStoreTests` and confirm failure.
3. Make `persist` route `SessionEnd` through `remove(provider:sessionID:)`.
4. Re-run the focused tests.

### Task 2: Add a non-archived Codex thread catalog

**Files:**
- Create: `Sources/CodingPet/Services/CodexThreadCatalog.swift`
- Create: `Tests/CodingPetTests/CodexThreadCatalogTests.swift`

1. Add tests for pagination, malformed responses, and repeated cursors.
2. Implement a reusable app-server session that calls `thread/list` with `archived: false`, pages through every result, and returns only validated thread IDs.
3. Return `nil` on any protocol or process failure so callers retain sessions rather than deleting them.
4. Run `swift test --filter CodexThreadCatalogTests`.

### Task 3: Reconcile stored and live sessions

**Files:**
- Create: `Sources/CodingPet/Services/SessionSnapshotReconciler.swift`
- Modify: `Sources/CodingPet/Services/SessionStore.swift`
- Modify: `Sources/CodingPet/CodingPetMain.swift`
- Create: `Tests/CodingPetTests/SessionSnapshotReconcilerTests.swift`
- Modify: `Tests/CodingPetTests/ProviderEventAdapterTests.swift`

1. Add failing tests showing archived Codex snapshots are excluded, Claude snapshots remain, and a failed catalog lookup preserves Codex snapshots.
2. Add a provider-scoped `SessionStore` removal operation and test that it leaves other providers untouched.
3. Start the bot without restoring stale rows, asynchronously query the catalog, restore only valid snapshots, and remove stale snapshot files.
4. Reconcile live Codex sessions every 15 seconds; cancel the task on app termination.
5. Keep live hook timestamp ordering intact so old snapshots cannot overwrite newer events.

### Task 4: Verify against the real local state

**Files:**
- Modify: `HANDOFF.md`
- Modify: `README.md`

1. Run `swift test` and require all tests to pass.
2. Restart CodingPet.
3. Verify the current `109` visible rows fall to the intersection of CodingPet snapshots and non-archived Codex thread IDs.
4. Archive one visible Codex task and verify it disappears within one reconciliation interval.
